use axum::{
    Json, Router,
    extract::{
        FromRef, FromRequestParts, State,
        ws::{Message, WebSocket, WebSocketUpgrade},
    },
    http::{StatusCode, request::Parts},
    response::{IntoResponse, Response},
    routing::{any, post},
};
use axum_extra::{
    TypedHeader,
    extract::{
        PrivateCookieJar,
        cookie::{Cookie, Key, SameSite},
    },
    headers,
};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;
use tracing::instrument;

use std::ops::ControlFlow;
use std::{collections::HashMap, net::SocketAddr, path::PathBuf, sync::Arc};
use tower_http::{
    services::{ServeDir, ServeFile},
    trace::{DefaultMakeSpan, TraceLayer},
};

use crate::auth::*;
use futures_util::{
    sink::SinkExt,
    stream::{SplitSink, StreamExt},
};

type WsSender = Arc<Mutex<SplitSink<WebSocket, Message>>>;

#[derive(Clone)]
struct AppState {
    tasks: Arc<Mutex<HashMap<UserId, Tasks>>>,
    clients: Arc<Mutex<HashMap<SessionId, WsSender>>>,
    users: Arc<Mutex<Users>>,
    key: Key,
}

impl AppState {
    pub fn new(key: [u8; 64]) -> Self {
        let key = Key::from(&key);
        Self {
            tasks: Arc::new(Mutex::new(HashMap::new())),
            clients: Arc::new(Mutex::new(HashMap::new())),
            users: Arc::new(Mutex::new(Users::default())),
            key,
        }
    }
}

impl FromRef<AppState> for Key {
    fn from_ref(input: &AppState) -> Self {
        input.key.clone()
    }
}

pub struct Env {
    pub port: u16,
    pub host: String,
    pub cookie_secret: String,
}

pub async fn run_app(env: Env) {
    let assets_dir = PathBuf::from(".").join("assets");

    let key = env.cookie_secret.as_bytes().first_chunk().unwrap();
    let app_state = AppState::new(*key);

    let app = make_app(assets_dir, app_state);

    let listener = tokio::net::TcpListener::bind(format!("{}:{}", env.host, env.port))
        .await
        .unwrap();
    tracing::debug!("listening on http://{}", listener.local_addr().unwrap());
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .unwrap();
}

fn make_app(assets_dir: PathBuf, app_state: AppState) -> Router {
    Router::new()
        .fallback_service(
            ServeDir::new(&assets_dir).fallback(ServeFile::new(assets_dir.join("index.html"))),
        )
        .route("/ws", any(ws_handler))
        .route("/api/register", post(handle_register))
        .route("/api/login", post(handle_login))
        .route("/api/logout", post(handle_logout))
        .with_state(app_state)
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(DefaultMakeSpan::default().include_headers(false)),
        )
}

#[derive(Debug, Clone, Copy)]
struct AuthedUser {
    session_id: SessionId,
    user_id: UserId,
}

impl FromRequestParts<AppState> for AuthedUser {
    #[doc = " If the extractor fails it\'ll use this `Rejection` type. A rejection is"]
    #[doc = " a kind of error that can be converted into a response."]
    type Rejection = StatusCode;

    #[doc = " Perform the extraction."]
    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let jar = PrivateCookieJar::<Key>::from_request_parts(parts, state)
            .await
            .map_err(|_| StatusCode::UNAUTHORIZED)?;
        let cookie = jar.get("session").ok_or(StatusCode::UNAUTHORIZED)?;
        let session = cookie.value();
        let session_id = session.parse().map_err(|_| StatusCode::UNAUTHORIZED)?;
        let user_id = state
            .users
            .lock()
            .await
            .get_session(session_id)
            .ok_or(StatusCode::UNAUTHORIZED)?;
        Ok(AuthedUser {
            session_id,
            user_id,
        })
    }
}

