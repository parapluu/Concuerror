%% -*- erlang-indent-level: 2 -*-

-module(concuerror_loader).

-export([load/2, load_binary/4]).

-define(flag(A), (1 bsl A)).

-define(call, ?flag(1)).
-define(result, ?flag(2)).
-define(detail, ?flag(3)).

-define(ACTIVE_FLAGS, [?result]).

%% -define(DEBUG, true).
%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).
-include("concuerror.hrl").

-spec load(module(), ets:tid()) -> 'ok'.

load(Module, Instrumented) ->
  case ets:lookup(Instrumented, Module) =:= [] of
    true ->
      ?debug_flag(?call, {load, Module}),
      Logger = ets:lookup_element(Instrumented, {logger}, 2),
      {Beam, Filename} =
        case code:which(Module) of
          preloaded ->
            {Module, BeamBinary, F} = code:get_object_code(Module),
            {BeamBinary, F};
          F ->
            {F, F}
        end,
      catch load_binary(Module, Filename, Beam, Instrumented),
      ?log(Logger, ?linfo, "Instrumented ~p~n", [Module]),
      maybe_instrumenting_myself(Module, Instrumented);
    false -> ok
  end.

-spec load_binary(module(), string(), beam_lib:beam(), ets:tid()) -> 'ok'.

load_binary(Module, Filename, Beam, Instrumented) ->
  ets:insert(Instrumented, {Module}),
  Core = get_core(Beam),
  InstrumentedCore =
    case Module =:= concuerror_inspect of
      true -> Core;
      false ->
        true = ets:insert(Instrumented, {{current}, Module}),
        I = concuerror_instrumenter:instrument(Core, Instrumented),
        true = ets:delete(Instrumented, {current}),
        I
    end,
  {ok, _, NewBinary} =
    compile:forms(InstrumentedCore, [from_core, report_errors, binary]),
  {module, Module} = code:load_binary(Module, Filename, NewBinary),
  ok.

get_core(Beam) ->
  {ok, {Module, [{abstract_code, ChunkInfo}]}} =
    beam_lib:chunks(Beam, [abstract_code]),
  case ChunkInfo of
    {_, Chunk} ->
      {ok, Module, Core} = compile:forms(Chunk, [binary, to_core0]),
      Core;
    no_abstract_code ->
      ?debug_flag(?detail, {adding_debug_info, Module}),
      {ok, {Module, [{compile_info, CompileInfo}]}} =
        beam_lib:chunks(Beam, [compile_info]),
      {source, File} = proplists:lookup(source, CompileInfo),
      {options, CompileOptions} = proplists:lookup(options, CompileInfo),
      Filter =
        fun(Option) ->
            case Option of
              {Tag, _} -> lists:member(Tag, [d, i]);
              _ -> false
            end
        end,
      CleanOptions = lists:filter(Filter, CompileOptions),
      Options = [debug_info, report_errors, binary, to_core0|CleanOptions],
      {ok, Module, Core} = compile:file(File, Options),
      Core
  end.

maybe_instrumenting_myself(Module, Instrumented) ->
  case Module =:= concuerror_inspect of
    false -> ok;
    true ->
      Additional = concuerror_callback,
      load(Additional, Instrumented)
  end.
