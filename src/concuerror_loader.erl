%% -*- erlang-indent-level: 2 -*-

-module(concuerror_loader).

-export([load/1, is_loaded/1, load_if_needed/1, binary_load/2]).

-define(flag(A), (1 bsl A)).

-define(call, ?flag(1)).
-define(result, ?flag(2)).
-define(detail, ?flag(3)).

-define(ACTIVE_FLAGS, [?result]).

%% -define(DEBUG, true).
%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).
-include("concuerror.hrl").

-spec load_if_needed(Module :: module()) -> 'ok' | {'error', Reason :: term()}.

load_if_needed(Module) ->
  case is_loaded(Module) =:= instrumented of
    true -> ok;
    false -> load(Module)
  end.

-spec load(Module :: module()) -> 'ok' | {'error', Reason :: term()}.

load(Module) ->
  ?debug_flag(?call, {load, Module}),
  case do_load(Module) of
    ok ->
      ?debug_flag(?result, {load_success, Module}),
      maybe_instrumenting_myself(Module);
    Error ->
      ?debug_flag(?result, {load_fail, Module, Error}),
      {error, Error}
  end.

-spec is_loaded(module()) -> 'false' | 'not_instrumented' | 'instrumented'.

is_loaded(Module) ->
  ?debug_flag(?call, {is_loaded, Module}),
  case code:is_loaded(Module) of
    {file, "Concuerror"} -> instrumented;
    {file, _} -> not_instrumented;
    _ -> false
  end.

do_load(Module) ->
  BeamRet =
    case code:which(Module) of
      preloaded ->
        case code:get_object_code(Module) of
          {Module, BeamBinary, _Filename} -> {ok, BeamBinary};
          _ -> {error, preloaded}
        end;
      Filename ->
        case file:read_file_info(Filename) of
          {ok, _} -> {ok, Filename};
          {error, _} -> error
        end
    end,
  binary_load(Module, BeamRet).

-spec binary_load(module(), {ok, beam_lib:beam()} | error) -> ok.

binary_load(Module, BeamRet) ->
  case BeamRet of
    error -> ok;
    {ok, Beam} ->
      {ok, {Module, [{abstract_code, ChunkInfo}]}} =
        beam_lib:chunks(Beam, [abstract_code]),
      GetAbstractCode =
        case ChunkInfo of
          {_, Chunk} ->
            {ok, Module, Core} = compile:forms(Chunk, [binary, to_core0]),
            {ok, Core};
          no_abstract_code ->
            ?debug_flag(?detail, {adding_debug_info, Module}),
            {ok, {Module, [{compile_info, CompileInfo}]}} =
              beam_lib:chunks(Beam, [compile_info]),
            case proplists:lookup(source, CompileInfo) of
              none -> {module_info, no_source};
              {source, File} ->
                case proplists:lookup(options, CompileInfo) of
                  none -> {module_info, no_compile_options};
                  {options, CompileOptions} ->
                    Filter =
                      fun(Option) ->
                          case Option of
                            {Tag, _} -> lists:member(Tag, [d, i]);
                            _ -> false
                          end
                      end,
                    CleanOptions = lists:filter(Filter, CompileOptions),
                    Options = [debug_info, report_errors, binary, to_core0|CleanOptions],
                    case compile:file(File, Options) of
                      {ok, Module, Core} -> {ok, Core};
                      {error, DebugErrors, []} -> {debug_compile, DebugErrors}
                    end
                end
            end
        end,
      case GetAbstractCode of
        {ok, CoreCode} ->
          InstrumentedCode =
            case Module =:= concuerror_inspect of
              true -> CoreCode;
              false -> concuerror_instrumenter:instrument(CoreCode)
            end,
          ?debug_flag(?detail, {compiling_instrumented, Module}),
          case compile:forms(InstrumentedCode, [from_core, report_errors, binary]) of
            {ok, _, NewBinary} ->
              ?debug_flag(?detail, {loading, Module}),
              case code:load_binary(Module, "Concuerror", NewBinary) of
                {module, Module} -> ok;
                {error, Error} -> {final_load, Error}
              end;
            {error, Errors, []} -> {compile, Errors}
          end;
        Error -> Error
      end
  end.

maybe_instrumenting_myself(Module) ->
  case Module =:= concuerror_inspect of
    false -> ok;
    true ->
      Additional = concuerror_callback,
      ?debug_flag(?call, {load, Additional}),
      case do_load(Additional) of
        ok ->
          ?debug_flag(?result, {load_success, Additional}),
          ok;
        Error ->
          ?debug_flag(?result, {load_fail, Additional, Error}),
          {error, Error}
      end
  end.
