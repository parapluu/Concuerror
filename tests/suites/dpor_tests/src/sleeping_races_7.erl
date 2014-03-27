-module(sleeping_races_7).

-export([sleeping_races_7/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

sleeping_races_7() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  cover(?LINE),
                  ets:insert(table, {y, 1})
          end),
    spawn(fun() ->
                  cover(?LINE),
                  ets:insert(table, {x, 1})
          end),
    spawn(fun() ->
                  cover(?LINE),
                  [{x, X}] = ets:lookup(table, x),
                  case X of
                      0 -> ok;
                      1 ->
                          cover(?LINE),
                          [{y, _}] = ets:lookup(table, y)
                  end
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.

cover(L) ->
    ets:insert(table, {L, ok}).
