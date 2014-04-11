%% -*- erlang-indent-level: 2 -*-

-module(concuerror).

-export([run/1]).

-include("concuerror.hrl").

-spec run(options()) -> 'completed' | 'error'.

run(RawOptions) ->
  try
    Options = concuerror_options:finalize(RawOptions),
    Modules = ?opt(modules, Options),
    Processes = ?opt(processes, Options),
    ok = concuerror_loader:load(concuerror_logger, Modules, false),
    Logger = concuerror_logger:start(Options),
    SchedulerOptions = [{logger, Logger}|Options],
    {Pid, Ref} =
      spawn_monitor(fun() -> concuerror_scheduler:run(SchedulerOptions) end),
    Reason = receive {'DOWN', Ref, process, Pid, R} -> R end,
    Status =
      case Reason =:= normal of
        true -> completed;
        false ->
          ?error(Logger,
                 "~s~n~n"
                 "Get more info by running Concuerror with -v ~p~n~n",
                 [explain(Reason), ?MAX_VERBOSITY]),
          error
      end,
    cleanup(Processes),
    ?trace(Logger, "Reached the end!~n",[]),
    concuerror_logger:stop(Logger, Status),
    ets:delete(Processes),
    Status
  catch
    throw:opt_error -> error
  end.

explain(Reason) ->
  Stacktrace = erlang:get_stacktrace(),
  try
    case Reason of
      {Module, Info} -> Module:explain_error(Info);
      _ -> error(undef)
    end
  catch
    _:_ ->
      io_lib:format("Reason: ~p~nTrace: ~p~n", [Reason, Stacktrace])
  end.

cleanup(Processes) ->
  Fold = fun(?process_pat_pid(P), true) -> exit(P, kill) end,
  true = ets:foldl(Fold, true, Processes),
  ok.

