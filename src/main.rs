use axum::{
    Router,
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    response::IntoResponse,
    routing::any,
};
use axum_extra::{TypedHeader, headers};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

use std::ops::ControlFlow;
use std::{net::SocketAddr, path::PathBuf, sync::Arc};
use tower_http::{
    services::ServeDir,
    trace::{DefaultMakeSpan, TraceLayer},
};

use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

//allows to extract the IP of connecting user
use axum::extract::connect_info::ConnectInfo;

//allows to split the websocket stream into separate TX and RX branches
use futures_util::{
    sink::SinkExt,
    stream::{SplitSink, StreamExt},
};

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| {
                format!("{}=debug,tower_http=debug", env!("CARGO_CRATE_NAME")).into()
            }),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let assets_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");

    // build our application with some routes
    let app = Router::new()
        .fallback_service(ServeDir::new(assets_dir).append_index_html_on_directories(true))
        .route("/ws", any(ws_handler))
        // logging so we can see what's going on
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(DefaultMakeSpan::default().include_headers(true)),
        );

    // run it with hyper
    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
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

/// The handler for the HTTP request (this gets called when the HTTP request lands at the start
/// of websocket negotiation). After this completes, the actual switching from HTTP to
/// websocket protocol will occur.
/// This is the last point where we can extract TCP/IP metadata such as IP address of the client
/// as well as things from HTTP headers such as user-agent of the browser etc.
async fn ws_handler(
    ws: WebSocketUpgrade,
    user_agent: Option<TypedHeader<headers::UserAgent>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
) -> impl IntoResponse {
    let user_agent = if let Some(TypedHeader(user_agent)) = user_agent {
        user_agent.to_string()
    } else {
        String::from("Unknown browser")
    };
    println!("`{user_agent}` at {addr} connected.");
    // finalize the upgrade process by returning upgrade callback.
    // we can customize the callback by sending additional info such as address.
    ws.on_upgrade(move |socket| handle_socket(socket, addr))
}

/// Actual websocket statemachine (one will be spawned per connection)
async fn handle_socket(socket: WebSocket, who: SocketAddr) {
    // By splitting socket we can send and receive at the same time. In this example we will send
    // unsolicited messages to client based on some sort of server's internal event (i.e .timer).
    let (sender, mut receiver) = socket.split();
    let sender = Arc::new(Mutex::new(sender));

    // This second task will receive messages from client and print them on server console
    let recv_task = tokio::spawn(async move {
        let mut cnt = 0;
        while let Some(Ok(msg)) = receiver.next().await {
            cnt += 1;
            // print message and break if instructed to do so
            if process_message(msg, who, sender.clone()).is_break() {
                break;
            }
        }
        cnt
    });

    recv_task.await.unwrap();

    // returning from the handler closes the websocket connection
    println!("Websocket context {who} destroyed");
}

#[derive(Debug, Serialize)]
#[serde(tag = "action", content = "payload", rename_all = "snake_case")]
enum OutMsg {
    Greet(String),
}

#[derive(Debug, Deserialize)]
#[serde(tag = "action", content = "payload", rename_all = "snake_case")]
enum InMsg {
    Greet(String),
    StartScanning,
}

type Shared<T> = Arc<Mutex<T>>;

/// helper to print contents of messages to stdout. Has special treatment for Close.
fn process_message(
    msg: Message,
    who: SocketAddr,
    sender: Shared<SplitSink<WebSocket, Message>>,
) -> ControlFlow<(), ()> {
    match msg {
        Message::Text(t) => {
            let k = serde_json::from_str::<InMsg>(t.as_str());

            match k {
                Ok(InMsg::Greet(s)) => {
                    let name = s.clone();
                    tokio::spawn(async move {
                        let mut send = sender.lock().await;
                        send.send(Message::Text(
                            serde_json::to_string(&OutMsg::Greet(format!(
                                "Hello, {name}!, You've been greeted from the other side"
                            )))
                            .unwrap()
                            .into(),
                        ))
                        .await
                        .unwrap();
                    });
                    tracing::info!("Got greet: {s}");
                }
                Ok(InMsg::StartScanning) => tracing::info!("Got start_scanning"),
                Err(e) => {
                    tracing::error!("Unhandled message: {e}");
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
