-module(many_links).

-export([many_links/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

many_links() ->
    process_flag(trap_exit, true),
    P1 = spawn(fun() -> ok end),
    P2 = spawn(fun() -> ok end),
    link(P1),
    link(P2),
    receive after infinity -> ok end.
