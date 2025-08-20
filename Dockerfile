FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json

# Install curl and Elm
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN curl -L https://github.com/elm/compiler/releases/download/0.19.1/binary-for-linux-64-bit.gz | gunzip -c >/usr/local/bin/elm
RUN chmod +x /usr/local/bin/elm

# Build application
COPY . .
# Build Elm first
RUN elm make elm-src/Main.elm --optimize --output=assets/elm.js
RUN cargo build --release --bin rust-elm

# We do not need the Rust toolchain to run the binary!
FROM debian:bookworm-slim AS runtime
WORKDIR /app
COPY --from=builder /app/target/release/rust-elm /usr/local/bin
COPY --from=builder /app/assets ./assets
ENTRYPOINT ["/usr/local/bin/rust-elm"]
