%% -*- erlang-indent-level: 2 -*-

-module(concuerror_loader).

-export([load/2, load_initially/2]).

-define(flag(A), (1 bsl A)).

-define(call, ?flag(1)).
-define(result, ?flag(2)).
-define(detail, ?flag(3)).

-define(ACTIVE_FLAGS, [?result]).

%% -define(DEBUG, true).
%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).
-include("concuerror.hrl").

-spec load(module(), modules()) -> module().

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
    false -> Module
  end.

-spec load_initially(module(), modules()) ->
                        {ok, module(), [string()]} | {error, string()}.

load_initially(File, Modules) ->
  MaybeModule =
    case filename:extension(File) of
      ".erl" ->
        case compile:file(File, [binary, debug_info, report_errors]) of
          error ->
            Format = "could not compile ~s (try to add the .beam file instead)",
            {error, io_lib:format(Format, [File])};
          Else -> Else
        end;
      ".beam" ->
        case beam_lib:chunks(File, []) of
          {ok, {M, []}} ->
            {ok, M, File};
          Else ->
            {error, beam_lib:format_error(Else)}
        end;
      _Other ->
        {error, io_lib:format("~s is not a .erl or .beam file", [File])}
    end,
  case MaybeModule of
    {ok, Module, Binary} ->
      Warnings = check_shadow(File, Module),
      Module = load_binary(Module, File, Binary, Modules),
      {ok, Module, Warnings};
    Error -> Error
  end.

check_shadow(File, Module) ->
  Default = code:which(Module),
  case Default =:= non_existing of
    true -> [];
    false ->
      [io_lib:format("file ~s shadows the default ~s", [File, Default])]
  end.

load_binary(Module, Filename, Beam, Instrumented) ->
  Core = get_core(Beam),
  InstrumentedCore =
    case Module =:= concuerror_inspect of
      true -> Core;
      false -> concuerror_instrumenter:instrument(Module, Core, Instrumented)
    end,
  {ok, _, NewBinary} =
    compile:forms(InstrumentedCore, [from_core, report_errors, binary]),
  {module, Module} = code:load_binary(Module, Filename, NewBinary),
  Module.

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
              {Tag, _} -> lists:member(Tag, [d, i, parse_transform]);
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
    false -> Module;
    true ->
      Additional = concuerror_callback,
      Additional = load(Additional, Instrumented),
      Module
  end.
