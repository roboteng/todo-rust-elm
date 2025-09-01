module Route exposing (Route(..), encodeRoute, parseRoute)

import Url
import Url.Parser exposing ((</>), Parser, int, map, oneOf, parse, s)


type Route
    = Home
    | New


parseRoute : Url.Url -> Route
parseRoute url =
    parse routeParser url |> Maybe.withDefault Home


routeParser : Parser (Route -> a) a
routeParser =
    oneOf
        [ map Home (s "")
        , map New (s "new")
        ]


encodeRoute : Route -> String
encodeRoute route =
    case route of
        Home ->
            "/"

        New ->
            "/new"
