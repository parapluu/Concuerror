-module(io_error).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    io:format(standard_error,"Test",[]),
    receive after infinity -> ok end.
