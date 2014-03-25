-module(irrelevant_send).

-export([irrelevant_send/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

irrelevant_send() ->
    process_flag(trap_exit, true),
    P1 = spawn_link(fun() -> ok end),
    P2 = spawn_link(fun() -> ok end),
    receive
        {'EXIT', P1, normal} -> ok;
        {'EXIT', P2, normal} -> throw(error)
    end.
