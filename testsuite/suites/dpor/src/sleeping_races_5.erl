-module(sleeping_races_5).

-export([sleeping_races_5/0]).

-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

sleeping_races_5() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:insert(table, {y, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:insert(table, {x, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:lookup(table, x),
                  ets:insert(table, {self(), ?LINE}),
                  ets:lookup(table, y)
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  [{x, X}] = ets:lookup(table, x),
                  case X of
                      0 -> ok;
                      1 ->
                          ets:insert(table, {self(), ?LINE}),
                          ets:lookup(table, y)
                  end
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:lookup(table, y)
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
