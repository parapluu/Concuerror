-module(monitor_info).

-export([scenarios/0]).
-export([test1/0,test2/0]).

scenarios() ->
  [{T, inf, dpor} || T <- [test1,test2]].

test1() ->
  {P,R} = spawn_monitor(fun() -> ok end),
  Before = receive _ -> true after 0 -> false end,
  case demonitor(R, [info]) of
    true ->
      %% Successful demonitor, will never deliver the message
      receive _ -> error(never)
      after 0 -> ok
      end;
    false ->
      %% Failed demonitor, message has either:
      %% - been delivered and received before the demonitor
      %% - been delivered after the first receive but before the
      %%   demonitor so not discarded
      %% - been delivered after the first receive and after the
      %%   demonitor (discarded upon delivery, so deadlock)
      true = Before orelse receive _ -> true end
  end.

test2() ->
  {P, R} = spawn_monitor(fun() -> ok end),
  case demonitor(R, [flush, info]) of
    true ->
      %% Was delivered and flushed
      receive _ -> error(never)
      after 0 -> ok
      end;
    false ->
      %% Was not flushed, but it will be ignored upon delivery
      receive _ -> error(never)
      after 0 -> ok
      end
  end.
