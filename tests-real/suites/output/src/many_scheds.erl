-module(many_scheds).

-concuerror_options([{ignore_error, deadlock}]).

-export([test/0, test_large/0]).

test() ->
  test(6).

test_large() ->
  test(10).

test(N) ->
  ets:new(table, [public, named_table]),
  Fun =
    fun() ->
        ets:insert(table, {key, self()})
    end,
  [spawn(Fun) || _ <- lists:seq(1, N)],
  receive after infinity -> ok end.
