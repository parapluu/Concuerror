-module(receive_exit).

-export([test/0, test1/0, test2/0, test3/0]).

-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, true}]).

scenarios() ->
  [{T, inf, dpor} || T <- [test, test1, test2, test3]].

%%% Minimal version of a bug reported by Felix Gallo in issue #75.  The problem
%%% is that a 'receive' event was not properly detected as racing with an exit
%%% signal that lead to an abnormal exit, leaving the process that sent the
%%% signal sleeping after the reversal.

test() ->
  Fun =
    fun() ->
        receive foo -> ok end,
        receive bar -> ok end,
        receive after infinity -> ok end
    end,
  P = spawn(Fun),
  spawn(fun() -> P ! bar end),
  spawn(fun() -> P ! foo, exit(P, die) end).

test1() ->
  Fun =
    fun() ->
        receive foo -> ok end,
        receive bar -> ok end,
        receive after infinity -> ok end
    end,
  P = spawn(Fun),
  spawn(fun() -> P ! foo, exit(P, die) end),
  spawn(fun() -> P ! bar end).

test2() ->
  Fun =
    fun() ->
        receive foo -> ok end,
        receive bar -> ok end,
        receive after infinity -> ok end
    end,
  P = spawn(Fun),
  spawn(fun() -> exit(P, die) end),
  spawn(fun() -> P ! foo end),
  spawn(fun() -> P ! bar end).

test3() ->
  Fun =
    fun() ->
        receive foo -> ok end,
        receive bar -> ok end,
        receive after infinity -> ok end
    end,
  P = spawn(Fun),
  spawn(fun() -> P ! bar end),
  spawn(fun() -> P ! foo end),
  exit(P, die).
