%% -*- erlang-indent-level: 2 -*-

-module(concuerror_loader).

-export([load/1, load_initially/1, register_logger/1]).

-export([explain_error/1]).

%%%-----------------------------------------------------------------------------

-define(flag(A), (1 bsl A)).

-define(call, ?flag(1)).
-define(result, ?flag(2)).
-define(detail, ?flag(3)).

-define(ACTIVE_FLAGS, [?result]).

%% -define(DEBUG, true).
%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).
-include("concuerror.hrl").

-spec load(module()) -> module().

load(Module) ->
  Instrumented = get_instrumented_table(),
  load(Module, Instrumented).

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
      try
        load_binary(Module, Filename, Beam, Instrumented),
        ?log(Logger, ?linfo, "Instrumented ~p~n", [Module]),
        maybe_instrumenting_myself(Module, Instrumented)
      catch
        exit:{?MODULE, _} = Reason -> exit(Reason);
        _:_ -> Module
      end;
    false -> Module
  end.

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
      Module = load_binary(Module, File, Binary, Instrumented),
      {ok, Module, Warnings};
    Error -> Error
  end.

-spec register_logger(logger()) -> ok.

register_logger(Logger) ->
  Instrumented = get_instrumented_table(),
  ets:delete(Instrumented, {logger}),
  Fun = fun({M}, _) -> ?log(Logger, ?linfo, "Instrumented ~p~n", [M]) end,
  ets:foldl(Fun, ok, Instrumented),
  ets:insert(Instrumented, {{logger}, Logger}),
  io_lib = load(io_lib, Instrumented),
  ok.

%%------------------------------------------------------------------------------

get_instrumented_table() ->
  case ets:info(concuerror_instrumented) =:= undefined of
    true ->
      setup_sticky_directories(),
      ets:new(concuerror_instrumented, [named_table, public]);
    false ->
      concuerror_instrumented
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

check_shadow(File, Module) ->
  Default = code:which(Module),
  case Default =:= non_existing of
    true -> [];
    false ->
      [io_lib:format("File ~s shadows ~s (found in path)", [File, Default])]
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
  case load_binary(Module, Filename, NewBinary) of
    {module, Module} ->
      Module;
    {error, Reason} ->
      case Reason =:= on_load_failure of
        true -> ?crash({Reason, Module});
        false -> Module
      end
  end.

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

%%%-----------------------------------------------------------------------------

-ifdef(BEFORE_OTP_20).

%% As of 8th Dec 2015, the spec of code:load_binary/3 is broken and reports
%% 'on_load' as an error reason, while the correct one is 'on_load_failure'. To
%% have the 'dialyze' test pass, I am obfuscating the type of the return value.

load_binary(Module, Filename, NewBinary) ->
  Result = code:load_binary(Module, Filename, NewBinary),
  [ResultWithTypeAny] = ordsets:from_list([Result]),
  ResultWithTypeAny.

-else.

load_binary(Module, Filename, NewBinary) ->
  code:load_binary(Module, Filename, NewBinary).

-endif.

%%%-----------------------------------------------------------------------------

-spec explain_error(term()) -> string().

explain_error({on_load_failure, Module}) ->
  io_lib:format(
    "Loading an instrumented version of module '~p' failed, as the on_load/0"
    " function failed, possibly due to attempting to load a NIF library. It is"
    " not possible to use NIFs with Concuerror.~n"
    "You can read more here:"
    " https://github.com/parapluu/Concuerror/issues/77~n"
    "If no NIFs are loaded by '~p' with on_load/0, this is a bug of Concuerror",
    [Module, Module]).
