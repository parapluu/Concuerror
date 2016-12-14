%% -*- erlang-indent-level: 2 -*-

-module(concuerror).

%% Main entry point.
-export([run/1]).

%%------------------------------------------------------------------------------

%% Internal export
-export([maybe_cover_compile/0, maybe_cover_export/1]).

%%------------------------------------------------------------------------------

-export_type([exit_status/0]).

-type exit_status() :: 'ok' | 'error' | 'fail'.

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-spec run(concuerror_options:options()) -> exit_status().

run(RawOptions) ->
  maybe_cover_compile(),
  Status =
    case concuerror_options:finalize(RawOptions) of
      {ok, Options, LogMsgs} -> start(Options, LogMsgs);
      {exit, ExitStatus} -> ExitStatus
    end,
  maybe_cover_export(RawOptions),
  Status.

%%------------------------------------------------------------------------------

start(Options, LogMsgs) ->
  error_logger:tty(false),
  Processes = ets:new(processes, [public]),
  Estimator = concuerror_estimator:start_link(Options),
  LoggerOptions = [{estimator, Estimator},{processes, Processes}|Options],
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
  concuerror_estimator:finish(Estimator),
  ets:delete(Processes),
  ExitStatus.

%%------------------------------------------------------------------------------

-spec maybe_cover_compile() -> 'ok'.

maybe_cover_compile() ->
  Cover = os:getenv("CONCUERROR_COVER"),
  if Cover =/= false ->
      case cover:is_compiled(?MODULE) of
        false ->
          EbinDir = filename:dirname(code:which(?MODULE)),
          _ = cover:compile_beam_directory(EbinDir),
          ok;
        _ -> ok
      end;
     true -> ok
  end.

%%------------------------------------------------------------------------------

-spec maybe_cover_export(term()) -> 'ok'.

maybe_cover_export(Args) ->
  Cover = os:getenv("CONCUERROR_COVER"),
  if Cover =/= false ->
      Hash = binary:decode_unsigned(erlang:md5(term_to_binary(Args))),
      Out = filename:join([Cover, io_lib:format("~.16b",[Hash])]),
      cover:export(Out),
      ok;
     true -> ok
  end.

%%------------------------------------------------------------------------------

explain(Reason) ->
  try
    {Module, Info} = Reason,
    Module:explain_error(Info)
  catch
    _:_ ->
      io_lib:format("~n  Reason: ~p", [Reason])
  end.
