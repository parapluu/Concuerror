-module(test_after_spawns).

-compile(export_all).

test_after_spawns() ->
    Parent = self(),
    spawn(fun() -> Parent ! one end),
    spawn(fun() -> Parent ! two end),
    spawn(fun() -> Parent ! one end),
    One = receive_or_fail(1),
    Two = receive_or_fail(2),
    Three = receive_or_fail(3),
    throw({One, Two, Three}).

receive_or_fail(N) ->
    receive
        Msg -> Msg
    after
        10 ->
            throw(N)
    end.
