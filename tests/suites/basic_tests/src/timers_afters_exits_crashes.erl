-module(timers_afters_exits_crashes).

-export([scenarios/0]).

-export([my_start_timer/0,
         my_exit_ok/0,
         my_exit_bad/0,
         child_crashes/0,
         both_crash/0]).

scenarios() ->
    [{N,P,dpor} || {N,P} <- [{my_start_timer, inf},
                          {my_exit_ok, inf},
                          {my_exit_bad, inf},
                          {child_crashes, inf},
                          {both_crash, inf}]].

my_start_timer() ->
    P1 = spawn(fun() -> receive _ -> ok end end),
    spawn(fun() -> P1 ! ok end),
    spawn(fun() -> erlang:start_timer(50, P1, ok) end),
    receive after infinity -> ok end.

my_exit_ok() ->
    P1 = spawn(fun() -> receive _ -> ok end end),
    exit(P1, normal),
    receive after infinity -> ok end.

my_exit_bad() ->
    P1 = spawn(fun() -> receive _ -> ok end end),
    exit(P1, whatever),
    receive after infinity -> ok end.

child_crashes() ->
    P1 = spawn(fun() -> error(child) end),
    P1 ! ok, P1 ! ok, P1 ! ok, P1 ! ok.

both_crash() ->
    spawn(fun() -> error(child) end),
    error(parent).
