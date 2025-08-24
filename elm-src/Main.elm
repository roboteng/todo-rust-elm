module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Css exposing (..)
import Html
import Html.Events exposing (onClick)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (..)
import Ports exposing (InMessage, OutMessage, recv, send)
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
    | Greet String
    | StartScanning
    | Recv InMessage
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
            ( { model | url = url }
            , Cmd.none
            )

        Greet s ->
            ( model
            , send <| Ports.Greet s
            )

        StartScanning ->
            ( model, send <| Ports.StartScanning )

        Recv inMsg ->
            case inMsg of
                Ports.Greeting m ->
                    ( { model | name = m }
                    , Cmd.none
                    )

        PortError e ->
            ( { model | error = Just e }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    recv Recv PortError


view : Model -> Browser.Document Msg
view model =
    { title = "Next Steps - TrevDo"
    , body =
        [ toUnstyled <|
            div []
                [ ul [ css [ listStyleType none ] ]
                    [ li [] [ text "Take out the trash" ]
                    , li [] [ text "Scoop catboxes" ]
                    , li [] [ text "Wash dishes" ]
                    ]
                ]
        ]
    }
