-module(depend_6).

-export([depend_6/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

depend_6() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() ->
                  ets:lookup(table, y),
                  ets:lookup(table, z)
          end),
    spawn(fun() ->
                  ets:lookup(table, y)
          end),
    spawn(fun() -> ets:insert(table, {z, 1}) end),
    spawn(fun() ->
                  ets:insert(table, {y, 1}),
                  ets:insert(table, {y, 2})
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
