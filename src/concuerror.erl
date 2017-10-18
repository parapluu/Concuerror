%% -*- erlang-indent-level: 2 -*-

-module(concuerror).

-export([run/1]).

-export_type([exit_status/0]).

-type exit_status() :: 'ok' | 'error' | 'fail'.

-include("concuerror.hrl").

-spec run(concuerror_options:options()) -> exit_status().

run(RawOptions) ->
  case concuerror_options:finalize(RawOptions) of
    {ok, Options, LogMsgs} -> start(Options, LogMsgs);
    {exit, ExitStatus} -> ExitStatus
  end.

start(Options, LogMsgs) ->
  error_logger:tty(false),
  Processes = ets:new(processes, [public]),
  LoggerOptions = [{processes, Processes}|Options],
  Logger = concuerror_logger:start(LoggerOptions),
  _ = [?log(Logger, Level, Format, Args) || {Level, Format, Args} <- LogMsgs],
  SchedulerOptions = [{logger, Logger}|LoggerOptions],
  {Pid, Ref} =
    spawn_monitor(concuerror_scheduler, run, [SchedulerOptions]),
  Reason = receive {'DOWN', Ref, process, Pid, R} -> R end,
  SchedulerStatus =
    case Reason =:= normal of
      true -> normal;
      false ->
        ?error(Logger, "~s~n", [explain(Reason)]),
        failed
    end,
  ?trace(Logger, "Reached the end!~n",[]),
  ExitStatus = concuerror_logger:finish(Logger, SchedulerStatus),
  ets:delete(Processes),
  ExitStatus.

explain(Reason) ->
  try
    {Module, Info} = Reason,
    Module:explain_error(Info)
  catch
    _:_ ->
      io_lib:format("~n  Reason: ~p~n", [Reason])
  end.
