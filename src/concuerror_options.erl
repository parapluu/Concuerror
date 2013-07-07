%% -*- erlang-indent-level: 2 -*-

-module(concuerror_options).

-export([parse_cl/1, filter_options/2]).

-include("concuerror.hrl").

parse_cl(CommandLineArgs) ->
  try
    parse_cl_aux(CommandLineArgs)
  catch
    throw:opt_error -> {exit, error}
  end.

parse_cl_aux(CommandLineArgs) ->
  case getopt:parse(getopt_spec(), CommandLineArgs) of
    {ok, {Options, OtherArgs}} ->
      case proplists:get_bool(help, Options) of
        true ->
          cl_usage(),
          {exit, ok};
        false ->
          case OtherArgs of
            [ModuleS, FunctionS|MaybeArgs] ->
              Module = list_to_atom(ModuleS),
              Function = list_to_atom(FunctionS),
              Parser =
                fun(RawArg) ->
                    try
                      {ok, Tokens, _} = erl_scan:string(RawArg ++ "."),
                      {ok, Term} = erl_parse:parse_term(Tokens),
                      Term
                    catch
                      _:_ -> throw(RawArg)
                    end
                end,
              try
                Args = [Parser(A) || A <- MaybeArgs],
                FullOptions = [{target, {Module, Function, Args}}|Options],
                finalize(FullOptions)
              catch
                throw:Arg -> opt_error("Arg ~s is not an Erlang term", [Arg])
              end;
            _ -> opt_error("Module and/or Function were not specified")
          end
      end;
    {error, Error} ->
      case Error of
        {missing_option_arg, Option} ->
          opt_error("no argument given for --~s", [Option]);
        _Other ->
          opt_error(getopt:format_error([], Error))
      end
  end.

getopt_spec() ->
  [
   {'after-timeout', $a, "after", {integer, infinite},
    "Assume that 'after' clause timeouts higher or equal to the specified value"
    " will never be triggered, unless no other process can progress."},
   {bound, $b, "bound", {integer, 2}, "Preemption bound (-1 for infinite)."},
   {distributed, $d, "distributed", {boolean, false},
    "Use distributed Erlang semantics: messages are not delivered immediately"
    " after being sent."},
   {file, $f, "file", string,
    "Also load a specific file (.beam or .erl). A .erl file should not require"
    " any command line compile options."},
   {help, $h, "help", undefined, "Display this information."},
   {'light-dpor', $l, "light-dpor", {boolean, false},
    "Use lightweight (source) DPOR instead of optimal."},
   {output, $o, "output", {string, "results.txt"}, "Output file."},
   {path, $p, "path", string, "Add directory to the code path."},
   {quiet, $q, "quiet", undefined,
    "Do not write anything to standard output. Equivalent to --verbose 0."},
   {timeout, $t, "timeout", {integer, 20000},
    "How many ms to wait before assuming a process to be stuck in an infinite"
    " loop between two operations with side-effects. Setting it to -1 makes"
    " Concuerror wait indefinitely. Otherwise must be > " ++
      integer_to_list(?MINIMUM_TIMEOUT) ++ "."},
   {verbose, $v, "verbose", integer,
    io_lib:format("Verbosity level (0-~p) [default: ~p].",
                  [?MAX_VERBOSITY, ?DEFAULT_VERBOSITY])}
  ].

filter_options(Mode, {Key, _}) ->
  Modes =
    case Key of
      'after-timeout' -> [logger, process];
      bound           -> [logger, scheduler];
      distributed     -> [logger, scheduler];
      files           -> [logger];
      help            -> [helper];
      'light-dpor'    -> [logger, scheduler];
      logger          -> [scheduler];
      output          -> [logger];
      quiet           -> [helper];
      target          -> [logger, scheduler];
      timeout         -> [logger, scheduler];
      verbose         -> [logger]
    end,
  lists:member(Mode, Modes).

cl_usage() ->
  ModuleS = "Module",
  FunctionS = "Function",
  ArgsS = "[Args]",
  getopt:usage(
    getopt_spec(),
    "./concuerror",
    string:join([ModuleS, FunctionS, ArgsS], " "),
    [{ModuleS, "Module containing the initial function"},
     {FunctionS, "The initial function to be called"},
     {ArgsS, "Arguments to be passed to the initial function. If nonexistent, a"
      " function with zero arity will be called."}]).

finalize(Options) ->
  Finalized = finalize(lists:reverse(proplists:unfold(Options)), []),
  case proplists:get_value(target, Finalized, undefined) of
    {M,F,B} when is_atom(M), is_atom(F), is_list(B) -> Finalized;
    _ -> opt_error("missing target option")
  end.

