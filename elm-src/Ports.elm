port module Ports exposing (InMessage(..), OutMessage(..), connectWebsocket, decodeIncomingMessage, recv, send)

import Json.Decode exposing (errorToString, field, map2)
import Json.Encode exposing (Value, object, string)
import Tasks as T


port sendMessage : Value -> Cmd msg


port recvMessage : (Value -> msg) -> Sub msg


port connectWebsocket : Bool -> Cmd msg


type OutMessage
    = Tasks T.Tasks


type InMessage
    = NewTasks T.Tasks


send : OutMessage -> Cmd msg
send outMsg =
    case outMsg of
        Tasks ts ->
            sendTasks ts


sendTasks : T.Tasks -> Cmd msg
sendTasks ts =
    sendHelp "tasks" (Just (T.encodeTasks ts))


sendHelp : String -> Maybe Value -> Cmd msg
sendHelp action payload =
    let
        act =
            [ ( "action", string action ) ]

        pay =
            payload
                |> Maybe.map (\p -> [ ( "payload", p ) ])
                |> Maybe.withDefault []
    in
    sendMessage <| object <| act ++ pay


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
                "new_tasks" ->
                    decodeTasks action.payload

                unknown ->
                    Err ("Unknown action: " ++ unknown)

        Err e ->
            Err ("Failed to decode action: " ++ errorToString e)


decodeTasks : Value -> Result String InMessage
decodeTasks value =
    case Json.Decode.decodeValue T.decodeTasks value of
        Ok tasks ->
            Ok (NewTasks tasks)

        Err e ->
            Err ("Failed to decode tasks payload: " ++ errorToString e)


type alias Action =
    { action : String
    , payload : Value
    }


decodeAction : Json.Decode.Decoder Action
decodeAction =
    map2 Action
        (field "action" Json.Decode.string)
        (field "payload" Json.Decode.value)
