%%% @doc
%%% Concuerror's main module
%%%
%%% Contains the entry points for invoking Concuerror, either directly
%%% from the command-line or from an Erlang program.
%%%
%%% For general documentation go to the Overview page.

-module(concuerror).

-export([main/1, run/1, version/0]).

%% Internal export for documentation belonging in this module
-export([analysis_result_documentation/0]).

%% Internal functions for reloading
-export([main_internal/1, run_internal/1]).

%%------------------------------------------------------------------------------

-export_type([analysis_result/0]).

-type analysis_result() :: 'ok' | 'error' | 'fail'.
%% @type analysis_result() = 'ok' | 'error' | 'fail'.
%% Meaning of Concuerror's analysis results, as returned from {@link
%% concuerror:run/1} (the corresponding exit status
%% returned by {@link concuerror:main/1} is given in parenthesis):
%% <dl>
%%   <dt>`ok' (exit status: <em>0</em>)</dt>
%%     <dd>
%%       the analysis terminated and found no errors
%%     </dd>
%%   <dt>`error' (exit status: <em>1</em>)</dt>
%%     <dd>
%%       the analysis terminated and found errors (see the
%%       {@link concuerror_options:output_option/0. `output'} option)
%%     </dd>
%%   <dt>`fail' (exit status: <em>2</em>)</dt>
%%     <dd>
%%       the analysis failed and it might have found errors or not
%%     </dd>
%% </dl>

%%------------------------------------------------------------------------------

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

%% @doc
%% Command-line entry point.
%%
%% This function can be used to invoke Concuerror from the
%% command-line.
%%
%% It accepts a list of strings as argument.  This list is processed by
%% {@link concuerror_options:parse_cl/1} and the result is passed to
%% {@link concuerror:run/1}.
%%
%% When {@link concuerror:run/1} returns, the Erlang VM will
%% terminate, with an exit value corresponding to the {@link
%% analysis_result()}.

-spec main([string()]) -> no_return().

main(Args) ->
  _ = application:load(concuerror),
  maybe_cover_compile(),
  ?MODULE:main_internal(Args).

%% @private
-spec main_internal([string()]) -> no_return().

main_internal(Args) ->
  AnalysisResult =
    case concuerror_options:parse_cl(Args) of
      {run, Options} -> run(Options);
      {return, Result} ->
        maybe_cover_export(Args),
        Result
    end,
  ExitStatus =
    case AnalysisResult of
      ok -> 0;
      error -> 1;
      fail -> 2
    end,
  erlang:halt(ExitStatus).

%%------------------------------------------------------------------------------

%% @doc
%% Erlang entry point.
%%
%% This function can be used to invoke Concuerror from an Erlang
%% program.  This is the recommended way to invoke Concuerror when you
%% use it as part of a test suite.
%%
%% This function accepts a `proplists' list as argument.  The
%% supported properties are specified at {@link concuerror_options}.
%%
%% The meaning of the return values is explained at {@link
%% analysis_result()}.

-spec run(concuerror_options:options()) -> analysis_result().

run(Options) ->
  _ = application:load(concuerror),
  maybe_cover_compile(),
  ?MODULE:run_internal(Options).

%% @private
-spec run_internal(concuerror_options:options()) -> analysis_result().

run_internal(Options) ->
  Status =
    case concuerror_options:finalize(Options) of
      {run, FinalOptions, LogMsgs} -> start(FinalOptions, LogMsgs);
      {return, ExitStatus} -> ExitStatus
    end,
  maybe_cover_export(Options),
  Status.

%%-----------------------------------------------------------------------------

%% @doc
%% Returns a string representation of Concuerror's version.

-spec version() -> string().

version() ->
  _ = application:load(concuerror),
  {ok, Vsn} = application:get_key(concuerror, vsn),
  io_lib:format("Concuerror v~s", [Vsn]).

%%------------------------------------------------------------------------------

-type string_constant() :: [1..255, ...]. % Dialyzer underspecs is unhappy otw.

%% @private
-spec analysis_result_documentation() -> string_constant().

analysis_result_documentation() ->
  ""
    "Exit status:~n"
    " 0    ('ok') : Analysis completed. No errors were found.~n"
    " 1 ('error') : Analysis completed. Errors were found.~n"
    " 2  ('fail') : Analysis failed to complete.~n".

%%------------------------------------------------------------------------------

start(Options, LogMsgs) ->
  error_logger:tty(false),
  Processes = ets:new(processes, [public]),
  Estimator = concuerror_estimator:start_link(Options),
  LoggerOptions = [{estimator, Estimator}, {processes, Processes}|Options],
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
  ?trace(Logger, "Reached the end!~n", []),
  ExitStatus = concuerror_logger:stop(Logger, SchedulerStatus),
  concuerror_estimator:stop(Estimator),
  ets:delete(Processes),
  ExitStatus.

%%------------------------------------------------------------------------------

maybe_cover_compile() ->
  Cover = os:getenv("CONCUERROR_COVER"),
  case Cover =/= false of
    true ->
      case cover:is_compiled(?MODULE) of
        false ->
          {ok, Modules} = application:get_key(concuerror, modules),
          [_|_] = cover:compile_beam(Modules),
          ok;
        _ -> ok
      end;
    false -> ok
  end.

%%------------------------------------------------------------------------------

maybe_cover_export(Args) ->
  Cover = os:getenv("CONCUERROR_COVER"),
  case Cover =/= false of
    true ->
      Hash = binary:decode_unsigned(erlang:md5(term_to_binary(Args))),
      Out = filename:join([Cover, io_lib:format("~.16b", [Hash])]),
      cover:export(Out),
      ok;
    false -> ok
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
