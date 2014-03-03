-module(complete_test_1).

-export([complete_test_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

complete_test_1() ->
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
                  cover(?LINE),
                  case X =:= 0 of
                      true  -> ets:lookup(table, y);
                      false -> ok
                  end
          end),
    spawn(fun() ->
                  cover(?LINE),
                  ets:lookup(table, x),
                  cover(?LINE),
                  ets:lookup(table, y)
          end),
    spawn(fun() ->
                  cover(?LINE),
                  ets:insert(table, {x, 2})
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.

cover(L) ->
    ets:insert(table, {L, ok}).
