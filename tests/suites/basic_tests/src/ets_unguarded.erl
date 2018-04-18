-module(ets_unguarded).

-export([test/0]).

-export([scenarios/0]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

%%------------------------------------------------------------------------------

test() ->
  ets:new(table, [named_table, public]),
  Fun =
    fun() ->
        ets:insert(table, {1, self()})
    end,
  _ = [spawn(Fun) || _ <- lists:seq(1, 3)].
