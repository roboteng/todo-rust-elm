module Register exposing (Model, Msg(..), OutMsg(..), init, update, view)

import Browser.Navigation as Nav
import Html.Styled
    exposing
        ( Html
        , a
        , button
        , div
        , form
        , h1
        , input
        , label
        , main_
        , p
        , text
        )
import Html.Styled.Attributes
    exposing
        ( attribute
        , for
        , href
        , id
        , placeholder
        , type_
        , value
        )
import Html.Styled.Events exposing (onInput, onSubmit)
import Http
import Json.Encode as Encode
import Route


type OutMsg
    = PushRoute Route.Route
    | None


type Model
    = M
        { username : String
        , password : String
        , message : Maybe String
        }


type Msg
    = UpdateUsername String
    | UpdatePassword String
    | Submit
    | Response (Result Http.Error ())


init : Model
init =
    M
        { username = ""
        , password = ""
        , message = Nothing
        }


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg (M model) =
    case msg of
        UpdateUsername username ->
            ( M { model | username = username }, Cmd.none, None )

        UpdatePassword password ->
            ( M { model | password = password }, Cmd.none, None )

        Submit ->
            ( init
            , Http.post
                { url = "/api/register"
                , body = Http.jsonBody <| Encode.object [ ( "username", Encode.string model.username ), ( "password", Encode.string model.password ) ]
                , expect = Http.expectWhatever Response
                }
            , None
            )

        Response result ->
            case result of
                Ok _ ->
                    ( M { model | message = Just "Account Created" }
                    , Cmd.none
                    , PushRoute Route.Login
                    )

                Err (Http.BadStatus 409) ->
                    ( M { model | message = Just "Username already exists, pick a different one" }, Cmd.none, None )

                Err _ ->
                    ( M { model | message = Just "Some error occurred" }, Cmd.none, None )


view : Model -> Html Msg
view (M model) =
    main_ []
        [ form
            [ onSubmit <| Submit
            ]
            [ h1 [] [ text "Register" ]
            , div []
                [ text <| Maybe.withDefault "" model.message
                , label [ for "username" ] [ text "Username" ]
                , input
                    [ type_ "text"
                    , placeholder "joeSmith"
                    , id "username"
                    , attribute "autocomplete" "username"
                    , value model.username
                    , onInput <| UpdateUsername
                    ]
                    []
                ]
            , div []
                [ label [ for "password" ] [ text "Password" ]
                , input
                    [ type_ "password"
                    , id "password"
                    , attribute "autocomplete" "new-password"
                    , value model.password
                    , onInput <| UpdatePassword
                    ]
                    []
                ]
            , button [ type_ "submit" ] [ text "Register" ]
            , p []
                [ text "Already have an account?"
                , a [ href <| Route.encodeRoute <| Route.Login ] [ text "Login" ]
                ]
            ]
        ]
