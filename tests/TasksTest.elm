module TasksTest exposing (..)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Random
import Tasks exposing (..)
import Test exposing (..)



-- Helper function for round-trip testing


roundTripNewTask : Task -> Result Decode.Error Task
roundTripNewTask newTask =
    newTask
        |> encodeTask
        |> Encode.encode 0
        |> Decode.decodeString decodeTask


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
                            { summary = "Complete project"
                            }

                        result =
                            roundTripTask original
                    in
                    Expect.equal (Ok original) result
            , test "Task with zero id and empty summary" <|
                \_ ->
                    let
                        original =
                            { summary = ""
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
                            List.foldl
                                (\task ( tasks, seed ) -> newTask tasks seed task)
                                ( empty, Random.initialSeed 2 )
                                [ { summary = "First task" }
                                , { summary = "Second task with different id" }
                                , { summary = "Task with high id" }
                                ]
                                |> Tuple.first

                        result =
                            roundTripTasks original
                    in
                    Expect.equal (Ok original) result
            , test "Empty Tasks with zero nextId" <|
                \_ ->
                    let
                        original =
                            empty

                        result =
                            roundTripTasks original
                    in
                    Expect.equal (Ok original) result
            ]
        ]
