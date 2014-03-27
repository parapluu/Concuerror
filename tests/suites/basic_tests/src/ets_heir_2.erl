-module(ets_heir_2).

-export([ets_heir_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_heir_2() ->
    spawn(fun() ->
                  ets:lookup(table, x),
                  throw(too_bad)
          end),
    Heir = spawn(fun() -> ok end),
    ets:new(table, [named_table, {heir, Heir, heir}]).
