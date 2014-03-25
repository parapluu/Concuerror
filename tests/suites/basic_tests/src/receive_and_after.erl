-module(receive_and_after).

-export([receive_and_after/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

receive_and_after() ->
    spawn(fun p1/0) ! enable.

p1() ->
    receive
        enable -> throw(kaboom)
    after
        10 ->
            throw(boom)
    end.
