-module(ets_delete_2).

-export([ets_delete_2/0]).
-export([ets_delete_2_twice/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_delete_2() ->
    P = self(),
    spawn(fun() ->
                  ets:new(table, [public, named_table]),
                  P ! ok
          end),
    receive ok ->
            ets:insert(table, {key, value})
    end,
    receive after infinity -> ok end.

ets_delete_2_twice() ->
    concuets = ets:new(concuets, [ordered_set, named_table, public]),
    ets:insert(concuets, {key, value}),
    spawn(fun() -> ets:delete(concuets, key) end),
    ets:delete(concuets, key),
    receive after infinity -> ok end.
