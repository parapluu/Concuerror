-module(many_send_to_dead).

-export([many_send_to_dead/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

many_send_to_dead() ->
    Pid = spawn(fun() -> receive _ -> ok after 0 -> ok end end),
    spawn(fun() -> Pid ! msg1 end),
    spawn(fun() -> Pid ! msg2 end),
    receive
    after
        infinity -> deadlock
    end.
