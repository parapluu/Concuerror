-module(wakeup_many).

-export([wakeup_many/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

wakeup_many() ->
    ets:new(table, [named_table, public]),
    spawn(fun() -> ets:insert(table, {x, 1}) end),
    spawn(fun() -> ets:insert(table, {x, 0}) end),
    ets:insert(table, {x,1}),
    receive after infinity -> deadlock end.
