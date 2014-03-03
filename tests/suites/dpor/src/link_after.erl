-module(link_after).

-export([link_after/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

link_after() ->
    P1 = spawn(fun() ->
                       process_flag(trap_exit, true),
                       receive
                           _ -> throw(untrapped)
                       after
                           0 -> ok
                       end
               end),
    try link(P1)
    catch _:_ -> ok
    end.
