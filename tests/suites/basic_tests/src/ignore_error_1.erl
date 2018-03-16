-module(ignore_error_1).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{ignore_error, abnormal_exit}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    P = self(),
    spawn(fun() -> exit(boom) end),
    receive after infinity -> ok end.
