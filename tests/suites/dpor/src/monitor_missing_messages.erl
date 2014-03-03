-module(monitor_missing_messages).

-export([monitor_missing_messages/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

monitor_missing_messages() ->
    spawn_monitor(fun() -> ok end),
    receive
        _ -> throw(boo)
    after
        0 -> ok
    end.
