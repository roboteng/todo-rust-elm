module Pages.TaskDetails exposing (Model, Msg, init, update, view)

import Html.Styled exposing (div, text)
import Tasks exposing (TaskId)


type Model
    = M
        { id : TaskId
        }


type Msg
    = None


init : TaskId -> Model
init id =
    M { id = id }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        None ->
            ( model, Cmd.none )


view model =
    div [] [ text "Task Details" ]
