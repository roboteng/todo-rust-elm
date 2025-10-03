module Pages.NewTask exposing (Model, Msg, NewTaskCmd(..), init, update, view)

import Html.Styled exposing (Html, form, input, main_, text)
import Html.Styled.Attributes exposing (placeholder, type_, value)
import Html.Styled.Events exposing (onInput, onSubmit)
import Tasks


type Msg
    = NewTaskSummary String
    | Create


type NewTaskCmd
    = NewTaskCreated Tasks.Task
    | None


type Model
    = M
        { summary : String
        }


init : Model
init =
    M
        { summary = ""
        }


update : Msg -> Model -> ( Model, NewTaskCmd )
update msg (M model) =
    case msg of
        NewTaskSummary summary ->
            ( M { model | summary = summary }, None )

        Create ->
            ( M { model | summary = "" }, NewTaskCreated <| Tasks.Task model.summary )


view : Model -> Html Msg
view (M model) =
    main_ []
        [ form
            [ onSubmit <| Create ]
            [ input [ type_ "text", placeholder "Summary", onInput <| NewTaskSummary, value model.summary ] []
            , input [ type_ "submit" ] [ text "Create" ]
            ]
        ]
