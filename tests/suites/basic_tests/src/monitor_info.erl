-module(monitor_info).

-export([scenarios/0]).
-export([test1/0,test2/0]).

scenarios() ->
    [{T, inf, dpor} || T <- [test1,test2]].

test1() ->
    {P,R} = spawn_monitor(fun() -> ok end),
    Before = receive _ -> true after 0 -> false end,
    case demonitor(R, [info]) of
        true ->
            receive _ -> error(never)
            after 0 -> ok
            end;
        false ->
            true = Before orelse receive _ -> true end
    end.

test2() ->
    {P,R} = spawn_monitor(fun() -> ok end),
    Before = receive _ -> true after 0 -> false end,
    case demonitor(R, [flush, info]) of
        true ->
            receive _ -> error(never)
            after 0 -> ok
            end;
        false -> true
    end.
