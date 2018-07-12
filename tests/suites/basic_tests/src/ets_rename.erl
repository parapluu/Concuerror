-module(ets_rename).

-compile(export_all).

scenarios() ->
  [ rename_good
  , rename_bad
  , rename_public
  ].

rename_good() ->
  ets:new(table, [named_table]),
  ets:rename(table, new_table).

rename_public() ->
  ets:new(table, [public, named_table]),
  Q =
    spawn_monitor(
      fun() ->
          ets:rename(table, bad)
      end),
  receive
    {'DOWN', _, _, _, normal} -> ok
  end.

rename_bad() ->
  ets:new(table, [named_table]),
  Q =
    spawn_monitor(
      fun() ->
          try
            ets:rename(table, bad),
            exit(wrong)
          catch
            error:_ -> ok
          end
      end),
  receive
    {'DOWN', _, _, _, normal} -> ok
  end.
