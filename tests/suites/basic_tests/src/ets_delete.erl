-module(ets_delete).

-compile(export_all).

scenarios() -> [{T, inf, dpor} || T <- [?MODULE, ets_delete_plain, ets_delete_bad]].

ets_delete() ->
    ets:new(table, [public, named_table]),
    spawn(fun() ->
                  ets:insert(table, {key, value})
          end),
    ets:delete(table),
    receive
        deadlock -> ok
    end.

ets_delete_plain() ->
  ets:new(table, [public, named_table]),
  ets:delete(table).

ets_delete_bad() ->
  ets:new(table, [public, named_table]),
  spawn_monitor(
    fun() ->
        try
          ets:delete(table),
          exit(wrong)
        catch
          error:_ -> ok
        end
    end),
  receive
    {'DOWN', _, _, _, normal} -> ok
  end.
