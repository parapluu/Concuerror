-module(many_monitors).

-export([many_monitors/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

many_monitors() ->
    P1 = spawn(fun() -> ok end),
    P2 = spawn(fun() -> ok end),
    monitor(process, P1),
    monitor(process, P2),
    receive after infinity -> ok end.
