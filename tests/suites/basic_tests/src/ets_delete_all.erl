-module(ets_delete_all).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

scenarios() ->
  [ delete_all_good
  , delete_all_bad
  , race_delete_all_read
  , race_delete_all_write
  ].

delete_all_good() ->
  ets:new(table, [named_table]),
  ets:insert(table, [{x, 1}, {y, 2}]),
  ets:delete_all_objects(table),
  ?assertEqual([], ets:lookup(table, x)),
  ?assertEqual([], ets:lookup(table, y)).

delete_all_bad() ->
  ets:new(table, [named_table]),
  ets:insert(table, [{x, 1}, {y, 2}]),
  Q =
    spawn_monitor(
      fun() ->
          try
            ets:delete_all_objects(table),
            exit(wrong)
          catch
            error:_ -> ok
          end
      end),
  receive
    {'DOWN', _, _, _, normal} ->
      ?assertEqual([{x, 1}], ets:lookup(table, x)),
      ?assertEqual([{y, 2}], ets:lookup(table, y))
  end.

race_delete_all_read() ->
  ets:new(table, [named_table]),
  ets:insert(table, [{x, 1}, {y, 2}]),
  Q =
    spawn_monitor(
      fun() ->
          ets:lookup(table, x)
      end),
  ets:delete_all_objects(table),
  receive
    {'DOWN', _, _, _, normal} ->
      ?assertEqual([], ets:lookup(table, x)),
      ?assertEqual([], ets:lookup(table, y))
  end.

race_delete_all_write() ->
  ets:new(table, [public, named_table]),
  ets:insert(table, [{x, 1}, {y, 2}]),
  Q =
    spawn_monitor(
      fun() ->
          ets:insert(table, {x, 2})
      end),
  ets:delete_all_objects(table),
  receive
    {'DOWN', _, _, _, normal} ->
      ?assertEqual([], ets:lookup(table, y))
  end.
