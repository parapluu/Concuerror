-module(ets_dependencies_2).

-export([ets_dependencies_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_dependencies_2() ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() ->
                  [{x, V}] = ets:lookup(table, x),
                  case V of
                      0 -> ets:insert(table, {y, 1});
                      1 -> ets:insert(table, {z, 0})
                  end,
                  Parent ! ok
          end),
    spawn(fun() ->
                  [{y, V}] = ets:lookup(table, y),
                  case V of
                      0 -> ets:insert(table, {z, 1});
                      1 -> ets:insert(table, {x, 0})
                  end,
                  Parent ! ok
          end),
    spawn(fun() ->
                  [{z, V}] = ets:lookup(table, z),
                  case V of
                      0 -> ets:insert(table, {x, 1});
                      1 -> ets:insert(table, {y, 0})
                  end,
                  Parent ! ok
          end),
    receive
        ok ->
            receive
                ok ->
                    receive
                        ok ->
                            [{x, X}] = ets:lookup(table, x),
                            [{y, Y}] = ets:lookup(table, y),
                            [{z, Z}] = ets:lookup(table, z),
                            throw({X,Y,Z})
                    end
            end
    end.
