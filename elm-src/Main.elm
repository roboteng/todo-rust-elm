module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Css exposing (..)
import Html.Styled
    exposing
        ( Html
        , a
        , button
        , div
        , form
        , h1
        , input
        , label
        , li
        , main_
        , nav
        , p
        , text
        , toUnstyled
        , ul
        )
import Html.Styled.Attributes
    exposing
        ( attribute
        , autocomplete
        , css
        , for
        , href
        , id
        , placeholder
        , type_
        , value
        )
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
    , newTask : Tasks.NewTask
    , error : Maybe String
    , route : Route
    , auth : Maybe String
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key
      , tasks =
            Tasks.empty
      , newTask =
            { summary = ""
            }
      , error = Nothing
      , route = Route.parseRoute url
      , auth = Nothing
      }
    , Cmd.none
    )


type Msg
    = None
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url
    | SendTasks Tasks.Tasks
    | NewTaskMsg Tasks.Msg
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

        NewTaskMsg m ->
            let
                ( newModel, cmd ) =
                    Tasks.update m model.newTask
            in
            case cmd of
                Tasks.None ->
                    ( { model | newTask = newModel }, Cmd.none )

                Tasks.NewTaskCreated task ->
                    ( { model | newTask = newModel, tasks = Tasks.newTask model.tasks task }, Cmd.none )

        Recv inMsg ->
            case inMsg of
                P.NewTasks ts ->
                    ( { model | tasks = ts }
                    , Cmd.none
                    )

        PortError e ->
            ( { model | error = Just e }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    P.recv Recv PortError



-- View


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
    div []
        [ nav []
            [ a [ href <| Route.encodeRoute Route.Home ] [ text "Home" ]
            , case model.auth of
                Nothing ->
                    a [ href <| Route.encodeRoute Route.Login ] [ text "Login" ]

                Just _ ->
                    a [ href <| Route.encodeRoute Route.Home ] [ text "Logout" ]
            ]
        , content model
        ]


content : Model -> Html Msg
content model =
    case model.route of
        Route.Home ->
            nextTasksView model

        Route.New ->
            Html.Styled.map NewTaskMsg <| Tasks.viewNewTask model.newTask

        Route.Login ->
            viewLogin

        Route.Register ->
            viewRegister


viewLogin : Html Msg
viewLogin =
    main_ []
        [ form []
            [ h1 [] [ text "Login" ]
            , div []
                [ label [ for "username" ] [ text "Username" ]
                , input [ type_ "text", placeholder "joeSmith", id "username", attribute "autocomplete" "username" ] []
                ]
            , div []
                [ label [ for "password" ] [ text "Password" ]
                , input [ type_ "password", id "password", attribute "autocomplete" "current-password" ] []
                ]
            , button [ type_ "submit" ] [ text "Login" ]
            , p []
                [ text "Don't have an account?"
                , a [ href <| Route.encodeRoute Route.Register ] [ text "Register" ]
                ]
            ]
        ]


viewRegister : Html Msg
viewRegister =
    main_ []
        [ form []
            [ h1 [] [ text "Register" ]
            , div []
                [ label [ for "username" ] [ text "Username" ]
                , input [ type_ "text", placeholder "joeSmith", id "username", attribute "autocomplete" "username" ] []
                ]
            , div []
                [ label [ for "password" ] [ text "Password" ]
                , input [ type_ "password", id "password", attribute "autocomplete" "new-password" ] []
                ]
            , button [ type_ "submit" ] [ text "Register" ]
            , p []
                [ text "Already have an account?"
                , a [ href <| Route.encodeRoute Route.Login ] [ text "Login" ]
                ]
            ]
        ]


nextTasksView : Model -> Html Msg
nextTasksView model =
    main_ []
        [ ul [ css [ listStyleType none ] ]
            (List.map
                (\task -> li [] [ text task.summary ])
                model.tasks.tasks
            )
        , button [ onClick <| SendTasks model.tasks ] [ text "Send Tasks to Server" ]
        , a [ href <| Route.encodeRoute Route.New ] [ text "Create new Item" ]
        ]
