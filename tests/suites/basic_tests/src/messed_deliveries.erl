-module(messed_deliveries).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    P = self(),
    process_flag(trap_exit, true),
    Q = spawn(fun() -> receive _ -> ok after 0 -> ok end end),
    spawn(fun() -> exit(P, die) end),
    spawn(fun() -> exit(P, die) end),
    Q ! ok.

