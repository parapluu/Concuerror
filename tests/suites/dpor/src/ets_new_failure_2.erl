-module(ets_new_failure_2).

-export([ets_new_failure_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_new_failure_2() ->
    Parent = self(),
    Fun =
        fun() ->
                ets:new(table, [named_table, public]),
                Parent ! ok,
                receive
                    wait -> Parent ! ok
                end
        end,
    Pid1 = spawn(Fun),
    Pid2 = spawn(Fun),
    receive
        ok ->
            receive
                ok -> ok
            end
    end,
    Pid1 ! ok,
    Pid2 ! ok,
    receive
        ok ->
            receive
                ok -> ok
            end
    end.
