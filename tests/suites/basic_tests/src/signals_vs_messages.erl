-module(signals_vs_messages).

-export([scenarios/0]).
-export([test/0, test1/0]).

-concuerror_options_forced([{treat_as_normal, die}]).

scenarios() ->
    [{T, inf, dpor} || T <- [test, test1]].

test() ->
    P = self(),
    register(p, P),
    spawn(fun() -> exit(P, die) end),
    spawn(fun() -> P ! ok end),
    spawn(fun() -> whereis(p) end),
    receive
        ok -> ok
    end.

test1() ->
    P = self(),
    spawn_link(fun() -> ok end),
    spawn(fun() -> P ! ok end),
    receive
        ok -> ok
    end.
