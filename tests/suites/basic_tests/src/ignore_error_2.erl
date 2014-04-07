-module(ignore_error_2).

-export([scenarios/0]).
-export([concuerror_options/0]).
-export([test/0]).

concuerror_options() ->
    [{ignore_error, deadlock}].

scenarios() ->
    [{test, inf, dpor}].

test() ->
    P = self(),
    spawn(fun() -> exit(boom) end),
    receive after infinity -> ok end.
