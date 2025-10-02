module TaskId exposing (TaskId, decode, encode, generate)

import Json.Decode as Decode
import Json.Encode as Encode
import Random


type TaskId
    = TaskId Int


decode : Decode.Decoder TaskId
decode =
    Decode.map TaskId Decode.int


encode : TaskId -> Encode.Value
encode (TaskId id) =
    Encode.int id


generate : Random.Generator TaskId
generate =
    Random.int 1 0xFFFFFFFF |> Random.map TaskId
