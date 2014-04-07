-module(concuerror_crash).

-export([scenarios/0]).
-export([concuerror_options/0]).
-export([test/0]).

concuerror_options() ->
    [{timeout, 3000}, {report_unknown, false}, {assume_racing, true}].

scenarios() ->
    [{test, inf, dpor, crash}].

test() ->
    P = self(),
    spawn(fun() -> P ! ok end),
    receive
        ok ->
            list_to_pid("<0.42.42>") ! ok
    after
        0 -> ok
    end.
