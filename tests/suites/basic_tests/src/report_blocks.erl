-module(report_blocks).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    Parent = self(),
    spawn(fun() -> Parent ! ok end),
    receive
        ok -> ok
    end,
    receive
    after
        infinity -> deadlock
    end.
