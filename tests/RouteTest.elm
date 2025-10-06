module RouteTest exposing (..)

import Expect
import Route exposing (Route(..), encodeRoute, parseRoute)
import Test exposing (..)
import Url


createUrl : String -> Url.Url
createUrl encodedRoute =
    { protocol = Url.Http
    , host = "example.com"
    , port_ = Nothing
    , path = "/"
    , query = Nothing
    , fragment =
        Just
            (case String.toList encodedRoute of
                '/' :: '#' :: rest ->
                    String.fromList rest

                _ ->
                    encodedRoute
            )
    }


roundTripUrl : String -> String
roundTripUrl path =
    path
        |> createUrl
        |> parseRoute
        |> encodeRoute



-- Tests


suite : Test
suite =
    describe "Route Round-trip Tests"
        [ describe "URL parsing round-trip tests"
            [ test "Home route round-trip" <|
                \_ ->
                    roundTripUrl "/"
                        |> Expect.equal "/#/"
            , test "Home route with empty path round-trip" <|
                \_ ->
                    roundTripUrl ""
                        |> Expect.equal "/#/"
            , test "New route round-trip" <|
                \_ ->
                    roundTripUrl "/new"
                        |> Expect.equal "/#/new"
            , test "Login route round-trip" <|
                \_ ->
                    roundTripUrl "/login"
                        |> Expect.equal "/#/login"
            , test "Register route round-trip" <|
                \_ ->
                    roundTripUrl "/register"
                        |> Expect.equal "/#/register"
            , test "Unknown route defaults to Home in round-trip" <|
                \_ ->
                    roundTripUrl "/unknown"
                        |> Expect.equal "/#/"
            , test "Route with trailing slash normalizes to Home" <|
                \_ ->
                    roundTripUrl "//"
                        |> Expect.equal "/#/"
            , test "Route with query parameters defaults to Home" <|
                \_ ->
                    let
                        urlWithQuery =
                            { protocol = Url.Http
                            , host = "example.com"
                            , port_ = Nothing
                            , path = "/unknown"
                            , query = Just "param=value"
                            , fragment = Nothing
                            }
                    in
                    urlWithQuery
                        |> parseRoute
                        |> encodeRoute
                        |> Expect.equal "/#/"
            ]
        , describe "Route type round-trip tests"
            [ test "Home route encode/parse consistency" <|
                \_ ->
                    Home
                        |> encodeRoute
                        |> createUrl
                        |> parseRoute
                        |> Expect.equal Home
            , test "New route encode/parse consistency" <|
                \_ ->
                    New
                        |> encodeRoute
                        |> createUrl
                        |> parseRoute
                        |> Expect.equal New
            , test "Login route encode/parse consistency" <|
                \_ ->
                    Login
                        |> encodeRoute
                        |> createUrl
                        |> parseRoute
                        |> Expect.equal Login
            , test "Register route encode/parse consistency" <|
                \_ ->
                    Register
                        |> encodeRoute
                        |> createUrl
                        |> parseRoute
                        |> Expect.equal Register
            ]
        ]
