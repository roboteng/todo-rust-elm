port module Ports exposing (recvAction, send, OutMessage(..))

import Dict exposing (Dict)
import Json.Decode exposing (errorToString, field, map2)
import Json.Encode exposing (Value, object, string)


port sendMessage : Value -> Cmd msg


port recvMessage : (Value -> msg) -> Sub msg

type OutMessage =
    Greet String
    | StartScanning

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

recvAction : Dict String (Value -> msg) -> (String -> msg) -> Sub msg
recvAction onAction onError =
    recvMessage <|
        \value ->
            case Json.Decode.decodeValue decodeAction value of
                Ok action ->
                    Dict.get action.action onAction
                        |> Maybe.map (\a -> a action.payload)
                        |> Maybe.withDefault (onError ("Unknown Command" ++ action.action))

                Err e ->
                    onError (errorToString e)


type alias Action =
    { action : String
    , payload : Value
    }


decodeAction : Json.Decode.Decoder Action
decodeAction =
    map2 Action
        (field "action" Json.Decode.string)
        (field "payload" Json.Decode.value)
