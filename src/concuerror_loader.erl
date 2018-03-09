%% -*- erlang-indent-level: 2 -*-

-module(concuerror_loader).

-export([initialize/1, load/1, load_initially/1, is_instrumenting/0]).

%%------------------------------------------------------------------------------

-export_type([instrumented/0]).

-type instrumented() :: 'concuerror_instrumented'.

%%------------------------------------------------------------------------------

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-spec initialize([atom()]) -> 'ok' | {'error', string()}.

initialize(Excluded) ->
  Instrumented = get_instrumented_table(),
  case ets:info(Instrumented, name) =:= undefined of
    true ->
      setup_sticky_directories(),
      Instrumented = ets:new(Instrumented, [named_table, public]),
      ok;
    false ->
      ets:match_delete(Instrumented, {'_', concuerror_excluded}),
      ok
  end,
  Entries = [{X, concuerror_excluded} || X <- Excluded],
  try
    true = ets:insert_new(Instrumented, Entries),
    ok
  catch
    _:_ ->
      {error, "Excluded modules have already been instrumented. Restart the shell."}
  end.

setup_sticky_directories() ->
  {module, concuerror_inspect} = code:ensure_loaded(concuerror_inspect),
  _ = [true = code:unstick_mod(M) || {M, preloaded} <- code:all_loaded()],
  [] = [D || D <- code:get_path(), ok =/= code:unstick_dir(D)],
  case code:get_object_code(erlang) =:= error of
    true ->
      true =
        code:add_pathz(filename:join(code:root_dir(), "erts/preloaded/ebin"));
    false ->
      ok
  end.

%%------------------------------------------------------------------------------

-spec load(module()) -> {'ok', iodata()} | 'already_done' | 'fail'.

load(Module) ->
  Instrumented = get_instrumented_table(),
  load(Module, Instrumented).

load(Module, Instrumented) ->
  case ets:lookup(Instrumented, Module) =:= [] of
    true ->
      set_is_instrumenting({true, Module}),
      {Beam, Filename} =
        case code:which(Module) of
          preloaded ->
            {Module, BeamBinary, F} = code:get_object_code(Module),
            {BeamBinary, F};
          F ->
            {F, F}
        end,
      try
        {ok, Warnings} = load_binary(Module, Filename, Beam, Instrumented),
        set_is_instrumenting(false),
        {ok, Warnings}
      catch
        _:_ -> fail
      end;
    false -> already_done
  end.

%%------------------------------------------------------------------------------

-spec load_initially(module()) ->
                        {ok, module(), [string()]} | {error, string()}.

load_initially(Module) ->
  Instrumented = get_instrumented_table(),
  load_initially(Module, Instrumented).

load_initially(File, Instrumented) ->
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
      {ok, MoreWarnings} = load_binary(Module, File, Binary, Instrumented),
      {ok, Module, Warnings ++ MoreWarnings};
    Error -> Error
  end.

%%------------------------------------------------------------------------------

-spec is_instrumenting() -> {'true', module()} | 'false'.

is_instrumenting() ->
  Instrumented = get_instrumented_table(),
  [{_, V}] = ets:lookup(Instrumented, {is_instrumenting}),
  V.

-spec set_is_instrumenting( {'true', module()} | 'false') -> 'ok'.

set_is_instrumenting(Value)->
  Instrumented = get_instrumented_table(),
  ets:insert(Instrumented, {{is_instrumenting}, Value}),
  ok.

%%------------------------------------------------------------------------------

get_instrumented_table() ->
  concuerror_instrumented.

check_shadow(File, Module) ->
  Default = code:which(Module),
  case Default =:= non_existing of
    true -> [];
    false ->
      [io_lib:format("File ~s shadows ~s (found in path)", [File, Default])]
  end.

load_binary(Module, Filename, Beam, Instrumented) ->
  Core = get_core(Beam),
  {InstrumentedCore, Warnings} =
    case ets:lookup(Instrumented, Module) =:= [] of
      true ->
        ets:insert(Instrumented, {Module, concuerror_instrumented}),
        concuerror_instrumenter:instrument(Module, Core, Instrumented);
      false ->
        {Core, []}
    end,
  {ok, _, NewBinary} =
    compile:forms(InstrumentedCore, [from_core, report_errors, binary]),
  {module, Module} = code:load_binary(Module, Filename, NewBinary),
  {ok, Warnings}.

get_core(Beam) ->
  {ok, {Module, [{abstract_code, ChunkInfo}]}} =
    beam_lib:chunks(Beam, [abstract_code]),
  case ChunkInfo of
    {_, Chunk} ->
      {ok, Module, Core} = compile:forms(Chunk, [binary, to_core0]),
      Core;
    no_abstract_code ->
      {ok, {Module, [{compile_info, CompileInfo}]}} =
        beam_lib:chunks(Beam, [compile_info]),
      {source, File} = proplists:lookup(source, CompileInfo),
      {options, CompileOptions} = proplists:lookup(options, CompileInfo),
      Filter =
        fun(Option) ->
            lists:member(element(1, Option), [d, i, parse_transform])
        end,
      CleanOptions = lists:filter(Filter, CompileOptions),
      Options = [debug_info, report_errors, binary, to_core0|CleanOptions],
      {ok, Module, Core} = compile:file(File, Options),
      Core
  end.
