-module(ets_new_failure).

-export([ets_new_failure/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_new_failure() ->
    ets:new(table, [named_table, public]),
    ets:new(table, [named_table, public]).
