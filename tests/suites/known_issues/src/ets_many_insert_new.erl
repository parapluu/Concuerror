-module(ets_many_insert_new).

-export([ets_many_insert_new/0, ets_many_insert_new/1]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_many_insert_new() ->
    ets_many_insert_new(3).

ets_many_insert_new(N) ->
    ets:new(table, [public, named_table]),
    Writer =
        fun(I) ->
            ets:insert_new(table, {x, I})
        end,
    [spawn(fun() -> Writer(I) end) || I <- lists:seq(1, N)],
    ets:lookup(table, x),
    receive
    after
        infinity -> deadlock
    end.
