module TasksTest exposing (..)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Tasks exposing (..)
import Test exposing (..)


-- Helper function for round-trip testing


roundTripNewTask : NewTask -> Result Decode.Error NewTask
roundTripNewTask newTask =
    newTask
        |> encodeNewTask
        |> Encode.encode 0
        |> Decode.decodeString decodeNewTask


roundTripTask : Task -> Result Decode.Error Task
roundTripTask task =
    task
        |> encodeTask
        |> Encode.encode 0
        |> Decode.decodeString decodeTask


roundTripTasks : Tasks -> Result Decode.Error Tasks
roundTripTasks tasks =
    tasks
        |> encodeTasks
        |> Encode.encode 0
        |> Decode.decodeString decodeTasks


-- Tests


suite : Test
suite =
    describe "Tasks JSON Round-trip Tests"
        [ describe "NewTask round-trip tests"
            [ test "NewTask with simple summary" <|
                \_ ->
                    let
                        original =
                            { summary = "Learn Elm" }

                        result =
                            roundTripNewTask original
                    in
                    Expect.equal (Ok original) result
            , test "NewTask with complex summary" <|
                \_ ->
                    let
                        original =
                            { summary = "Write integration tests with special chars: !@#$%^&*()" }

                        result =
                            roundTripNewTask original
                    in
                    Expect.equal (Ok original) result
            ]
        , describe "Task round-trip tests"
            [ test "Task with positive id and simple summary" <|
                \_ ->
                    let
                        original =
                            { id = 42
                            , summary = "Complete project"
                            }

                        result =
                            roundTripTask original
                    in
                    Expect.equal (Ok original) result
            , test "Task with zero id and empty summary" <|
                \_ ->
                    let
                        original =
                            { id = 0
                            , summary = ""
                            }

                        result =
                            roundTripTask original
                    in
                    Expect.equal (Ok original) result
            ]
        , describe "Tasks round-trip tests"
            [ test "Tasks with multiple tasks and high nextId" <|
                \_ ->
                    let
                        original =
                            { tasks =
                                [ { id = 1, summary = "First task" }
                                , { id = 5, summary = "Second task with different id" }
                                , { id = 100, summary = "Task with high id" }
                                ]
                            , nextId = 101
                            }

                        result =
                            roundTripTasks original
                    in
                    Expect.equal (Ok original) result
            , test "Empty Tasks with zero nextId" <|
                \_ ->
                    let
                        original =
                            { tasks = []
                            , nextId = 0
                            }

                        result =
                            roundTripTasks original
                    in
                    Expect.equal (Ok original) result
            ]
        ]
