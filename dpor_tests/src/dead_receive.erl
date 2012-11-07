-module(dead_receive).

-export([dead_receive/0]).

dead_receive() ->
    Timeout = infinity,
    receive
    after Timeout -> ok
    end.
