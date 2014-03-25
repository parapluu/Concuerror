-module(manywrite).

-export([manywrite/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

manywrite() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  ets:insert(table, {x,1}),
                  block()
          end),
    spawn(fun() ->
                  ets:insert(table, {x,2}),
                  block()
          end),
    spawn(fun() ->
                  ets:insert(table, {y,1}),
                  block()
          end),
    spawn(fun() ->
                  ets:insert(table, {y,2}),
                  block()
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
