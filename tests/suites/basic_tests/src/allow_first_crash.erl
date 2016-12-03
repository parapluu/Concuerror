-module(allow_first_crash).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{keep_going, false}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    P = self(),
    spawn(fun() -> P ! ok end),
    receive
        ok -> ok
    after
        0 -> ok
    end,
    exit(error).
