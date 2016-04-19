%% -*- erlang-indent-level: 2 -*-

-module(concuerror).

-export([run/1]).

-export_type([status/0]).

-type status() :: 'completed' | 'error' | 'warning'.

-include("concuerror.hrl").

-spec run(concuerror_options:options()) -> status().

run(RawOptions) ->
  try
    concuerror_options:finalize(RawOptions)
  of
    Options -> start(Options)
  catch
    throw:opt_error -> error;
    throw:opt_exit -> completed
  end.

start(Options) ->
  error_logger:tty(false),
  Processes = ets:new(processes, [public]),
  LoggerOptions = [{processes, Processes}|Options],
  Logger = concuerror_logger:start(LoggerOptions),
  SchedulerOptions = [{logger, Logger}|LoggerOptions],
  {Pid, Ref} =
    spawn_monitor(fun() -> concuerror_scheduler:run(SchedulerOptions) end),
  Reason = receive {'DOWN', Ref, process, Pid, R} -> R end,
  Status =
    case Reason =:= normal of
      true -> completed;
      false ->
        {Explain, Type} = explain(Reason),
        ?error(Logger, "~s~n~n", [Explain]),
        Type
    end,
  concuerror_callback:cleanup_processes(Processes),
  ?trace(Logger, "Reached the end!~n",[]),
  concuerror_logger:stop(Logger, Status),
  ets:delete(Processes),
  Status.

explain(Reason) ->
  Stacktrace = erlang:get_stacktrace(),
  try
    {Module, Info} = Reason,
    case Module:explain_error(Info) of
      {_, _} = WithStatus -> WithStatus;
      ReasonStr -> {ReasonStr, error}
    end
  catch
    _:_ ->
      Str =
        io_lib:format("~n  Reason: ~p~nTrace:~n  ~p~n", [Reason, Stacktrace]),
      {Str, error}
  end.
