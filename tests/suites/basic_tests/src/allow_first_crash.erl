-module(allow_first_crash).

-export([scenarios/0]).
-export([concuerror_options/0]).
-export([test/0]).

concuerror_options() ->
    [{allow_first_crash, false}].

scenarios() ->
    [{test, inf, dpor, crash}].

test() ->
    P = self(),
    spawn(fun() -> P ! ok end),
    receive
        ok -> ok
    after
        0 -> ok
    end,
    exit(error).
