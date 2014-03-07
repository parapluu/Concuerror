-module(difficult_readers).

-export([difficult_readers/0]).

-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

difficult_readers() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:insert(table, {x, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:insert(table, {x, 2})
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:lookup(table, x)
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:lookup(table, x)
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
