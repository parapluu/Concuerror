-module(conditional_readers_3).

-export([conditional_readers_3/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

conditional_readers_3() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  ets:insert(table, {x, 1})
          end),
    spawn(fun() ->
                  [{y, Y}] = ets:lookup(table, y),
                  case Y of
                      0 -> ets:lookup(table, x);
                      _ -> ok
                  end
          end),
    spawn(fun() ->
                  ets:lookup(table, x),
                  ets:insert(table, {y, 1})
          end),
    receive
    after
        infinity -> ok
    end.
