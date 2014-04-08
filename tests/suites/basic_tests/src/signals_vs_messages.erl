-module(signals_vs_messages).

-export([scenarios/0]).
-export([concuerror_options/0]).
-export([test/0]).

concuerror_options() ->
    [{treat_as_normal, die}].

scenarios() ->
    [{test, inf, dpor}].

test() ->
    P = self(),
    register(p, P),
    spawn(fun() -> exit(P, die) end),
    spawn(fun() -> P ! ok end),
    spawn(fun() -> whereis(p) end),
    receive
        ok -> ok
    end.
