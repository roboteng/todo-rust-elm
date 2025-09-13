module Register exposing (Model, Msg(..), init, update, view)

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


type Model
    = M
        { username : String
        , password : String
        , message : Maybe String
        , key : Nav.Key
        }


type Msg
    = UpdateUsername String
    | UpdatePassword String
    | Submit
    | Response (Result Http.Error ())


init : Nav.Key -> Model
init key =
    M
        { username = ""
        , password = ""
        , message = Nothing
        , key = key
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg (M model) =
    case msg of
        UpdateUsername username ->
            ( M { model | username = username }, Cmd.none )

        UpdatePassword password ->
            ( M { model | password = password }, Cmd.none )

        Submit ->
            ( init model.key
            , Http.post
                { url = "/api/register"
                , body = Http.jsonBody <| Encode.object [ ( "username", Encode.string model.username ), ( "password", Encode.string model.password ) ]
                , expect = Http.expectWhatever Response
                }
            )

        Response result ->
            case result of
                Ok _ ->
                    ( M { model | message = Just "Account Created" }
                    , Nav.pushUrl model.key <| Route.encodeRoute Route.Login
                    )

                Err (Http.BadStatus 409) ->
                    ( M { model | message = Just "Username already exists, pick a different one" }, Cmd.none )

                Err _ ->
                    ( M { model | message = Just "Some error occurred" }, Cmd.none )


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
