module Tasks exposing (Task, Tasks, allTasks, decodeTask, decodeTasks, empty, encodeTask, encodeTasks, newTask)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


type alias Task =
    { summary : String
    }


type Tasks
    = Tasks Tasks_


type alias Tasks_ =
    { tasks : List Task
    , nextId : Int
    }


empty : Tasks
empty =
    Tasks { tasks = [], nextId = 0 }


newTask : Tasks -> Task -> Tasks
newTask (Tasks tasks) task =
    Tasks
        { tasks = task :: tasks.tasks
        , nextId = tasks.nextId + 1
        }


allTasks : Tasks -> List Task
allTasks (Tasks tasks) =
    tasks.tasks



-- ENCODERS


encodeTask : Task -> Value
encodeTask task =
    Encode.object
        [ ( "summary", Encode.string task.summary )
        ]


encodeTasks : Tasks -> Value
encodeTasks (Tasks tasks) =
    Encode.object
        [ ( "tasks", Encode.list encodeTask tasks.tasks )
        , ( "next_id", Encode.int tasks.nextId )
        ]



-- DECODERS


decodeTask : Decoder Task
decodeTask =
    Decode.map Task (Decode.field "summary" Decode.string)


decodeTasks : Decoder Tasks
decodeTasks =
    Decode.map Tasks
        (Decode.map2 Tasks_
            (Decode.field "tasks" (Decode.list decodeTask))
            (Decode.field "next_id" Decode.int)
        )
