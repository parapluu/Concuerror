-module(erlang_display).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    erlang:display(test),
    receive after infinity -> ok end.
