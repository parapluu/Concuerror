-module(hairbrush_teeth_1).

-export([hairbrush_teeth_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

hairbrush_teeth_1() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  ets:insert(table, {x, 2})
          end),
    spawn(fun() ->
                  ets:lookup(table, x),
                  ets:lookup(table, x)
          end),
    receive
    after
        infinity -> ok
    end.
