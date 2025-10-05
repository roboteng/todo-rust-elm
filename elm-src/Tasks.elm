module Tasks exposing
    ( Task
    , TaskId
    , TaskWithId
    , Tasks
    , allTasks
    , decodeTask
    , decodeTaskId
    , decodeTasks
    , empty
    , encodeTask
    , encodeTaskId
    , encodeTasks
    , generateTaskId
    , newTask
    , taskIdFromString
    , taskIdToString
    )

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Random



-- TaskId


type TaskId
    = TaskId Int


decodeTaskId : Decode.Decoder TaskId
decodeTaskId =
    Decode.map TaskId Decode.int


encodeTaskId : TaskId -> Encode.Value
encodeTaskId (TaskId id) =
    Encode.int id


generateTaskId : Random.Seed -> ( TaskId, Random.Seed )
generateTaskId seed =
    Random.step (Random.int 1 0xFFFFFFFF) seed |> Tuple.mapFirst TaskId


taskIdToString : TaskId -> String
taskIdToString (TaskId id) =
    String.fromInt id


taskIdFromString : String -> Maybe TaskId
taskIdFromString val =
    String.toInt val
        |> Maybe.map TaskId



{-
   Constraints on Tasks:
   - No two tasks can have the same Id
   - (TODO) Every task must exist on exactly one list
-}


type alias TaskWithId =
    ( TaskId, Task )


type alias Task =
    { summary : String
    }


type Tasks
    = Tasks Tasks_


type alias Tasks_ =
    { tasks : Dict Int Task
    }


empty : Tasks
empty =
    Tasks { tasks = Dict.empty }


newTask : Tasks -> Random.Seed -> Task -> ( Tasks, Random.Seed )
newTask (Tasks tasks) seed task =
    let
        ( TaskId id, newSeed ) =
            generateTaskId seed
    in
    case Dict.get id tasks.tasks of
        Nothing ->
            ( Tasks { tasks = Dict.insert id task tasks.tasks }, newSeed )

        Just _ ->
            newTask (Tasks tasks) newSeed task


allTasks : Tasks -> List TaskWithId
allTasks (Tasks tasks) =
    Dict.toList tasks.tasks
        |> List.map
            (Tuple.mapFirst TaskId)



-- ENCODERS


encodeTask : Task -> Value
encodeTask task =
    Encode.object
        [ ( "summary", Encode.string task.summary )
        ]


encodeTasks : Tasks -> Value
encodeTasks (Tasks tasks) =
    Encode.object
        [ ( "tasks", Encode.dict String.fromInt encodeTask tasks.tasks )
        ]



-- DECODERS


decodeTask : Decoder Task
decodeTask =
    Decode.map Task (Decode.field "summary" Decode.string)


decodeTasks : Decoder Tasks
decodeTasks =
    Decode.map Tasks <|
        Decode.map Tasks_ <|
            Decode.andThen
                (\maybeDict ->
                    case maybeDict of
                        Just dict ->
                            Decode.succeed dict

                        Nothing ->
                            Decode.fail "Failed to decode tasks"
                )
            <|
                Decode.map
                    mapKeys
                <|
                    Decode.field "tasks" (Decode.dict decodeTask)


mapKeys : Dict String Task -> Maybe (Dict Int Task)
mapKeys tasks =
    Dict.toList tasks
        |> List.map
            (\( k, v ) ->
                String.toInt k |> Maybe.map (\key -> ( key, v ))
            )
        |> List.foldl
            (\a ->
                \b ->
                    case ( a, b ) of
                        ( Just c, Just d ) ->
                            Just (c :: d)

                        _ ->
                            Nothing
            )
            (Just [])
        |> Maybe.map Dict.fromList
