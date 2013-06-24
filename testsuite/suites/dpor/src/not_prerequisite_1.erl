-module(not_prerequisite_1).

-export([not_prerequisite_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

not_prerequisite_1() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  ets:insert(table, {y, 1})
          end),
    spawn(fun() ->
                  [{y, Y}] = ets:lookup(table, y),
                  case Y of
                      0 -> ok;
                      1 -> ets:lookup(table, x)
                  end
          end),
    spawn(fun() ->
                  ets:insert(table, {y, 1})
          end),
    receive
    after
        infinity -> ok
    end.