/// The handler for the HTTP request (this gets called when the HTTP request lands at the start
/// of websocket negotiation). After this completes, the actual switching from HTTP to
/// websocket protocol will occur.
/// This is the last point where we can extract TCP/IP metadata such as IP address of the client
/// as well as things from HTTP headers such as user-agent of the browser etc.
#[axum::debug_handler]
#[instrument(skip(ws, app_state, user_agent))]
async fn ws_handler(
    ws: WebSocketUpgrade,
    State(app_state): State<AppState>,
    user_agent: Option<TypedHeader<headers::UserAgent>>,
    user: AuthedUser,
) -> impl IntoResponse {
    let user_agent = if let Some(TypedHeader(user_agent)) = user_agent {
        user_agent.to_string()
    } else {
        String::from("Unknown browser")
    };
    tracing::debug!("`{user_agent}` for session {} connected.", user.session_id);
    ws.on_upgrade(move |socket| handle_socket(socket, user, app_state))
}

#[instrument(skip(socket, app_state))]
async fn handle_socket(socket: WebSocket, session: AuthedUser, app_state: AppState) {
    // By splitting socket we can send and receive at the same time. In this example we will send
    // unsolicited messages to client based on some sort of server's internal event (i.e .timer).
    let (sender, mut receiver) = socket.split();
    let sender = Arc::new(Mutex::new(sender));

    app_state
        .clients
        .lock()
        .await
        .insert(session.session_id, sender.clone());

    // Send current tasks to the newly connected client
    {
        let tasks_map = app_state.tasks.lock().await;
        let ts = Tasks::default();
        let tasks = tasks_map.get(&session.user_id).unwrap_or(&ts);
        let send = sender.lock().await;
        let new_tasks = OutMsg::NewTasks(tasks.clone());
        let sent = send_outmsg(send, new_tasks).await;
        if let Err(e) = sent {
            tracing::error!(
                "Failed to send initial tasks to user {}: {}",
                session.user_id,
                e
            );
        }
    }

    // This second task will receive messages from client and print them on server console
    let app_state_clone = app_state.clone();
    let recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            process_message(msg, session, sender.clone(), app_state_clone.clone()).await?;
        }
        ControlFlow::Continue(())
    });

    let _ = recv_task.await.unwrap();

    app_state.clients.lock().await.remove(&session.session_id);

    tracing::debug!(
        "Websocket context for session {} destroyed",
        session.session_id
    );
}

