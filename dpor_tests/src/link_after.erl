-module(link_after).

-export([link_after/0]).

link_after() ->
    P = self(),
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
