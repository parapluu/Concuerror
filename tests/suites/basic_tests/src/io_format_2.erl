-module(io_format_2).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    spawn(fun() -> io:format("Child~n") end),
    io:format("Parent~n"),
    receive after infinity -> ok end.
