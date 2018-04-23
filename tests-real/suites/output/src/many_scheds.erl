-module(many_scheds).

-concuerror_options([{ignore_error, deadlock}]).

-export([test/0]).

test() ->
  ets:new(table, [public, named_table]),
  Fun =
    fun() ->
        ets:insert(table, {key, self()})
    end,
  [spawn(Fun) || _ <- lists:seq(1, 6)],
  receive after infinity -> ok end.
