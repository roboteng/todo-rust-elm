module Route exposing (Route(..), encodeRoute, parseRoute)

import Tasks
import Url
import Url.Parser exposing ((</>), Parser, custom, map, oneOf, parse, s, string)


type Route
    = Home
    | New
    | Login
    | Register
    | TaskDetails Tasks.TaskId


parseRoute : Url.Url -> Route
parseRoute url =
    parse routeParser url |> Maybe.withDefault Home


routeParser : Parser (Route -> a) a
routeParser =
    oneOf
        [ map Home (s "")
        , map New (s "new")
        , map Login (s "login")
        , map Register (s "register")
        , map TaskDetails (s "task" </> custom "taskId" Tasks.taskIdFromString)
        ]


encodeRoute : Route -> String
encodeRoute route =
    case route of
        Home ->
            "/"

        New ->
            "/new"

        Login ->
            "/login"

        Register ->
            "/register"

        TaskDetails taskId ->
            "/task/" ++ Tasks.taskIdToString taskId
