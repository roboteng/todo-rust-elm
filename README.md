# Todo Web App

This runs as a web app connected to the back end with websockets.
It is designed to be local-first piece of software, meaning that if the connection to the backend goes down, the app will still keep working.

## Motivation

I'm building a Todo app for myself.The existing solutions (mostly Todoist and Nozbe) aren't good enough because:

- Clarifying seems cumbersome
- Switching contexts is too hard
- Contexts must be manually added
- Separation between subtasks and projects is unclear

https://gist.github.com/evancz/2b2ba366cae1887fe621

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
When authenticating, users will log in at the login page, and all calls to the server (apart from getting static files) will be authenticated, including the call to start a websocket connection.
Messages sent across a websocket are not authenticated at all.
Users create accounts with just a username and password.


### Data Model

Tasks are stored in different lists.
Each user has their own lists, and can create new lists as needed.
User can choose to share lists they have made with others, as well.

## Todos

- [ ] Add client data store (localstorage)
- [ ] Add server data storage (database)
- [ ] Serve static files from CDN
- [ ] Add authentication
- [ ] Add support for multiple lists
- [ ] Share lists between users
- [ ] Add task details view
- [ ] Progressive web app
- [ ] USe LLM to suggest labels and metadata
- [ ] Voice interface to manage tasks
