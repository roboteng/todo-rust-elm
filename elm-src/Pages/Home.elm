module Pages.Home exposing (Model, Msg, OutMsg(..), init, update, view)

import Browser
import Browser.Navigation as Nav
import Css exposing (listStyleType, none)
import Html.Styled
    exposing
        ( Html
        , a
        , button
        , div
        , li
        , main_
        , nav
        , text
        , toUnstyled
        , ul
        )
import Html.Styled.Attributes exposing (css, href)
import Html.Styled.Events exposing (onClick)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Route exposing (Route(..), parseRoute)
import Tasks


type alias Context =
    { loggedIn : Bool, tasks : Tasks.Tasks }


type Model
    = M
        { loggedIn : Bool
        , tasks : List Tasks.TaskWithId
        }


type Msg
    = SyncTasksClicked


type OutMsg
    = None
    | Sync


init : Context -> Model
init context =
    M
        { loggedIn = context.loggedIn
        , tasks = Tasks.allTasks context.tasks
        }


update : Context -> Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update context msg (M _) =
    case msg of
        SyncTasksClicked ->
            ( init context, Cmd.none, Sync )


view : Model -> Html Msg
view (M model) =
    main_ [] <|
        if model.loggedIn then
            [ ul [ css [ listStyleType none ] ]
                (viewTasks model.tasks)
            , button [ onClick <| SyncTasksClicked ] [ text "Sync Tasks" ]
            , a [ href <| Route.encodeRoute Route.New ] [ text "Create new Item" ]
            ]

        else
            [ ul [ css [ listStyleType none ] ]
                (viewTasks model.tasks)
            , a [ href <| Route.encodeRoute Route.New ] [ text "Create new Item" ]
            ]


viewTasks : List Tasks.TaskWithId -> List (Html Msg)
viewTasks tasks =
    List.map
        (\task -> li [] [ a [ href <| Route.encodeRoute <| Route.TaskDetails (Tuple.first task) ] [ text <| (Tuple.second task |> .summary) ] ])
        tasks
