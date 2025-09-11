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

use std::ops::ControlFlow;
use std::{collections::HashMap, net::SocketAddr, path::PathBuf, sync::Arc};
use tower_http::{
    services::{ServeDir, ServeFile},
    trace::{DefaultMakeSpan, TraceLayer},
};

use axum::extract::connect_info::ConnectInfo;

use crate::auth::*;
use futures_util::{
    sink::SinkExt,
    stream::{SplitSink, StreamExt},
};

type WsSender = Arc<Mutex<SplitSink<WebSocket, Message>>>;

#[derive(Clone, Default)]
struct AppState {
    tasks: Arc<Mutex<Tasks>>,
    clients: Arc<Mutex<HashMap<SocketAddr, WsSender>>>,
    users: Arc<Mutex<Users>>,
}

impl FromRef<AppState> for Key {
    fn from_ref(_input: &AppState) -> Self {
        Key::from(&[42; 64])
    }
}

pub struct Env {
    pub port: u16,
    pub host: String,
}

pub async fn run_app(env: Env) {
    let assets_dir = PathBuf::from(".").join("assets");

    let app_state = AppState::default();

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
        .with_state(app_state)
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(DefaultMakeSpan::default().include_headers(false)),
        )
}

struct AuthedUser {
    #[allow(dead_code)]
    session_id: SessionId,
    #[allow(dead_code)]
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
async fn ws_handler(
    ws: WebSocketUpgrade,
    State(app_state): State<AppState>,
    user_agent: Option<TypedHeader<headers::UserAgent>>,
    _user: AuthedUser,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
) -> impl IntoResponse {
    let user_agent = if let Some(TypedHeader(user_agent)) = user_agent {
        user_agent.to_string()
    } else {
        String::from("Unknown browser")
    };
    tracing::debug!("`{user_agent}` at {addr} connected.");
    ws.on_upgrade(move |socket| handle_socket(socket, addr, app_state))
}

async fn handle_socket(socket: WebSocket, who: SocketAddr, app_state: AppState) {
    // By splitting socket we can send and receive at the same time. In this example we will send
    // unsolicited messages to client based on some sort of server's internal event (i.e .timer).
    let (sender, mut receiver) = socket.split();
    let sender = Arc::new(Mutex::new(sender));

    app_state.clients.lock().await.insert(who, sender.clone());

    // Send current tasks to the newly connected client
    {
        let tasks = app_state.tasks.lock().await;
        let mut send = sender.lock().await;
        let sent = send
            .send(Message::Text(
                serde_json::to_string(&OutMsg::NewTasks(tasks.clone()))
                    .unwrap()
                    .into(),
            ))
            .await;
        if let Err(e) = sent {
            tracing::error!("Failed to send initial tasks to client {}: {}", who, e);
        }
    }

    // This second task will receive messages from client and print them on server console
    let app_state_clone = app_state.clone();
    let recv_task = tokio::spawn(async move {
        let mut cnt = 0;
        while let Some(Ok(msg)) = receiver.next().await {
            cnt += 1;
            // print message and break if instructed to do so
            if process_message(msg, who, sender.clone(), app_state_clone.clone())
                .await
                .is_break()
            {
                break;
            }
        }
        cnt
    });

    recv_task.await.unwrap();

    app_state.clients.lock().await.remove(&who);

    tracing::debug!("Websocket context {who} destroyed");
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
struct NewTask {
    summary: String,
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

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "action", content = "payload", rename_all = "snake_case")]
enum OutMsg {
    NewTasks(Tasks),
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "action", content = "payload", rename_all = "snake_case")]
enum InMsg {
    Tasks(Tasks),
}

type Shared<T> = Arc<Mutex<T>>;

async fn broadcast_tasks_to_all(app_state: &AppState, tasks: &Tasks) {
    let clients = app_state.clients.lock().await;
    let message = Message::Text(
        serde_json::to_string(&OutMsg::NewTasks(tasks.clone()))
            .unwrap()
            .into(),
    );

    // Send to all connected clients
    for (addr, sender) in clients.iter() {
        let mut send = sender.lock().await;
        if let Err(e) = send.send(message.clone()).await {
            tracing::error!("Failed to send tasks update to client {}: {}", addr, e);
        }
    }

    tracing::debug!(
        "Broadcasted tasks to {} clients: {} tasks, next_id: {}",
        clients.len(),
        tasks.tasks.len(),
        tasks.next_id
    );
}

/// helper to print contents of messages to stdout. Has special treatment for Close.
async fn process_message(
    msg: Message,
    who: SocketAddr,
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
                        *current_state = client_tasks.clone();
                    }

                    // Broadcast the updated tasks to ALL connected clients
                    broadcast_tasks_to_all(&app_state, &client_tasks).await;
                }
                Err(e) => {
                    tracing::error!("Unhandled message from {}: {}", who, e);
                }
            }
        }
        Message::Binary(d) => {
            println!(">>> {who} sent {} bytes: {d:?}", d.len());
        }
        Message::Close(c) => {
            if let Some(cf) = c {
                println!(
                    ">>> {who} sent close with code {} and reason `{}`",
                    cf.code, cf.reason
                );
            } else {
                println!(">>> {who} somehow sent close message without CloseFrame");
            }
            return ControlFlow::Break(());
        }

        Message::Pong(v) => {
            println!(">>> {who} sent pong with {v:?}");
        }
        // You should never need to manually handle Message::Ping, as axum's websocket library
        // will do so for you automagically by replying with Pong and copying the v according to
        // spec. But if you need the contents of the pings you can see them here.
        Message::Ping(v) => {
            println!(">>> {who} sent ping with {v:?}");
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
async fn handle_register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> impl IntoResponse {
    let mut users = state.users.lock().await;
    match users.try_add(UserData::new(req.username, req.password)) {
        Some(_) => StatusCode::CREATED,
        None => StatusCode::CONFLICT,
    }
}

#[axum::debug_handler]
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

#[cfg(test)]
mod tests {
    use axum::{Extension, http::StatusCode};
    use axum_test::{TestServer, Transport};
    #[allow(unused_imports)]
    use pretty_assertions::{assert_eq, assert_ne, assert_str_eq};
    use serde_json::json;
    use std::net::{Ipv4Addr, SocketAddr};

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

    fn test_server() -> TestServer {
        let temp = std::env::temp_dir();
        let app_state = AppState::default();
        let app = make_app(temp, app_state);

        TestServer::new(app).unwrap()
    }

    fn test_server_http() -> TestServer {
        let temp = std::env::temp_dir();
        let app_state = AppState::default();

        let app = make_app(temp, app_state).layer(Extension(ConnectInfo(SocketAddr::from((
            Ipv4Addr::LOCALHOST,
            8080,
        )))));

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
            self.receive_json::<OutMsg>().await
        }

        async fn send_inmsg(&mut self, msg: impl Into<InMsg>) {
            self.send_text(&serde_json::to_string(&msg.into()).unwrap())
                .await;
        }
    }
}
