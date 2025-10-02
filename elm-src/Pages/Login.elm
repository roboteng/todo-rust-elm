module Pages.Login exposing (Model, Msg(..), OutMsg(..), init, update, view)

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
        }


type Msg
    = UpdateUsername String
    | UpdatePassword String
    | Submit
    | Response (Result Http.Error ())


type OutMsg
    = LoggedIn
    | PushUrl String
    | Batch (List OutMsg)
    | None


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
                { url = "/api/login"
                , body = Http.jsonBody <| Encode.object [ ( "username", Encode.string model.username ), ( "password", Encode.string model.password ) ]
                , expect = Http.expectWhatever Response
                }
            , None
            )

        Response result ->
            case result of
                Ok _ ->
                    ( M { model | message = Just "You're now logged in!" }
                    , Cmd.none
                    , Batch [ LoggedIn, PushUrl <| Route.encodeRoute Route.Home ]
                    )

                Err (Http.BadStatus 401) ->
                    ( M { model | message = Just "Incorrect Credentials" }, Cmd.none, None )

                Err _ ->
                    ( M { model | message = Just "Some error occurred" }, Cmd.none, None )


view : Model -> Html Msg
view (M model) =
    main_ []
        [ form
            [ onSubmit <| Submit
            ]
            [ h1 [] [ text "Login" ]
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
                    , attribute "autocomplete" "current-password"
                    , value model.password
                    , onInput <| UpdatePassword
                    ]
                    []
                ]
            , button [ type_ "submit" ] [ text "Login" ]
            , p []
                [ text "Don't have an account?"
                , a [ href <| Route.encodeRoute <| Route.Register ] [ text "Register" ]
                ]
            ]
        ]
