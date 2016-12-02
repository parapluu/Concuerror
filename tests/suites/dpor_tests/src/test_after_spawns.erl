-module(test_after_spawns).

-export([test_after_spawns/0]).
-export([scenarios/0]).

-concuerror_options_forced([{scheduling, oldest}]).

scenarios() -> [{?MODULE, inf, dpor}].

test_after_spawns() ->
    Parent = self(),
    spawn(fun() -> Parent ! one end),
    spawn(fun() -> Parent ! two end),
    spawn(fun() -> Parent ! one end),
    One = receive_or_fail(1),
    Two = receive_or_fail(2),
    Three = receive_or_fail(3),
    throw({ok, One, Two, Three}).

receive_or_fail(N) ->
    receive
        Msg -> Msg
    after
        10 ->
            List = get_msgs([]),
            {N, List}
    end.

get_msgs(Acc) ->
    receive
        P ->
            get_msgs([P|Acc])
    after
        0 ->
            Acc
    end.
