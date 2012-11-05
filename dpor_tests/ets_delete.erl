-module(ets_delete).

-compile(export_all).

ets_delete() ->
    ets:new(table, [public, named_table]),
    spawn(fun() ->
                  ets:insert(table, {key, value})
          end),
    ets:delete(table),
    receive
        deadlock -> ok
    end.
