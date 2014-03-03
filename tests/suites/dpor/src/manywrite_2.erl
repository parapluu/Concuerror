-module(manywrite_2).

-export([manywrite_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

manywrite_2() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {w, 0}),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> cover(), ets:insert(table, {w, 1}) end),
    spawn(fun() -> cover(), ets:insert(table, {x, 1}) end),
    spawn(fun() -> cover(), ets:insert(table, {y, 1}) end),
    spawn(fun() -> cover(), ets:insert(table, {x, 2}) end),
    spawn(fun() -> cover(), ets:insert(table, {y, 2}) end),
    spawn(fun() -> cover(), ets:insert(table, {z, 1}) end),
    spawn(fun() -> cover(), ets:insert(table, {z, 2}) end),
    spawn(fun() -> cover(), ets:insert(table, {w, 2}) end),
    block().

cover() ->
    ets:insert(table, {self(), ok}).

block() ->
    receive
    after
        infinity -> ok
    end.
