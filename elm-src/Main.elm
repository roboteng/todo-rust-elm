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
import Pages.Home as Home
import Pages.Login as Login
import Pages.NewTask as NewTask
import Pages.Register as Register
import Ports as P exposing (connectWebsocket)
import Random
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
    , error : Maybe String
    , page : Page
    , loggedIn : Bool
    }


type Page
    = Home Home.Model
    | New NewTask.Model
    | Register Register.Model
    | Login Login.Model


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { pushUrl = \u -> Nav.pushUrl key u
      , tasks =
            Tasks.empty
      , error = Nothing
      , page =
            case Route.parseRoute url of
                Route.Home ->
                    Home <| Home.init { loggedIn = False, tasks = Tasks.empty }

                Route.New ->
                    New <| NewTask.init

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
    | NewTaskMsg NewTask.Msg
    | Recv P.InMessage
    | PortError String
    | RegisterMsg Register.Msg
    | LoginMsg Login.Msg
    | HomeMsg Home.Msg
    | Logout
    | LogoutResponse (Result Http.Error ())
    | TaskIdCreated Tasks.Task Tasks.TaskId


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( None, _ ) ->
            ( model, Cmd.none )

        ( UrlRequested urlRequest, _ ) ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, model.pushUrl (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        ( UrlChanged url, _ ) ->
            let
                page =
                    case parseRoute url of
                        Route.Home ->
                            Home <| Home.init { loggedIn = model.loggedIn, tasks = model.tasks }

                        Route.New ->
                            New <| NewTask.init

                        Route.Register ->
                            Register <| Register.init

                        Route.Login ->
                            Login <| Login.init
            in
            ( { model | page = page }
            , Cmd.none
            )

        ( SendTasks ts, _ ) ->
            ( model
            , P.send <| P.Tasks ts
            )

        ( NewTaskMsg message, New pageModel ) ->
            let
                ( newModel, cmd ) =
                    NewTask.update message pageModel
            in
            case cmd of
                NewTask.None ->
                    ( { model | page = New newModel }, Cmd.none )

                NewTask.NewTaskCreated task ->
                    ( { model | page = New newModel }, Random.generate (TaskIdCreated task) Tasks.generateTaskId )

        ( NewTaskMsg _, _ ) ->
            ( model, Cmd.none )

        ( Recv inMsg, _ ) ->
            case inMsg of
                P.NewTasks ts ->
                    ( { model | tasks = ts }
                    , Cmd.none
                    )

        ( PortError e, _ ) ->
            ( { model | error = Just e }, Cmd.none )

        ( RegisterMsg m, Register pageModel ) ->
            let
                ( newModel, cmd, outMsg ) =
                    Register.update m pageModel

                navCommand =
                    case outMsg of
                        Register.PushRoute route ->
                            model.pushUrl <| Route.encodeRoute route

                        Register.None ->
                            Cmd.none
            in
            ( { model | page = Register newModel }, Cmd.batch [ Cmd.map RegisterMsg cmd, navCommand ] )

        ( RegisterMsg _, _ ) ->
            ( model, Cmd.none )

        ( LoginMsg m, Login pageModel ) ->
            let
                ( newModel, cmd, outMsg ) =
                    Login.update m pageModel

                ( newParentModel, outCmd ) =
                    handleLoginMsg model outMsg
            in
            ( { newParentModel
                | page = Login newModel
              }
            , Cmd.batch [ Cmd.map LoginMsg cmd, outCmd ]
            )

        ( LoginMsg _, _ ) ->
            ( model, Cmd.none )

        ( HomeMsg message, Home pageModel ) ->
            let
                ( newModel, command, outMsg ) =
                    Home.update { loggedIn = model.loggedIn, tasks = model.tasks } message pageModel

                c =
                    case outMsg of
                        Home.None ->
                            Cmd.none

                        Home.Sync ->
                            P.send <| P.Tasks model.tasks
            in
            ( { model | page = Home newModel }, Cmd.batch [ c, Cmd.map HomeMsg command ] )

        ( HomeMsg _, _ ) ->
            ( model, Cmd.none )

        ( Logout, _ ) ->
            ( model
            , Http.post
                { url = "/api/logout"
                , body = Http.emptyBody
                , expect = Http.expectWhatever LogoutResponse
                }
            )

        ( LogoutResponse (Ok _), _ ) ->
            ( { model | loggedIn = False }, connectWebsocket False )

        ( LogoutResponse (Err _), _ ) ->
            -- Even if logout fails on server, still log out client-side
            ( { model | loggedIn = False }, connectWebsocket False )

        ( TaskIdCreated task id, _ ) ->
            case Tasks.newTask model.tasks id of
                Just fn ->
                    ( { model | tasks = fn task }, Cmd.none )

                Nothing ->
                    ( model, Random.generate (TaskIdCreated task) Tasks.generateTaskId )


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
            batchHelp handleLoginMsg model msgs


batchHelp : (Model -> a -> ( Model, Cmd Msg )) -> Model -> List a -> ( Model, Cmd Msg )
batchHelp f model msgs =
    List.foldl
        (\msg ( mdl, cmd ) ->
            let
                ( newModel, c ) =
                    f mdl msg
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
        Home m ->
            Html.Styled.map HomeMsg <| Home.view m

        New m ->
            Html.Styled.map NewTaskMsg <| NewTask.view m

        Login m ->
            Html.Styled.map LoginMsg <| Login.view m

        Register m ->
            Html.Styled.map RegisterMsg <| Register.view m
