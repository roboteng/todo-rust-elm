port module Ports exposing (IncomingMessage(..), OutgoingMessage(..), decodeIncomingMessage, encodeMessage, recvAction, sendGreet, sendMessage, sendStartScanning)

import Json.Decode exposing (errorToString, field, map2)
import Json.Encode exposing (Value, object)


port sendMessagePort : Value -> Cmd msg


port recvMessage : (Value -> msg) -> Sub msg


type OutgoingMessage
    = Greet String
    | StartScanning


type IncomingMessage
    = GreetReceived String
    | ScanStarted


sendMessage : OutgoingMessage -> Cmd msg
sendMessage msg =
    sendMessagePort <| encodeMessage msg


sendGreet : String -> Cmd msg
sendGreet s =
    sendMessage <| Greet s


sendStartScanning : Cmd msg
sendStartScanning =
    sendMessage StartScanning


encodeMessage : OutgoingMessage -> Value
encodeMessage msg =
    case msg of
        Greet s ->
            object
                [ ( "action", Json.Encode.string "greet" )
                , ( "payload", Json.Encode.string s )
                ]

        StartScanning ->
            object
                [ ( "action", Json.Encode.string "start_scanning" )
                ]


recvAction : (IncomingMessage -> msg) -> (String -> msg) -> Sub msg
recvAction onMessage onError =
    recvMessage <|
        \value ->
            case decodeIncomingMessage value of
                Ok incomingMsg ->
                    onMessage incomingMsg

                Err error ->
                    onError error


decodeIncomingMessage : Value -> Result String IncomingMessage
decodeIncomingMessage value =
    case Json.Decode.decodeValue decodeAction value of
        Ok action ->
            case action.action of
                "greet" ->
                    case Json.Decode.decodeValue Json.Decode.string action.payload of
                        Ok s ->
                            Ok (GreetReceived s)

                        Err e ->
                            Err ("Failed to decode greet payload: " ++ errorToString e)

                "start_scanning" ->
                    Ok ScanStarted

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
