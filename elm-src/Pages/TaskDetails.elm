module Pages.TaskDetails exposing (Model, Msg, init, update, view)

import Html.Styled exposing (div, text)
import Tasks exposing (Task, TaskId)


type Model
    = M
        { id : TaskId
        , task : Maybe Task
        }


type Msg
    = None


init : Tasks.Tasks -> TaskId -> Model
init tasks id =
    M { id = id, task = Tasks.find tasks id }


type alias Context =
    { tasks : Tasks.Tasks }


update : Context -> Msg -> Model -> ( Model, Cmd Msg )
update context msg model =
    case msg of
        None ->
            ( model, Cmd.none )


view (M model) =
    case model.task of
        Just task ->
            div [] [ text task.summary ]

        Nothing ->
            div [] [ text "Task not found" ]
