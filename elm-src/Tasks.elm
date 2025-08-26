module Tasks exposing (..)


type alias NewTask =
    { summary : String
    }


type alias Task =
    { id : Int
    , summary : String
    }


type alias Tasks =
    { tasks : List Task
    , nextId : Int
    }


empty : Tasks
empty =
    { tasks = [], nextId = 0 }


newTask : Tasks -> NewTask -> Tasks
newTask tasks task =
    { tasks = { id = tasks.nextId, summary = task.summary } :: tasks.tasks
    , nextId = tasks.nextId + 1
    }
