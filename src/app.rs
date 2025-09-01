use axum::{
    Router,
    extract::{
        State,
        ws::{Message, WebSocket, WebSocketUpgrade},
    },
    response::IntoResponse,
    routing::any,
};
use axum_extra::{TypedHeader, headers};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

use std::ops::ControlFlow;
use std::{collections::HashMap, net::SocketAddr, path::PathBuf, sync::Arc};
use tower_http::{
    services::{ServeDir, ServeFile},
    trace::{DefaultMakeSpan, TraceLayer},
};

use axum::extract::connect_info::ConnectInfo;

use futures_util::{
    sink::SinkExt,
    stream::{SplitSink, StreamExt},
};

type WsSender = Arc<Mutex<SplitSink<WebSocket, Message>>>;

#[derive(Clone, Default)]
struct AppState {
    tasks: Arc<Mutex<Tasks>>,
    clients: Arc<Mutex<HashMap<SocketAddr, WsSender>>>,
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
        .with_state(app_state)
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(DefaultMakeSpan::default().include_headers(false)),
        )
}

/// The handler for the HTTP request (this gets called when the HTTP request lands at the start
/// of websocket negotiation). After this completes, the actual switching from HTTP to
/// websocket protocol will occur.
/// This is the last point where we can extract TCP/IP metadata such as IP address of the client
/// as well as things from HTTP headers such as user-agent of the browser etc.
async fn ws_handler(
    ws: WebSocketUpgrade,
    State(app_state): State<AppState>,
    user_agent: Option<TypedHeader<headers::UserAgent>>,
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

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
struct Task {
    id: i32,
    summary: String,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Default)]
#[serde(rename_all = "snake_case")]
struct Tasks {
    tasks: Vec<Task>,
    next_id: i32,
}

#[derive(Debug, Serialize, Deserialize)]
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

#[cfg(test)]
mod tests {
    use futures_util::{SinkExt, StreamExt};
    use std::net::{Ipv4Addr, SocketAddr};
    use tokio_tungstenite::{connect_async, tungstenite::Message as TungsteniteMessage};

    use super::*;

    #[tokio::test]
    async fn test_websocket() {
        let listener = tokio::net::TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, 0)))
            .await
            .unwrap();
        let addr = listener.local_addr().unwrap();

        let temp = std::env::temp_dir();
        let app_state = AppState {
            tasks: Arc::new(Mutex::new(Tasks {
                tasks: vec![],
                next_id: 0,
            })),
            clients: Arc::new(Mutex::new(HashMap::new())),
        };
        let app = make_app(temp, app_state);

        // Spawn server in background
        tokio::spawn(async move {
            axum::serve(
                listener,
                app.into_make_service_with_connect_info::<SocketAddr>(),
            )
            .await
            .unwrap();
        });

        // Connect WebSocket client
        let url = format!("ws://{}/ws", addr);
        let (mut ws_stream, _) = connect_async(&url).await.unwrap();

        // Test sending tasks message
        let test_tasks = Tasks {
            tasks: vec![Task {
                id: 1,
                summary: "test".to_string(),
            }],
            next_id: 2,
        };
        let tasks_msg = serde_json::to_string(&InMsg::Tasks(test_tasks.clone())).unwrap();
        ws_stream
            .send(TungsteniteMessage::Text(tasks_msg))
            .await
            .unwrap();

        // First message should be initial empty tasks
        if let Some(msg) = ws_stream.next().await {
            let msg = msg.unwrap();
            if let TungsteniteMessage::Text(text) = msg {
                let response: OutMsg = serde_json::from_str(&text).unwrap();
                match response {
                    OutMsg::NewTasks(tasks) => {
                        // Should be empty initially
                        assert_eq!(tasks.tasks.len(), 0);
                        assert_eq!(tasks.next_id, 0);
                    }
                }
            }
        }

        // Second message should be our broadcasted update
        if let Some(msg) = ws_stream.next().await {
            let msg = msg.unwrap();
            if let TungsteniteMessage::Text(text) = msg {
                let response: OutMsg = serde_json::from_str(&text).unwrap();
                match response {
                    OutMsg::NewTasks(tasks) => {
                        assert_eq!(tasks.tasks.len(), 1);
                        assert_eq!(tasks.tasks[0].summary, "test");
                        assert_eq!(tasks.tasks[0].id, 1);
                        assert_eq!(tasks.next_id, 2);
                    }
                }
            }
        }
    }
}
