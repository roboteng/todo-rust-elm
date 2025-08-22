# Todo Web App

This runs as a web app connected to the back end with websockets.
It is designed to be local-first piece of software, meaning that if the connection to the backend goes down, the app will still keep working.

## Running

- `elm make elm-src/Main.elm --output assets/elm.js`
- `cargo run`
