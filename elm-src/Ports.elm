port module Ports exposing (recv, send, OutMessage(..), InMessage(..))

import Dict exposing (Dict)
import Json.Decode exposing (errorToString, field, map2)
import Json.Encode exposing (Value, object, string)


port sendMessage : Value -> Cmd msg


port recvMessage : (Value -> msg) -> Sub msg

type OutMessage =
    Greet String
    | StartScanning

type InMessage =
    Greeting String

send : OutMessage -> Cmd msg
send outMsg =
    case outMsg of
        Greet s ->
            sendGreet s

        StartScanning ->
            sendStartScanning

sendGreet : String -> Cmd msg
sendGreet s =
    sendMessage
        (object
            [ ( "action", string "greet" )
            , ( "payload", string s )
            ]
        )

sendStartScanning : Cmd msg
sendStartScanning =
     sendAction  "start_scanning"

sendAction action = sendMessage
        (object
            [ ( "action", string action )
            ]
        )

encodeMessage : InMessage -> Value
encodeMessage msg =
    case msg of
        Greeting s ->
            object
                [ ( "action", Json.Encode.string "greet" )
                , ( "payload", Json.Encode.string s )
                ]



recv : (InMessage -> msg) -> (String -> msg) -> Sub msg
recv onMessage onError =
    recvMessage <|
        \value ->
            case decodeIncomingMessage value of
                Ok incomingMsg ->
                    onMessage incomingMsg

                Err error ->
                    onError error


decodeIncomingMessage : Value -> Result String InMessage
decodeIncomingMessage value =
    case Json.Decode.decodeValue decodeAction value of
        Ok action ->
            case action.action of
                "greet" ->
                    case Json.Decode.decodeValue Json.Decode.string action.payload of
                        Ok s ->
                            Ok (Greeting s)

                        Err e ->
                            Err ("Failed to decode greet payload: " ++ errorToString e)

                unknown ->
                    Err ("Unknown action: " ++ unknown)

        Err e ->
            Err ("Failed to decode action: " ++ errorToString e)


type alias Action =
    { action : String
    , payload : Value
    }


decodeAction : Json.Decode.Decoder Action
decodeAction =
    map2 Action
        (field "action" Json.Decode.string)
        (field "payload" Json.Decode.value)
