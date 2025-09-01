module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (..)
import Html.Styled.Events exposing (onClick)
import Ports as P
import Route exposing (Route(..), parseRoute)
import Tasks
import Url


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }


type alias Model =
    { key : Nav.Key
    , tasks : Tasks.Tasks
    , error : Maybe String
    , route : Route
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key
      , tasks =
            Tasks.empty
      , error = Nothing
      , route = Route.parseRoute url
      }
    , Cmd.none
    )


type Msg
    = None
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url
    | SendTasks Tasks.Tasks
    | AddTask Tasks.NewTask
    | Recv P.InMessage
    | PortError String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        None ->
            ( model, Cmd.none )

        UrlRequested urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model | route = parseRoute url }
            , Cmd.none
            )

        SendTasks ts ->
            ( model
            , P.send <| P.Tasks ts
            )

        Recv inMsg ->
            case inMsg of
                P.NewTasks ts ->
                    ( { model | tasks = ts }
                    , Cmd.none
                    )

        PortError e ->
            ( { model | error = Just e }, Cmd.none )

        AddTask task ->
            ( { model | tasks = Tasks.newTask model.tasks task }
            , Cmd.none
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    P.recv Recv PortError


view : Model -> Browser.Document Msg
view model =
    { title = "Next Steps - TrevDo"
    , body =
        [ toUnstyled <|
            body model
        ]
    }


body : Model -> Html Msg
body model =
    case model.route of
        Route.Home ->
            nextTasksView model

        Route.New ->
            main_ []
                [ text "new Task"
                ]


nextTasksView : Model -> Html Msg
nextTasksView model =
    main_ []
        [ ul [ css [ listStyleType none ] ]
            (List.map
                (\task -> li [] [ text task.summary ])
                model.tasks.tasks
            )
        , button [ onClick <| AddTask { summary = "Item" } ] [ text "Add Task" ]
        , button [ onClick <| SendTasks model.tasks ] [ text "Send Tasks to Server" ]
        , a [ href <| Route.encodeRoute Route.New ] [ text "Create new Item" ]
        ]
