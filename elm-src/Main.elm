module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Dict
import Html exposing (..)
import Html.Events exposing (onClick)
import Json.Decode exposing (Value, errorToString)
import Ports exposing (IncomingMessage(..), OutgoingMessage(..), recvAction, sendMessage)
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
    { navigation : NavigationModel
    , messages : MessageModel
    }


type alias NavigationModel =
    { key : Nav.Key
    , url : Url.Url
    }


type alias MessageModel =
    { name : String
    , error : Maybe String
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { navigation =
            { key = key
            , url = url
            }
      , messages =
            { name = ""
            , error = Nothing
            }
      }
    , Cmd.none
    )


type Msg
    = None
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url
    | SendMsg OutgoingMessage
    | MessageReceived IncomingMessage
    | MessageError String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        None ->
            ( model, Cmd.none )

        UrlRequested urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.navigation.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model | navigation = { key = model.navigation.key, url = url } }
            , Cmd.none
            )

        SendMsg m ->
            dispatchSendMsg model m

        MessageReceived incomingMsg ->
            case incomingMsg of
                GreetReceived s ->
                    ( { model | messages = { name = s, error = model.messages.error } }
                    , Cmd.none
                    )

                ScanStarted ->
                    ( model, Cmd.none )

        MessageError e ->
            ( { model | messages = { name = model.messages.name, error = Just e } }, Cmd.none )


dispatchSendMsg : Model -> OutgoingMessage -> ( Model, Cmd Msg )
dispatchSendMsg model msg =
    ( model, sendMessage msg )


subscriptions : Model -> Sub Msg
subscriptions _ =
    recvAction MessageReceived MessageError


view : Model -> Browser.Document Msg
view model =
    { title = "Application Title"
    , body =
        [ div []
            [ text "Web Application"
            , text model.messages.name
            , button [ onClick <| SendMsg <| Greet "Me" ] [ text "click" ]
            , text (Maybe.withDefault "" model.messages.error)
            ]
        , button [ onClick <| SendMsg StartScanning ] [ text "Start Scanning" ]
        ]
    }
