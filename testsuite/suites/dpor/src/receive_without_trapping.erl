-module(receive_without_trapping).

-export([receive_without_trapping/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

receive_without_trapping() ->
    Parent = self(),
    C1 = spawn_link(fun() -> receive _ -> ok end end),
    C2 = spawn(fun() ->
                       receive
                           _ -> C1 ! ok
                       end,
                       Parent ! ok
               end),
    C2 ! ok,
    receive
        _ -> ok
    end.
