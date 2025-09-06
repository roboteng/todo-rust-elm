module Register exposing (Model, Msg(..), OutCmd(..), init, update, view)

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
        , css
        , for
        , href
        , id
        , placeholder
        , type_
        , value
        )
import Html.Styled.Events exposing (on, onClick, onInput, onSubmit)
import Http
import Route


type alias Model =
    { username : String
    , password : String
    , error : Maybe String
    }


type Msg
    = UpdateUsername String
    | UpdatePassword String
    | Submit
    | Response (Result Http.Error String)


type OutCmd
    = Register String String
    | None


init : Model
init =
    { username = ""
    , password = ""
    , error = Nothing
    }


update : Msg -> Model -> ( Model, OutCmd )
update msg model =
    case msg of
        UpdateUsername username ->
            ( { model | username = username }, None )

        UpdatePassword password ->
            ( { model | password = password }, None )

        Submit ->
            ( init, Register model.username model.password )

        Response result ->
            case result of
                Ok _ ->
                    ( { model | error = Nothing }, None )

                Err (Http.BadStatus 409) ->
                    ( { model | error = Just "Username already exsists" }, None )

                Err error ->
                    ( { model | error = Just "Some error occurred" }, None )


view : Model -> Html Msg
view model =
    main_ []
        [ form
            [ onSubmit <| Submit
            ]
            [ h1 [] [ text "Register" ]
            , div []
                [ text <| Maybe.withDefault "" model.error
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
