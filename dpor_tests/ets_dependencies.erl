-module(ets_dependencies).

-compile(export_all).

ets_dependencies() ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  Parent ! ok
          end),
    spawn(fun() ->
                  ets:insert(table, {y, 2}),
                  ets:lookup(table, x),
                  Parent ! ok
          end),
    spawn(fun() ->
                  ets:insert(table, {z, 3}),
                  ets:lookup(table, x),
                  Parent ! ok
          end),
    receive
        ok ->
            receive
                ok ->
                    receive
                        ok ->
                            receive
                                dead -> ok
                            end
                    end
            end
    end.
