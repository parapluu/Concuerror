-module(trigger_the_after).

-export([trigger_the_after/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

trigger_the_after() ->
    Receiver = spawn(fun receive_two/0),
    spawn(sender(Receiver, two)),
    spawn(sender(Receiver, one)),
    error(error).

receive_two() ->
    receive
        one ->
            receive
                two -> throw(both)
            after
                100 -> throw(one)
            end
    end.

sender(Receiver, Msg) ->
    fun() -> Receiver ! Msg end.
