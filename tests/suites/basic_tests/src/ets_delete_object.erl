-module(ets_delete_object).

-export([test1/0, test2/0, test3/0]).
-export([scenarios/0]).

scenarios() -> [{T, inf, dpor} || T <- [test1,test2,test3]].

test1() ->
    ets:new(table, [named_table, public]),
    Object1 = {foo, 1},
    spawn(fun() -> ets:delete_object(table, Object1) end),
    spawn(fun() -> ets:lookup(table, foo) end),
    spawn(fun() -> ets:insert(table, {foo,2}) end),
    receive after infinity -> ok end.

test2() ->
    ets:new(table, [named_table, public]),
    Object2 = {bar, 1},
    spawn(fun() -> ets:delete_object(table, Object2) end),
    spawn(fun() -> ets:insert(table, {bar,2}) end),
    spawn(fun() -> ets:update_counter(table, bar, 1) end),
    spawn(fun() -> ets:update_counter(table, bar, 1) end),
    receive after infinity -> ok end.

test3() ->
    ets:new(table, [named_table, public]),
    Object1 = {foo, 1},
    Object2 = {bar, 1},
    spawn(fun() -> ets:delete_object(table, Object1) end),
    spawn(fun() -> ets:delete_object(table, Object2) end),
    spawn(fun() -> ets:lookup(table, foo) end),
    spawn(fun() -> ets:insert(table, {bar,2}) end),
    spawn(fun() -> ets:update_counter(table, bar, 1) end),
    spawn(fun() -> ets:update_counter(table, bar, 1) end),
    receive after infinity -> ok end.
