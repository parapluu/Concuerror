-module(io_format).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    io:format("Test"),
    receive after infinity -> ok end.
