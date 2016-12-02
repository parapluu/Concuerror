-module(reuse_raw_pid).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{symbolic_names, false}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    P = self(),
    spawn(fun() -> P ! ok end),
    Msg =
        receive
            ok -> received
        after
            0 -> expired
        end,
    spawn(fun() -> P ! Msg end),
    receive
        M -> throw(M)
    end.