finalize([], Acc) -> Acc;
finalize([{quiet, true}|Rest], Acc) ->
  NewRest = proplists:delete(verbose, proplists:delete(quiet, Rest)),
  finalize(NewRest, [{verbose, 0}|Acc]);
finalize([{verbose, N}|Rest], Acc) ->
  case proplists:is_defined(quiet, Rest) =:= true andalso N =/= 0 of
    true ->
      opt_error("--verbose defined after --quiet");
    false ->
      Sum = lists:sum([N|proplists:get_all_values(verbose, Rest)]),
      Verbosity = min(Sum, ?MAX_VERBOSITY),
      NewRest = proplists:delete(verbose, Rest),
      finalize(NewRest, [{verbose, Verbosity}|Acc])
  end;
finalize([{Key, Value}|Rest], Acc)
  when Key =:= file; Key =:= path ->
  case Key of
    file ->
      Files = [Value|proplists:get_all_values(file, Rest)],
      LoadedFiles = compile_and_load(Files),
      NewRest = proplists:delete(file, Rest),
      finalize(NewRest, [{files, LoadedFiles}|Acc]);
    path ->
      case code:add_patha(Value) of
        true -> ok;
        {error, bad_directory} ->
          opt_error("could not add ~s to code path", [Value])
      end,
      finalize(Rest, Acc)
  end;
finalize([{Key, Value}|Rest], Acc) ->
  case proplists:is_defined(Key, Rest) of
    true ->
      opt_error("multiple instances of --~s defined", [Key]);
    false ->
      case Key of
        output ->
          case file:open(Value, [write]) of
            {ok, IoDevice} ->
              finalize(Rest, [{output, IoDevice}|Acc]);
            {error, _} ->
              opt_error("could not open file ~s for writing", [Value])
          end;
        timeout ->
          case Value of
            -1 ->
              finalize(Rest, [{timeout, infinite}|Acc]);
            N when is_integer(N), N > ?MINIMUM_TIMEOUT ->
              finalize(Rest, [{timeout, N}|Acc]);
            _Else ->
              opt_error("--timeout value must be -1 (infinite) or > "
                       ++ integer_to_list(?MINIMUM_TIMEOUT))
          end;
        _ ->
          finalize(Rest, [{Key, Value}|Acc])
      end
  end.

compile_and_load(Files) ->
  %% Platform-dependent directory to store compiled .erl files
  {OsType, _} = os:type(),
  TmpDir =
    case OsType of
      unix -> "/tmp/";
      win32 -> os:getenv("TEMP")
    end,
  compile_and_load(Files, TmpDir, []).

compile_and_load([], _TmpDir, Acc) -> lists:sort(Acc);
compile_and_load([File|Rest], TmpDir, Acc) ->
  case filename:extension(File) of
    ".erl" ->
      case compile:file(File, [{outdir, TmpDir}, debug_info, report_errors]) of
        {ok, Module} ->
          Default = code:which(Module),
          case Default =:= non_existing of
            true -> ok;
            false ->
              opt_warn("file ~s shadows the default ~s", [File, Default])
          end,
          BeamFile = atom_to_list(Module),
          FullBeamFile = filename:join(TmpDir, BeamFile),
          LoadRes = code:load_abs(FullBeamFile),
          ok = concuerror_loader:load(Module),
          ok = file:delete(FullBeamFile ++ code:objfile_extension()),
          case LoadRes of
            {module, Module} ->
              compile_and_load(Rest, TmpDir, [File|Acc]);
            {error, What} ->
              opt_error("could not load ~s: ~p", [FullBeamFile, What])
          end;
        error ->
          Format = "could not compile ~s (try to add the .beam file instead)",
          opt_error(Format, [File])
      end;
    ".beam" ->
      Filename = filename:basename(File, ".beam"),
      case code:load_abs(Filename) of
        {module, _Module} ->
          compile_and_load(Rest, TmpDir, [File|Acc]);
        {error, What} ->
          opt_error("could not load ~s: ~p", [File, What])
      end;
    _Other ->
      opt_error("~s is not a .erl or .beam file", [File])
  end.

opt_error(Format) ->
  opt_error(Format, []).

opt_error(Format, Data) ->
  io:format(standard_error, "concuerror: ERROR: " ++ Format ++ "~n", Data),
  io:format(standard_error, "concuerror: Use --help for more information.\n", []),
  throw(opt_error).

opt_warn(Format, Data) ->
  io:format(standard_error, "concuerror: WARNING: " ++ Format ++ "~n", Data),
  ok.
