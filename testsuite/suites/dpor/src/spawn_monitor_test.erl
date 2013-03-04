-module(spawn_monitor_test).

-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

-include_lib("eunit/include/eunit.hrl").

spawn_monitor_test() ->
    {Pid, Ref} = spawn_monitor(fun() -> ok end),
    demonitor(Ref),
    Result =
    receive
        {'DOWN', Ref, process, Pid, normal} -> result1
    after 0 -> result2
    end,
    ?assertEqual(result2, Result).
