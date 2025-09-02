module Tasks exposing (..)

import Html.Styled exposing (Html, form, input, main_, text)
import Html.Styled.Attributes exposing (placeholder, type_, value)
import Html.Styled.Events exposing (onInput, onSubmit)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


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



-- ENCODERS


encodeNewTask : NewTask -> Value
encodeNewTask task =
    Encode.object
        [ ( "summary", Encode.string task.summary )
        ]


encodeTask : Task -> Value
encodeTask task =
    Encode.object
        [ ( "id", Encode.int task.id )
        , ( "summary", Encode.string task.summary )
        ]


encodeTasks : Tasks -> Value
encodeTasks tasks =
    Encode.object
        [ ( "tasks", Encode.list encodeTask tasks.tasks )
        , ( "next_id", Encode.int tasks.nextId )
        ]



-- DECODERS


decodeNewTask : Decoder NewTask
decodeNewTask =
    Decode.map NewTask
        (Decode.field "summary" Decode.string)


decodeTask : Decoder Task
decodeTask =
    Decode.map2 Task
        (Decode.field "id" Decode.int)
        (Decode.field "summary" Decode.string)


decodeTasks : Decoder Tasks
decodeTasks =
    Decode.map2 Tasks
        (Decode.field "tasks" (Decode.list decodeTask))
        (Decode.field "next_id" Decode.int)



-- New Tasks


type Msg
    = NewTaskSummary String
    | Create


type NewTaskCmd
    = NewTaskCreated NewTask
    | None


type alias Model =
    { summary : String
    }


update : Msg -> Model -> ( Model, NewTaskCmd )
update msg model =
    case msg of
        NewTaskSummary summary ->
            ( { model | summary = summary }, None )

        Create ->
            ( { model | summary = "" }, NewTaskCreated <| NewTask model.summary )


viewNewTask : Model -> Html Msg
viewNewTask model =
    main_ []
        [ form
            [ onSubmit <| Create ]
            [ input [ type_ "text", placeholder "Summary", onInput <| NewTaskSummary, value model.summary ] []
            , input [ type_ "submit" ] [ text "Create" ]
            ]
        ]
