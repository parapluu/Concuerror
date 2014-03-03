-module(ets_dependencies_deeper_2).

-export([ets_dependencies_deeper_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_dependencies_deeper_2() ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    T1 =
        spawn(fun() ->
                      ets:insert(table, {x, 1}),
                      receive
                          ok -> Parent ! ok
                      end
              end),
    T2 =
        spawn(fun() ->
                      ets:insert(table, {y, 2}),
                      [{x, V}] = ets:lookup(table, x),
                      ets:insert(table, {p2, V}),
                      receive
                          ok -> T1 ! ok
                      end
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
                  T2 ! ok
          end),
    receive
        ok ->
            [{p2, V}] = ets:lookup(table, p2),
            [{p3, Y}] = ets:lookup(table, p3),
            throw({V,Y})
    end.
