-module(dead_receive).

-export([dead_receive/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

dead_receive() ->
    Timeout = infinity,
    receive
    after Timeout -> ok
    end.
