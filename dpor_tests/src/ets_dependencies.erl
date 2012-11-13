-module(ets_dependencies).

-export([ets_dependencies/0]).

ets_dependencies() ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    spawn(fun() ->
                  ets:insert(table, {x, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {y, 2}),
                  ets:lookup(table, x)
          end),
    spawn(fun() ->
                  ets:insert(table, {z, 3}),
                  ets:lookup(table, x)
          end),
    receive
    after
        infinity -> ok
    end.
