-module(ets_update_element).

-compile(export_all).

scenarios() ->
    [ update_element_good
    , update_element_bad
    ].

update_element_good() ->
  ets:new(table, [named_table, public]),
  ets:insert(table, {x, 1}),
  spawn_monitor(
    fun() ->
        ets:update_element(table, x, {2, 2})
    end),
  receive
    _ -> ok
  end.

update_element_bad() ->
  ets:new(table, [named_table]),
  ets:insert(table, {x, 1}),
  spawn_monitor(
    fun() ->
        try
          ets:update_element(table, x, {2, 2}),
          exit(wrong)
        catch
          error:badarg -> ok
        end
    end),
  receive
    _ -> ok
  end.
