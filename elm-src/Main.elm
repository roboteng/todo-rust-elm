module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Css exposing (listStyleType, none)
import Html.Styled
    exposing
        ( Html
        , a
        , button
        , div
        , li
        , main_
        , nav
        , text
        , toUnstyled
        , ul
        )
import Html.Styled.Attributes exposing (css, href)
import Html.Styled.Events exposing (onClick)
import Login
import Ports as P exposing (connectWebsocket)
import Register
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
    , page : Page
    , loggedIn : Bool
    }


type Page
    = Home
    | New
    | Register Register.Model
    | Login Login.Model


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key
      , tasks =
            Tasks.empty
      , newTask =
            { summary = ""
            }
      , error = Nothing
      , page =
            case Route.parseRoute url of
                Route.Home ->
                    Home

                Route.New ->
                    New

                Route.Register ->
                    Register Register.init

                Route.Login ->
                    Login Login.init
      , loggedIn = False
      }
    , P.connectWebsocket False
    )


type Msg
    = None
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url
    | SendTasks Tasks.Tasks
    | NewTaskMsg Tasks.Msg
    | Recv P.InMessage
    | PortError String
    | RegisterMsg Register.Msg
    | LoginMsg Login.Msg
    | LoggedIn


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
            let
                page =
                    case parseRoute url of
                        Route.Home ->
                            Home

                        Route.New ->
                            New

                        Route.Register ->
                            Register Register.init

                        Route.Login ->
                            Login Login.init
            in
            ( { model | page = page }
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

        RegisterMsg m ->
            case model.page of
                Register mdl ->
                    let
                        ( newModel, cmd ) =
                            Register.update m mdl
                    in
                    ( { model | page = Register newModel }, Cmd.map RegisterMsg cmd )

                _ ->
                    ( model, Cmd.none )

        LoginMsg m ->
            case model.page of
                Login mdl ->
                    let
                        ( newModel, cmd, outMsg ) =
                            Login.update m mdl
                    in
                    ( { model
                        | page = Login newModel
                        , loggedIn = outMsg == Login.LoggedIn
                      }
                    , Cmd.batch [ Cmd.map LoginMsg cmd, connectWebsocket <| outMsg == Login.LoggedIn ]
                    )

                _ ->
                    ( model, Cmd.none )

        LoggedIn ->
            ( { model | loggedIn = True }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.loggedIn of
        True ->
            P.recv Recv PortError

        False ->
            Sub.none



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
            , a [ href <| Route.encodeRoute Route.Login ] [ text "Login" ]
            ]
        , content model
        ]


content : Model -> Html Msg
content model =
    case model.page of
        Home ->
            nextTasksView model

        New ->
            Html.Styled.map NewTaskMsg <| Tasks.viewNewTask model.newTask

        Login m ->
            Html.Styled.map LoginMsg <| Login.view m

        Register m ->
            Html.Styled.map RegisterMsg <| Register.view m


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
