%% -*- erlang-indent-level: 2 -*-

-module(concuerror).

-export([run/1]).

-include("concuerror.hrl").

-spec run(options()) -> 'completed' | 'error'.

run(RawOptions) ->
  try
    [] = [M || {M, preloaded} <- code:all_loaded(), true =/= code:unstick_mod(M)],
    [] = [D || D <- code:get_path(), ok =/= code:unstick_dir(D)],
    case code:get_object_code(erlang) =:= error of
      true ->
        true =
          code:add_pathz(filename:join(code:root_dir(), "erts/preloaded/ebin"));
      false ->
        ok
    end,
    Options = concuerror_options:finalize(RawOptions),
    Modules = ?opt(modules, Options),
    Processes = ?opt(processes, Options),
    Logger = concuerror_logger:start(Options),
    SchedulerOptions = [{logger, Logger}|Options],
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
    {Module, Info} = Reason,
    case Module:explain_error(Info) of
      {_,_} = ReasonType -> ReasonType;
      Else -> {Else, error}
    end
  catch
    _:_ ->
      {io_lib:format("Reason: ~p~nTrace: ~p~n", [Reason, Stacktrace]),
       error}
  end.

cleanup(Processes) ->
  Fold =
    fun(?process_pat_pid_kind(P,Kind), true) ->
        case Kind =:= hijacked of
          true -> true;
          false -> exit(P, kill)
        end
    end,
  true = ets:foldl(Fold, true, Processes),
  ok.
