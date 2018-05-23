-module(concuerror).

%% CLI entry point.
-export([main/1]).

%% Erlang entry point.
-export([run/1]).

%%------------------------------------------------------------------------------

-export_type([exit_status/0]).

-type exit_status() :: 'ok' | 'error' | 'fail'.

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

%% @doc Concuerror's entry point when invoked by the command-line with
%% a list of strings as arguments.

-spec main([string()]) -> no_return().

main(Args) ->
  _ = application:load(concuerror),
  maybe_cover_compile(),
  Status =
    case concuerror_options:parse_cl(Args) of
      {ok, Options} -> run(Options);
      {exit, ExitStatus} ->
        maybe_cover_export(Args),
        ExitStatus
    end,
  cl_exit(Status).

%%------------------------------------------------------------------------------

%% @doc Concuerror's entry point when invoked by an Erlang shell, with
%% a proplist as argument.

-spec run(concuerror_options:options()) -> exit_status().

run(RawOptions) ->
  _ = application:load(concuerror),
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
  ExitStatus = concuerror_logger:stop(Logger, SchedulerStatus),
  concuerror_estimator:stop(Estimator),
  ets:delete(Processes),
  ExitStatus.

%%------------------------------------------------------------------------------

maybe_cover_compile() ->
  Cover = os:getenv("CONCUERROR_COVER"),
  if Cover =/= false ->
      case cover:is_compiled(?MODULE) of
        false ->
          {ok, Modules} = application:get_key(concuerror, modules),
          [_|_] = cover:compile_beam(Modules),
          ok;
        _ -> ok
      end;
     true -> ok
  end.

%%------------------------------------------------------------------------------

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

cl_exit(ok) ->
  erlang:halt(0);
cl_exit(error) ->
  erlang:halt(1);
cl_exit(fail) ->
  erlang:halt(2).

%%------------------------------------------------------------------------------

explain(Reason) ->
  try
    {Module, Info} = Reason,
    Module:explain_error(Info)
  catch
    _:_ ->
      io_lib:format("~n  Reason: ~p", [Reason])
  end.