async fn send_outmsg(
    mut send: tokio::sync::MutexGuard<'_, SplitSink<WebSocket, Message>>,
    new_tasks: OutMsg,
) -> Result<(), axum::Error> {
    tracing::debug!(?new_tasks);
    send.send(Message::Text(
        serde_json::to_string(&new_tasks).unwrap().into(),
    ))
    .await
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
struct Task {
    id: i32,
    summary: String,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
struct Tasks {
    tasks: Vec<Task>,
    next_id: i32,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq, Clone)]
#[serde(tag = "action", content = "payload", rename_all = "snake_case")]
enum OutMsg {
    NewTasks(Tasks),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
#[serde(tag = "action", content = "payload", rename_all = "snake_case")]
enum InMsg {
    Tasks(Tasks),
}

type Shared<T> = Arc<Mutex<T>>;

#[instrument(skip(app_state))]
async fn broadcast_tasks(app_state: &AppState, user_id: u64) {
    let tasks_stored = app_state.tasks.lock().await;
    let tasks = match tasks_stored.get(&user_id) {
        Some(tasks) => tasks,
        None => return,
    };
    let message = Message::Text(
        serde_json::to_string(&OutMsg::NewTasks(tasks.clone()))
            .unwrap()
            .into(),
    );

    let sessions = app_state.users.lock().await.get_sessions(user_id);
    let clients = app_state.clients.lock().await;
    let user_clients = clients
        .iter()
        .filter(|(entry_session, _)| sessions.contains(entry_session));
    for (session_id, sender) in user_clients {
        let mut send = sender.lock().await;
        if let Err(e) = send.send(message.clone()).await {
            tracing::error!(
                "Failed to send tasks update to session {}: {}",
                session_id,
                e
            );
        }
    }

    tracing::debug!(
        "Broadcasted tasks to {} clients: {} tasks, next_id: {}",
        sessions.len(),
        tasks.tasks.len(),
        tasks.next_id
    );
}

/// helper to print contents of messages to stdout. Has special treatment for Close.
#[instrument(skip(_sender, app_state))]
async fn process_message(
    msg: Message,
    session: AuthedUser,
    _sender: Shared<SplitSink<WebSocket, Message>>,
    app_state: AppState,
) -> ControlFlow<(), ()> {
    match msg {
        Message::Text(t) => {
            let k = serde_json::from_str::<InMsg>(t.as_str());

            match k {
                Ok(InMsg::Tasks(client_tasks)) => {
                    // Client is source of truth - replace server state with client state
                    {
                        let mut current_state = app_state.tasks.lock().await;
                        current_state.insert(session.user_id, client_tasks);
                    }

                    // Broadcast the updated tasks to ALL connected clients
                    broadcast_tasks(&app_state, session.user_id).await;
                }
                Err(e) => {
                    tracing::error!(
                        "Unhandled message from session {}: {}",
                        session.session_id,
                        e
                    );
                }
            }
        }
        Message::Binary(d) => {
            println!(
                ">>> session {} sent {} bytes: {d:?}",
                session.session_id,
                d.len()
            );
        }
        Message::Close(c) => {
            if let Some(cf) = c {
                println!(
                    ">>> session {} sent close with code {} and reason `{}`",
                    session.session_id, cf.code, cf.reason
                );
            } else {
                println!(
                    ">>> user {} somehow sent close message without CloseFrame",
                    session.user_id
                );
            }
            return ControlFlow::Break(());
        }

        Message::Pong(v) => {
            println!(">>> session {} sent pong with {v:?}", session.user_id);
        }
        // You should never need to manually handle Message::Ping, as axum's websocket library
        // will do so for you automagically by replying with Pong and copying the v according to
        // spec. But if you need the contents of the pings you can see them here.
        Message::Ping(v) => {
            println!(">>> session {} sent ping with {v:?}", session.user_id);
        }
    }
    ControlFlow::Continue(())
}

#[derive(Debug, Deserialize)]
struct RegisterRequest {
    username: String,
    password: String,
}

#[axum::debug_handler]
#[instrument(skip_all)]
async fn handle_register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> impl IntoResponse {
    let mut users = state.users.lock().await;
    match UserData::new(req.username, req.password)
        .ok()
        .and_then(|user| users.try_add(user))
    {
        Some(_) => StatusCode::CREATED,
        None => StatusCode::CONFLICT,
    }
}

#[axum::debug_handler]
#[instrument(skip_all)]
async fn handle_login(
    State(state): State<AppState>,
    jar: PrivateCookieJar,
    Json(req): Json<RegisterRequest>,
) -> Response {
    let mut users = state.users.lock().await;
    match users.try_login(req.username, req.password) {
        Some(session_id) => {
            let mut cookie = Cookie::new("session", format!("{session_id}"));
            cookie.set_path("/");
            cookie.set_http_only(true);
            cookie.set_same_site(SameSite::Strict);
            let jar = jar.add(cookie);
            (jar, StatusCode::OK).into_response()
        }
        None => StatusCode::UNAUTHORIZED.into_response(),
    }
}

#[axum::debug_handler]
#[instrument(skip_all)]
async fn handle_logout(
    State(state): State<AppState>,
    jar: PrivateCookieJar,
    session: AuthedUser,
) -> impl IntoResponse {
    let mut users = state.users.lock().await;
    users.logout_session(session.session_id);
    let jar = jar.remove("session");
    (jar, StatusCode::NO_CONTENT).into_response()
}

#[cfg(test)]
mod tests {
    use axum::http::StatusCode;
    use axum_test::{TestServer, Transport};
    #[allow(unused_imports)]
    use pretty_assertions::{assert_eq, assert_ne, assert_str_eq};
    use serde_json::json;
    use std::time::Duration;
    use tokio::time::timeout;

    use super::*;

    #[tokio::test]
    async fn unit_websocket() {
        let server = test_server_http();

        // Register and login user
        let user_data = json!({
            "username": "testuser",
            "password": "testpass"
        });

        server.post("/api/register").json(&user_data).await;
        let login_response = server.post("/api/login").json(&user_data).await;
        login_response.assert_status(StatusCode::OK);

        let mut websocket = server.get_websocket("/ws").await.into_websocket().await;

        let test_tasks = Tasks::single_task();
        websocket.send_inmsg(InMsg::Tasks(test_tasks.clone())).await;

        // First message should be initial empty tasks
        let initial_response = websocket.receive_outmsg().await;
        assert_eq!(initial_response, OutMsg::NewTasks(Tasks::default()));

        // Second message should be the updated tasks
        let updated_response = websocket.receive_outmsg().await;
        assert_eq!(updated_response, OutMsg::NewTasks(test_tasks));

        websocket.close().await;
    }

    #[tokio::test]
    async fn unit_websocket_unauthenticated() {
        let server = test_server_http();

        let ws_result = server.get_websocket("/ws").await;

        assert_eq!(ws_result.status_code(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn unit_register() {
        let server = test_server();

        let request_body = json!({
            "username": "testuser",
            "password": "testpass"
        });

        let response = server.post("/api/register").json(&request_body).await;

        response.assert_status(StatusCode::CREATED);
    }

    #[tokio::test]
    async fn unit_register_missing_username() {
        let server = test_server();

        let request_body = json!({
            "password": "testpass"
        });

        let response = server.post("/api/register").json(&request_body).await;

        response.assert_status(StatusCode::UNPROCESSABLE_ENTITY);
    }

    #[tokio::test]
    async fn unit_register_missing_password() {
        let server = test_server();

        let request_body = json!({
            "username": "testuser"
        });

        let response = server.post("/api/register").json(&request_body).await;

        response.assert_status(StatusCode::UNPROCESSABLE_ENTITY);
    }

    #[tokio::test]
    async fn unit_register_duplicate() {
        let server = test_server();

        let request_body = json!({
            "username": "testuser",
            "password": "testpass"
        });

        let _response1 = server.post("/api/register").json(&request_body).await;
        let response2 = server.post("/api/register").json(&request_body).await;
        response2.assert_status(StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn unit_two_registers() {
        let server = test_server();

        let request_body1 = json!({
            "username": "testuser",
            "password": "testpass"
        });

        let request_body2 = json!({
            "username": "testuser2",
            "password": "testpass2"
        });

        let _response1 = server.post("/api/register").json(&request_body1).await;
        let response2 = server.post("/api/register").json(&request_body2).await;
        response2.assert_status(StatusCode::CREATED);
    }

    #[tokio::test]
    async fn unit_login() {
        let server = test_server();

        let request_body = json!({
            "username": "testuser",
            "password": "testpass"
        });
        server.post("/api/register").json(&request_body).await;

        let response = server.post("/api/login").json(&request_body).await;

        response.assert_status(StatusCode::OK);
        response.cookies().get("session").expect("Cookie not found");
    }

    #[tokio::test]
    async fn unit_no_register_login() {
        let server = test_server();

        let request_body = json!({
            "username": "testuser",
            "password": "testpass"
        });

        let response = server.post("/api/login").json(&request_body).await;

        response.assert_status(StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn unit_login_bad_password() {
        let server = test_server();

        let register_body = json!({
            "username": "testuser",
            "password": "testpass"
        });

        let login_body = json!({
            "username": "testuser",
            "password": "bad_password"
        });

        server.post("/api/register").json(&register_body).await;
        let response = server.post("/api/login").json(&login_body).await;

        response.assert_status(StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn unit_one_user_logged_in_twice_gets_updates() {
        let server = test_server_http();

        let request_body = json!({
            "username": "testuser",
            "password": "testpass"
        });
        server.post("/api/register").json(&request_body).await;

        let client1 = server.post("/api/login").json(&request_body).await;
        let client2 = server.post("/api/login").json(&request_body).await;
        let mut ws1 = server
            .get_websocket("/ws")
            .add_cookie(client1.cookie("session"))
            .await
            .into_websocket()
            .await;
        let mut ws2 = server
            .get_websocket("/ws")
            .add_cookie(client2.cookie("session"))
            .await
            .into_websocket()
            .await;

        ws1.send_text(serde_json::to_string(&InMsg::Tasks(Tasks::single_task())).unwrap())
            .await;
        let _msg = ws2.receive_outmsg().await;
        let msg = ws2.receive_outmsg().await;

        assert_eq!(msg, OutMsg::NewTasks(Tasks::single_task()));
    }

    #[tokio::test]
    async fn unit_two_users_logged_do_not_get_updates_from_the_other() {
        let server = test_server_http();

        let user1 = json!({
            "username": "testuser",
            "password": "testpass"
        });

        let user2 = json!({
            "username": "testuser2",
            "password": "testpass2"
        });
        server.post("/api/register").json(&user1).await;
        server.post("/api/register").json(&user2).await;

        let client1 = server.post("/api/login").json(&user1).await;
        let client2 = server.post("/api/login").json(&user2).await;
        let mut ws1 = server
            .get_websocket("/ws")
            .add_cookie(client1.cookie("session"))
            .await
            .into_websocket()
            .await;
        let mut ws2 = server
            .get_websocket("/ws")
            .add_cookie(client2.cookie("session"))
            .await
            .into_websocket()
            .await;

        let _msg = ws1.receive_outmsg().await;
        let _msg = ws2.receive_outmsg().await;

        let user1_tasks = Tasks {
            tasks: vec![Task {
                id: 0,
                summary: "Task 1".to_string(),
            }],
            next_id: 1,
        };

        let user2_tasks = Tasks {
            tasks: vec![Task {
                id: 0,
                summary: "different task".to_string(),
            }],
            next_id: 1,
        };

        ws1.send_inmsg(InMsg::Tasks(user1_tasks)).await;
        ws2.send_inmsg(InMsg::Tasks(user2_tasks)).await;

        let msg1 = ws1.receive_outmsg().await;
        let msg2 = ws2.receive_outmsg().await;

        assert_ne!(msg1, msg2);
    }

    #[tokio::test]
    async fn unit_logout() {
        let server = test_server_http();

        let user_data = json!({
            "username": "testuser",
            "password": "testpass"
        });

        server.post("/api/register").json(&user_data).await;
        let _ = server.post("/api/login").json(&user_data).await;

        let logout_response = server.post("/api/logout");
        logout_response.await.assert_status(StatusCode::NO_CONTENT);

        let response = server.get_websocket("/ws").await;
        response.assert_status(StatusCode::UNAUTHORIZED);
    }

    fn test_server() -> TestServer {
        let temp = std::env::temp_dir();
        let app_state = AppState::new([42; 64]);
        let app = make_app(temp, app_state);

        TestServer::new(app).unwrap()
    }

    fn test_server_http() -> TestServer {
        let temp = std::env::temp_dir();
        let app_state = AppState::new([42; 64]);
        let app = make_app(temp, app_state);

        let mut config = axum_test::TestServerConfig::new();
        config.save_cookies = true;
        config.transport = Some(Transport::HttpRandomPort);

        TestServer::new_with_config(app, config).unwrap()
    }

    impl Tasks {
        fn single_task() -> Self {
            Self {
                tasks: vec![Task {
                    id: 1,
                    summary: "test".to_string(),
                }],
                next_id: 2,
            }
        }
    }

    trait TestWebSocketExt {
        async fn receive_outmsg(&mut self) -> OutMsg;
        async fn send_inmsg(&mut self, msg: impl Into<InMsg>);
    }
    impl TestWebSocketExt for axum_test::TestWebSocket {
        async fn receive_outmsg(&mut self) -> OutMsg {
            timeout(Duration::from_millis(10), async move {
                self.receive_json::<OutMsg>().await
            })
            .await
            .unwrap()
        }

        async fn send_inmsg(&mut self, msg: impl Into<InMsg>) {
            timeout(Duration::from_millis(10), async move {
                self.send_text(&serde_json::to_string(&msg.into()).unwrap())
                    .await
            })
            .await
            .unwrap();
        }
    }
}
