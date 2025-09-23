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
import Http
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
    { pushUrl : String -> Cmd Msg
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
    ( { pushUrl = \u -> Nav.pushUrl key u
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
                    Register <| Register.init

                Route.Login ->
                    Login <| Login.init
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
    | Logout
    | LogoutResponse (Result Http.Error ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        None ->
            ( model, Cmd.none )

        UrlRequested urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, model.pushUrl (Url.toString url) )

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
                            Register <| Register.init

                        Route.Login ->
                            Login <| Login.init
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
                        ( newModel, cmd, outMsg ) =
                            Register.update m mdl

                        navCommand =
                            case outMsg of
                                Register.PushRoute route ->
                                    model.pushUrl <| Route.encodeRoute route

                                Register.None ->
                                    Cmd.none
                    in
                    ( { model | page = Register newModel }, Cmd.batch [ Cmd.map RegisterMsg cmd, navCommand ] )

                _ ->
                    ( model, Cmd.none )

        LoginMsg m ->
            case model.page of
                Login mdl ->
                    let
                        ( newModel, cmd, outMsg ) =
                            Login.update m mdl

                        ( newParentModel, outCmd ) =
                            handleLoginMsg model outMsg
                    in
                    ( { newParentModel
                        | page = Login newModel
                      }
                    , Cmd.batch [ Cmd.map LoginMsg cmd, outCmd ]
                    )

                _ ->
                    ( model, Cmd.none )

        Logout ->
            ( model
            , Http.post
                { url = "/api/logout"
                , body = Http.emptyBody
                , expect = Http.expectWhatever LogoutResponse
                }
            )

        LogoutResponse result ->
            case result of
                Ok _ ->
                    ( { model | loggedIn = False }, connectWebsocket False )

                Err _ ->
                    -- Even if logout fails on server, still log out client-side
                    ( { model | loggedIn = False }, connectWebsocket False )


handleLoginMsg : Model -> Login.OutMsg -> ( Model, Cmd Msg )
handleLoginMsg model outMsg =
    case outMsg of
        Login.None ->
            ( model, Cmd.none )

        Login.LoggedIn ->
            ( { model | loggedIn = True }, connectWebsocket True )

        Login.PushUrl url ->
            ( model, model.pushUrl url )

        Login.Batch msgs ->
            List.foldl
                (\msg ( mdl, cmd ) ->
                    let
                        ( newModel, c ) =
                            handleLoginMsg mdl msg
                    in
                    ( newModel, Cmd.batch [ cmd, c ] )
                )
                ( model, Cmd.none )
                msgs


subscriptions : Model -> Sub Msg
subscriptions model =
    if model.loggedIn then
        P.recv Recv PortError

    else
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
        [ nav [] <|
            if model.loggedIn then
                [ a [ href <| Route.encodeRoute Route.Home ] [ text "Home" ]
                , button [ onClick Logout ] [ text "Logout" ]
                ]

            else
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
    main_ [] <|
        if model.loggedIn then
            [ ul [ css [ listStyleType none ] ]
                (List.map
                    (\task -> li [] [ text task.summary ])
                    model.tasks.tasks
                )
            , button [ onClick <| SendTasks model.tasks ] [ text "Send Tasks to Server" ]
            , a [ href <| Route.encodeRoute Route.New ] [ text "Create new Item" ]
            ]

        else
            [ ul [ css [ listStyleType none ] ]
                (List.map
                    (\task -> li [] [ text task.summary ])
                    model.tasks.tasks
                )
            , a [ href <| Route.encodeRoute Route.New ] [ text "Create new Item" ]
            ]
