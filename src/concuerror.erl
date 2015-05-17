%% -*- erlang-indent-level: 2 -*-

-module(concuerror).

-export([run/1]).

-include("concuerror.hrl").

-spec run(options()) -> 'completed' | 'error'.

run(RawOptions) ->
  try
    _ = [true = code:unstick_mod(M) || {M, preloaded} <- code:all_loaded()],
    [] = [D || D <- code:get_path(), ok =/= code:unstick_dir(D)],
    case code:get_object_code(erlang) =:= error of
      true ->
        true =
          code:add_pathz(filename:join(code:root_dir(), "erts/preloaded/ebin"));
      false ->
        ok
    end,
    {module, concuerror_inspect} = code:load_file(concuerror_inspect),
    Processes = ets:new(processes, [public]),
    Options = concuerror_options:finalize([{processes, Processes}|RawOptions]),
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
    concuerror_callback:cleanup_processes(Processes),
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
