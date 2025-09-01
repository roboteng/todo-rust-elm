module Route exposing (..)

import Url


type Route
    = Home


parseRoute : Url.Url -> Route
parseRoute url =
    Home


encodeRoute : Route -> String
encodeRoute route =
    case route of
        Home ->
            "/"
