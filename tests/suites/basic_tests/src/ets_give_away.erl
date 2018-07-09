-module(ets_give_away).

-compile(export_all).

scenarios() ->
  [ give_away_good
  , give_away_bad
  ].

give_away_good() ->
  P = self(),
  ets:new(table, [private, named_table, {heir, P, returned}]),
  P1 =
    spawn(
      fun() ->
          receive
            {'ETS-TRANSFER', table, P, given} ->
              ets:insert(table, {x, 2})
          end
      end),
  ets:insert(table, {x, 1}),
  ets:give_away(table, P1, given),
  receive
    {'ETS-TRANSFER', table, P1, returned} ->
      ets:insert(table, {x, 3})
  end.

give_away_bad() ->
  P = self(),
  ets:new(table, [public, named_table]),
  Q =
    spawn_monitor(
      fun() ->
          try
            ets:give_away(table, P, bad),
            exit(wrong)
          catch
            error:_ -> ok
          end
      end),
  receive
    {'DOWN', _, _, _, normal} -> ok
  end.
