port module Ports exposing (InMessage(..), OutMessage(..), recv, send)

import Dict exposing (Dict)
import Json.Decode exposing (errorToString, field, map2)
import Json.Encode exposing (Value, object, string)


port sendMessage : Value -> Cmd msg


port recvMessage : (Value -> msg) -> Sub msg


type OutMessage
    = Greet String
    | StartScanning


type InMessage
    = Greeting String


send : OutMessage -> Cmd msg
send outMsg =
    case outMsg of
        Greet s ->
            sendGreet s

        StartScanning ->
            sendStartScanning


sendGreet : String -> Cmd msg
sendGreet s =
    sendHelp "greet" (Just (string s))


sendHelp : String -> Maybe Value -> Cmd msg
sendHelp action payload =
    let
        act =  [ ( "action", string action ) ]
        pay =
            payload
            |> Maybe.map (\p -> [ ( "payload", p ) ])
            |> Maybe.withDefault []

    in
        sendMessage <| object <| act ++ pay


sendStartScanning : Cmd msg
sendStartScanning =
    sendHelp "start_scanning" Nothing


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
