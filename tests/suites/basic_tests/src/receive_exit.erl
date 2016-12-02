-module(receive_exit).

-export([test/0]).

-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, true}]).

scenarios() ->
  [{test, inf, dpor}].

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
