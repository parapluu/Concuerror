-module(conditional_readers).

-export([conditional_readers/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

conditional_readers() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  ets:insert(table, {x, 1})
          end),
    Fun =
        fun() ->
                [{y, Y}] = ets:lookup(table, y),
                case Y of
                    0 ->
                        ets:lookup(table, x),
                        ets:insert(table, {y, 1});
                    _ -> ok
                end
        end,
    spawn(Fun),
    spawn(Fun),
    receive
    after
        infinity -> ok
    end.
