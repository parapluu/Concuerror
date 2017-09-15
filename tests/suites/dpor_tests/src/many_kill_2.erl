-module(many_kill_2).

-export([test/0]).
-export([scenarios/0]).

scenarios() -> [{test, inf, dpor}].

test() ->
  P = self(),
  ets:new(table, [named_table, public]),
  Fun = fun() -> receive after infinity -> ok end end,
  {Pid, M} = spawn_monitor(Fun),
  Fun2 =
    fun(A) ->
        fun() ->
            case A of
              true -> ets:insert(table,{foo});
              false -> ok
            end,
            exit(Pid, not_normal)
        end
    end,
  spawn(Fun2(true)),
  spawn(Fun2(false)),
  receive
    {'DOWN', M, process, Pid, not_normal} ->
      true = [] =/= ets:lookup(table, foo)
  end.
