-module(ets_dependencies_deeper).

-export([ets_dependencies_deeper/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_dependencies_deeper() ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  Parent ! ok
          end),
    spawn(fun() ->
                  ets:insert(table, {y, 2}),
                  [{x, V}] = ets:lookup(table, x),
                  ets:insert(table, {p2, V}),
                  Parent ! ok
          end),
    spawn(fun() ->
                  ets:insert(table, {z, 3}),
                  [{x, V}] = ets:lookup(table, x),
                  Y =
                      case V of
                          0 -> [{y, Q}] = ets:lookup(table, y), Q;
                          1 -> none
                      end,
                  ets:insert(table, {p3, Y}),
                  Parent ! ok
          end),
    receive
        ok ->
            receive
                ok ->
                    receive
                        ok ->
                            [{p2, V}] = ets:lookup(table, p2),
                            [{p3, Y}] = ets:lookup(table, p3),
                            throw({V,Y})
                    end
            end
    end.
