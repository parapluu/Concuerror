-module(conditional_readers_2).

-export([conditional_readers_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

conditional_readers_2() ->
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
                        [{x, X}] = ets:lookup(table, x),
                        case X of
                            1 -> ets:insert(table, {y, 1});
                            _ -> ok
                        end;
                    _ -> ok
                end
        end,
    spawn(Fun),
    spawn(Fun),
    receive
    after
        infinity -> ok
    end.
