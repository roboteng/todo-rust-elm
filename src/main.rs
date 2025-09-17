use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::app::*;

mod app;
mod auth;

#[tokio::main]
async fn main() {
    dotenv::dotenv().ok();
    let env = Env {
        port: 3000,
        host: "0.0.0.0".to_string(),
        cookie_secret: std::env::var("COOKIE_SECRET").expect("COOKIE_SECRET must be set"),
    };

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| {
                format!("{}=debug,tower_http=debug", env!("CARGO_CRATE_NAME")).into()
            }),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    run_app(env).await;
}
