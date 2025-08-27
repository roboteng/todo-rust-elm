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

## Design Choices

### The client is the source of truth

Since this app essentially just storing things that the user has asked it to store, the server should always defer choices to the client.
The servers job is to manage the data between clients.

### Authentication

As this is a local-first app, users don't need to authenticate to use it.
Users are able to start using it right away, but authentication is required to sync data between devices.
Authentication is not required to use the app on a single device.
