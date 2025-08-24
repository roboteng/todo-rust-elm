# Todo Web App

This runs as a web app connected to the back end with websockets.
It is designed to be local-first piece of software, meaning that if the connection to the backend goes down, the app will still keep working.

## Motivation

I'm building a Todo app for myself.The existing solutions (mostly Todoist and Nozbe) aren't good enough because:

- Clarifying seems cumbersome
- Switching contexts is too hard
- Contexts must be manually added
- Separation between subtasks and projects is unclear

## Running

- `elm make elm-src/Main.elm --output assets/elm.js`
- `cargo run`
