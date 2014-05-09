-module(sleeping_races_6).

-export([sleeping_races_6/0]).

-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, R} || R <- [dpor,source]].

sleeping_races_6() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {w, 0}),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:insert(table, {w, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:insert(table, {x, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:insert(table, {y, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  ets:lookup(table, y),
                  ets:insert(table, {self(), ?LINE}),
                  ets:insert(table, {z, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {self(), ?LINE}),
                  [{y, Y}] = ets:lookup(table, y),
                  case Y of
                      0 -> ok;
                      1 ->
                          ets:insert(table, {self(), ?LINE}),
                          [{z, Z}] = ets:lookup(table, z),
                          case Z of
                              0 -> ok;
                              1 ->
                                  ets:insert(table, {self(), ?LINE}),
                                  [{x, X}] = ets:lookup(table, x),
                                  case X of
                                      0 -> ok;
                                      1 ->
                                          ets:insert(table, {self(), ?LINE}),
                                          ets:lookup(table, w)
                                  end
                          end
                  end
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
