-module('POPL_optimal_example').

-export([test/0]).
-export([scenarios/0]).

-concuerror_options_forced([{scheduling, oldest}]).

scenarios() -> [{test, inf, R} || R <- [dpor,source]].

test() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> ets:insert(table, {x, 1}) end),
    spawn(fun() -> ets:insert(table, {y, 1}) end),
    spawn(fun() ->
                  [{y, Y}] = ets:lookup(table, y),
                  case Y of
                      1 -> ok;
                      0 -> ets:insert(table, {z, 1})
                  end
          end),
    spawn(fun() ->
                  [{z, Z}] = ets:lookup(table, z),
                  case Z of
                      0 -> ok;
                      1 ->
                          [{y, Y}] = ets:lookup(table, y),
                          case Y of
                              1 -> ok;
                              0 -> ets:insert(table, {x, 2})
                          end
                  end
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
