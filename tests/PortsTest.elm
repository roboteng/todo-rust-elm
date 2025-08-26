module PortsTest exposing (..)

import Expect exposing (Expectation)
import Json.Encode as Encode
import Ports exposing (InMessage(..), decodeIncomingMessage)
import Tasks as T
import Test exposing (..)


suite : Test
suite =
    describe "Ports"
        [ describe "decodeIncomingMessage"
            [ test "successfully decodes a new_tasks message" <|
                \_ ->
                    let
                        expectedTasks =
                            { tasks = [ { id = 1, summary = "Hello World" } ]
                            , nextId = 2
                            }

                        json =
                            Encode.object
                                [ ( "action", Encode.string "new_tasks" )
                                , ( "payload", T.encodeTasks expectedTasks )
                                ]
                    in
                    decodeIncomingMessage json
                        |> Expect.equal (Ok (NewTasks expectedTasks))
            , test "returns error for unknown action" <|
                \_ ->
                    let
                        json =
                            Encode.object
                                [ ( "action", Encode.string "unknown" )
                                , ( "payload", Encode.string "test" )
                                ]
                    in
                    decodeIncomingMessage json
                        |> Expect.err
            , test "returns error for malformed JSON" <|
                \_ ->
                    let
                        json =
                            Encode.string "not an object"
                    in
                    decodeIncomingMessage json
                        |> Expect.err
            , test "returns error for malformed tasks payload" <|
                \_ ->
                    let
                        json =
                            Encode.object
                                [ ( "action", Encode.string "new_tasks" )
                                , ( "payload", Encode.int 42 )
                                ]
                    in
                    decodeIncomingMessage json
                        |> Expect.err
            ]
        ]
