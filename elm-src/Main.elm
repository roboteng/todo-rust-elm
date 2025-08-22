module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Dict
import Html exposing (..)
import Html.Events exposing (onClick)
import Json.Decode exposing (Value, errorToString)
import Ports exposing (recvAction, send, OutMessage)
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
    , url : Url.Url
    , name : String
    , error : Maybe String
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key
      , url = url
      , name = ""
      , error = Nothing
      }
    , Cmd.none
    )


type Msg
    = None
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url
    | SendGreet String
    | RecvGreet String
    | PortError String
    | StartScanning


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
            ( { model | url = url }
            , Cmd.none
            )

        SendGreet s ->
            ( model
            , send <| Ports.Greet s
            )

        RecvGreet s ->
            ( { model | name = s }
            , Cmd.none
            )

        StartScanning ->
            ( model, send <| Ports.StartScanning )

        PortError e ->
            ( { model | error = Just e }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    recvAction
        (Dict.fromList
            [ ( "greet"
              , decodeGreet
              )
            , ( "start_scanning"
              , decodeEmpty
              )
            ]
        )
        PortError


decodeGreet : Value -> Msg
decodeGreet v =
    case Json.Decode.decodeValue Json.Decode.string v of
        Ok g ->
            RecvGreet g

        Err e ->
            PortError (errorToString e)


decodeEmpty _ =
    None


view : Model -> Browser.Document Msg
view model =
    { title = "Application Title"
    , body =
        [ div []
            [ text "Web Application"
            , text model.name
            , button [ onClick (SendGreet "Me") ] [ text "click" ]
            , text (Maybe.withDefault "" model.error)
            ]
        , button [ onClick StartScanning ] [ text "Start Scanning" ]
        ]
    }
