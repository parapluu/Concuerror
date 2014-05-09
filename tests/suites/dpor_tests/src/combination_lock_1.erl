-module(combination_lock_1).

-export([combination_lock_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, R} || R <- [dpor,source]].

combination_lock_1() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {v, 0}),
    ets:insert(table, {w, 0}),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> ets:insert(table, {z, 1}) end),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  ets:insert(table, {a, 1}),
                  [{y, Y}] = ets:lookup(table, y),
                  case Y of
                      1 ->
                          ets:insert(table, {w, 1}),
                          ets:insert(table, {b, 0});
                      _ -> ok
                  end

          end),
    spawn(fun() ->
                  [{x, X}] = ets:lookup(table, x),
                  case X of
                      1 ->
                          ets:insert(table, {y, 1}),
                          ets:insert(table, {c, 0}),
                          [{v, V}] = ets:lookup(table, v),
                          case V of
                              1 -> ets:lookup(table, z);
                              _ -> ok
                          end;
                      _ -> ok
                  end
          end),
    spawn(fun() ->
                  [{w, W}] = ets:lookup(table, w),
                  case W of
                      1 ->
                          ets:insert(table, {v, 1}),
                          ets:insert(table, {d, 0});
                      _ -> ok
                  end
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
