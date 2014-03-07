-module(exit_message_unpredicted).

-export([exit_message_unpredicted/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

exit_message_unpredicted() ->
    P1 = self(),
    {P11,_} = spawn_monitor(fun() -> ok end),
    P12 = spawn(fun() -> P1 ! ok end),
    is_process_alive(P11),
    receive
        _ -> ok
    end,
    receive after infinity -> ok end.
