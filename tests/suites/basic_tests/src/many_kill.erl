-module(many_kill).

-export([test/0]).
-export([scenarios/0]).

scenarios() -> [{test, inf, dpor}].

test() ->
  Fun =
    fun() ->
        receive after infinity -> ok end
    end,
  Pid = spawn(Fun),
  spawn(fun() -> exit(Pid, not_normal) end),
  spawn(fun() -> exit(Pid, also_not_normal) end),
  spawn(fun() -> exit(Pid, not_normal) end).
