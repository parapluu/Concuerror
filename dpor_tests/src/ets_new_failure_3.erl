-module(ets_new_failure_3).

-export([ets_new_failure_3/0]).

ets_new_failure_3() ->
    Fun =
        fun() ->
                ets:new(table, [named_table, public])
        end,
    spawn(Fun),
    spawn(Fun).
