%% -*- erlang-indent-level: 2 -*-

-module(concuerror_options).

-export([parse_cl/1, finalize/1]).

-include("concuerror.hrl").

-define(MINIMUM_TIMEOUT, 1000).
-define(DEFAULT_VERBOSITY, ?linfo).
-define(DEFAULT_PRINT_DEPTH, 20).

-spec parse_cl([string()]) -> options().

parse_cl(CommandLineArgs) ->
  try
    parse_cl_aux(CommandLineArgs)
  catch
    throw:opt_error -> {exit, error}
  end.

parse_cl_aux(CommandLineArgs) ->
  case getopt:parse(getopt_spec(), CommandLineArgs) of
    {ok, {Options, OtherArgs}} ->
      case {proplists:get_bool(help, Options),
            proplists:get_bool(version, Options)} of
        {true,_} ->
          cl_usage(),
          {exit, completed};
        {_,true} ->
          cl_version(),
          {exit, completed};
        {false, false} ->
          case OtherArgs =:= [] of
            true -> ok;
            false ->
              opt_warn("Ignoring: ~s", [string:join(OtherArgs, " ")], Options)
          end,
          Options
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
  %% Options long name is the same as the inner representation atom for
  %% consistency.
  [{Key, Short, atom_to_list(Key), Type, Help} ||
    {Key, Short, Type, Help} <- options()].

options() ->
  [{module, $m, atom,
    "The module containing the main test function."}
  ,{test, $t, {atom, test},
    "The name of the 0-arity function that starts the test."}
  ,{output, $o, {string, "concuerror_report.txt"},
    "Output file where Concuerror shall write the results of the analysis."}
  ,{help, $h, undefined,
    "Display this information."}
  ,{version, undefined, undefined,
    "Display version information about Concuerror."}
  ,{pa, undefined, string,
    "Add directory at the front of Erlang's code path."}
  ,{pz, undefined, string,
    "Add directory at the end of Erlang's code path."}
  ,{file, $f, string,
    "Explicitly load a file (.beam or .erl). (A .erl file should not require"
    " any command line compile options.)"}
  ,{verbosity, $v, integer,
    io_lib:format("Sets the verbosity level (0-~p). [default: ~p]",
                  [?MAX_VERBOSITY, ?DEFAULT_VERBOSITY])}
  ,{quiet, $q, undefined,
    "Do not write anything to standard output. Equivalent to -v 0."}
  ,{print_depth, undefined, {integer, ?DEFAULT_PRINT_DEPTH},
    "Specifies the max depth for any terms printed in the log (behaves just as"
    " the extra argument of ~W and ~P argument of io:format/3. If you want more"
    " info about a particular piece of data consider using erlang:display/1"
    " and check the standard output section instead."}
  ,{symbolic_names, $s, {boolean, true},
    "Use symbolic names for process identifiers in the output interleavings."}
  ,{depth_bound, $d, {integer, 5000},
    "The maximum number of events allowed in an interleaving. Concuerror will"
    " stop exploration beyond this limit."}
  ,{interleaving_bound, undefined, {integer, infinity},
    "The maximum number of interleavings that will be explored. Concuerror will"
    " stop exploration beyond this limit."}
  ,{delay_bound, $b, {integer, infinity},
    "The maximum number of times a round-robin scheduler is allowed to deviate"
    " from the default scheduling order in order to reverse the order of racing"
    " events. Implies --optimal=false."}
  ,{optimal, undefined, {boolean, true},
    "Setting this to false enables a more lightweight DPOR algorithm. Use this"
    " if the rate of exploration is too slow. Don't use it if a lot of"
    " interleavings are reported as sleep-set blocked."}
  ,{show_races, undefined, {boolean, false},
    "Determines whether information about pairs of racing instructions will be"
    " included in the graph and the logs of erroneous interleavings."}
  ,{graph, undefined, string,
    "Graph file where Concuerror will store interleaving info using the DOT"
    " language."}
  ,{after_timeout, $a, {integer, infinity},
    "Assume that 'after' clause timeouts higher or equal to the specified value"
    " will never be triggered."}
  ,{instant_delivery, undefined, {boolean, false},
    "Assume that messages and signals are delivered immediately, when sent to a"
    " process on the same node."}
  ,{scheduling, undefined, {atom, round_robin},
    "How Concuerror picks the next process to run. Valid choices are 'oldest',"
    " 'newest' and 'round_robin'."}
  ,{strict_scheduling, undefined, {boolean, false},
    "Whether Concuerror should enforce the scheduling strategy strictly or lets"
    " a process run until blocked before reconsidering the scheduling policy."}
  ,{ignore_first_crash, $i, {boolean, false},
    "If not enabled, Concuerror will immediately exit if the first interleaving"
    " contains errors."}
  ,{ignore_error, undefined, atom,
    "Concuerror will not report errors of the specified kind: 'crash' (all"
    " process crashes, see also next option for more refined control),"
    " 'deadlock' (processes waiting at a receive statement), 'depth_bound'."}
  ,{treat_as_normal, undefined, atom,
    "A process that exits with reason the specified atom (or with a reason that"
    " is a tuple with the specified atom as a first element) will not be"
    " reported as exiting abnormally. Useful e.g. when analyzing supervisors"
    " ('shutdown' is probably a normal exit reason in this case)."}
  ,{timeout, undefined, {integer, ?MINIMUM_TIMEOUT},
    "How many ms to wait before assuming a process to be stuck in an infinite"
    " loop between two operations with side-effects. Setting it to -1 makes"
    " Concuerror wait indefinitely. Otherwise must be >= " ++
      integer_to_list(?MINIMUM_TIMEOUT) ++ "."}
  ,{assume_racing, undefined, {boolean, true},
    "If there is no info about whether a specific pair of built-in operations"
    " may race, assume that they do indeed race. Set this to false to detect"
    " missing dependency info."}
  ,{non_racing_system, undefined, atom,
    "Assume that any messages sent to the specified system process (specified"
    " by registered name) are not racing with each-other. Useful for reducing"
    " the number of interleavings when processes have calls to io:format/1,2 or"
    " similar."}
  ].

cl_usage() ->
  getopt:usage(getopt_spec(), "./concuerror").

cl_version() ->
  io:format(standard_error, "Concuerror v~s~n",[?VSN]),
  ok.

-spec finalize(options()) -> options().

finalize(Options) ->
  FinalOptions =
    try
      Options1 = rename_equivalent(Options),
      Options2 = add_missing_getopt_defaults(Options1),
      Options3 =
        add_missing_defaults(
          [{modules, ets:new(modules, [public])},
           {processes, ets:new(processes, [public])},
           {verbosity, ?DEFAULT_VERBOSITY}
          ], Options2),
      Options4 = finalize_aux(proplists:unfold(Options3)),
      add_missing_defaults(
        [{ignore_error, []},
         {non_racing_system, []},
         {treat_as_normal, []}
        ], Options4)
    catch
      throw:{file_defined, FileOptions} ->
        NewOptions = proplists:delete(file, Options),
        Fold = fun({K,_}, Override) -> lists:keydelete(K, 1, Override) end,
        OverridenOptions = lists:foldl(Fold, NewOptions, FileOptions),
        finalize(FileOptions ++ OverridenOptions)
    end,
  consistent(FinalOptions),
  case proplists:get_value(entry_point, FinalOptions, undefined) of
    {M,F,B} when is_atom(M), is_atom(F), is_list(B) ->
      try
        true = lists:member({F,length(B)}, M:module_info(exports)),
        FinalOptions
      catch
        _:_ ->
          InvalidEntryPoint =
            "The entry point ~p:~p/~p is not valid. Make sure you have"
            " specified the correct module ('-m') and test function ('-t')",
          opt_error(InvalidEntryPoint, [M,F,length(B)])
      end;
    _ ->
      UndefinedEntryPoint =
        "The module containing the main test function has not been specified."
        " Use '-m <module>' to provide this info.",
      opt_error(UndefinedEntryPoint)
  end.

rename_equivalent(Options) ->
  rename_equivalent(Options, []).

rename_equivalent([quiet|Rest], Acc) ->
  case proplists:is_defined(verbosity, Rest ++ Acc) of
    true -> opt_error("--verbosity specified together with --quiet");
    false ->
      rename_equivalent(Rest, [{verbosity, ?lquiet}|Acc])
  end;
rename_equivalent([Other|Rest], Acc) ->
  rename_equivalent(Rest, [Other|Acc]);
rename_equivalent([], Acc) -> lists:reverse(Acc).

finalize_aux(Options) ->
  {value, Verbosity, RestOptions} = lists:keytake(verbosity, 1, Options),
  finalize([Verbosity|RestOptions], []).

finalize([], Acc) -> Acc;
finalize([{Key, V}|Rest], Acc)
  when
    Key =:= ignore_error;
    Key =:= non_racing_system;
    Key =:= treat_as_normal ->
  Values = [V|proplists:get_all_values(Key, Rest)],
  NewRest = proplists:delete(Key, Rest),
  finalize(NewRest, [{Key, lists:usort(Values)}|Acc]);
finalize([{verbosity, N}|Rest], Acc) ->
  Sum = lists:sum([N|proplists:get_all_values(verbosity, Rest)]),
  Verbosity = min(Sum, ?MAX_VERBOSITY),
  NewRest = proplists:delete(verbosity, Rest),
  if Verbosity < ?ltiming; ?has_dev -> ok;
     true -> opt_error("To use this verbosity, run 'make clean; make dev' first")
  end,
  finalize(NewRest, [{verbosity, Verbosity}|Acc]);
finalize([{file, Value}|Rest], Acc) ->
  %% This will force rechecking defaults, so no need to recurse.
  Files = [Value|proplists:get_all_values(file, Rest)],
  compile_and_load(Files, Acc);
finalize([{Key, Value}|Rest], Acc) when Key =:= pa; Key =:=pz ->
  PathAdd =
    case Key of
      pa -> fun code:add_patha/1;
      pz -> fun code:add_pathz/1
    end,
  case PathAdd(Value) of
    true -> ok;
    {error, bad_directory} ->
      opt_error("could not add ~s to code path", [Value])
  end,
  finalize(Rest, Acc);
finalize([{Key, Value}|Rest], AccIn) ->
  Acc =
    case proplists:is_defined(Key, AccIn) of
      true ->
        Format = "multiple instances of --~s defined. Using last value: ~p.",
        opt_warn(Format, [Key, Value], AccIn ++ Rest),
        proplists:delete(Key, AccIn);
      false -> AccIn
    end,
  case Key of
    delay_bound ->
      NewRest =
        case Value =:= infinity of
          true -> Rest;
          false -> [{optimal, false}|Rest]
        end,
      finalize(NewRest, [{Key, Value}|Acc]);
    graph ->
      case file:open(Value, [write]) of
        {ok, IoDevice} -> finalize(Rest, [{Key, IoDevice}|Acc]);
        {error, _} -> file_error(Key, Value)
      end;
    module ->
      case proplists:get_value(test, Rest, 1) of
        Name when is_atom(Name) ->
          NewRest = proplists:delete(test, Rest),
          finalize(NewRest, [{entry_point, {Value, Name, []}}|Acc]);
        _ -> opt_error("The name of the test function is missing")
      end;
    output ->
      case file:open(Value, [write]) of
        {ok, IoDevice} -> finalize(Rest, [{Key, {IoDevice, Value}}|Acc]);
        {error, _} -> file_error(Key, Value)
      end;
    timeout ->
      case Value of
        -1 ->
          finalize(Rest, [{Key, infinity}|Acc]);
        N when is_integer(N), N >= ?MINIMUM_TIMEOUT ->
          finalize(Rest, [{Key, N}|Acc]);
        _Else ->
          opt_error(
            "--~s value must be -1 (infinity) or >= ~p",
            [Key, ?MINIMUM_TIMEOUT])
      end;
    test ->
      case Rest =:= [] of
        true -> finalize(Rest, Acc);
        false -> finalize(Rest ++ [{Key, Value}], Acc)
      end;
    _ ->
      finalize(Rest, [{Key, Value}|Acc])
  end.

-spec file_error(atom(), term()) -> no_return().

file_error(Key, Value) ->
  opt_error("could not open --~p file ~s for writing", [Key, Value]).

compile_and_load(Files, Options) ->
  Modules = proplists:get_value(modules, Options),
  Processes = proplists:get_value(processes, Options),
  {LoadedFiles, MoreOptions} =
    compile_and_load(Files, Modules, {[], {none, []}}, Options),
  Preserved =
    [{modules, Modules},
     {processes, Processes},
     {files, LoadedFiles}
     |MoreOptions],
  throw({file_defined, Preserved}).

compile_and_load([], _Modules, {Acc, {_, MoreOpts}}, _Options) ->
  {lists:sort(Acc), MoreOpts};
compile_and_load([File|Rest], Modules, {Acc, MoreOpts}, Options) ->
  case concuerror_loader:load_initially(File, Modules) of
    {ok, Module, Warnings} ->
      lists:foreach(fun(W) -> opt_warn(W, [], Options) end, Warnings),
      NewMoreOpts =
        case try Module:concuerror_options() catch _:_ -> [] end of
          [] -> MoreOpts;
          More when MoreOpts =:= {none, []} -> {File, More};
          _ ->
            {Other, _} = MoreOpts,
            Error =
              "Both ~s and ~s export concuerror_options/0. Please remove one of"
              " them.",
            opt_error(Error, [Other, File])
        end,
      compile_and_load(Rest, Modules, {[File|Acc], NewMoreOpts}, Options);
    {error, Error} ->
      opt_error(Error)
  end.

add_missing_defaults([], Options) -> Options;
add_missing_defaults([{Key, _} = Default|Rest], Options) ->
  case proplists:is_defined(Key, Options) of
    true -> add_missing_defaults(Rest, Options);
    false -> [Default|add_missing_defaults(Rest, Options)]
  end.

add_missing_getopt_defaults(Opts) ->
  MissingDefaults =
    [{Key, Default} ||
      {Key, _Short, {_, Default}, _Help} <- options(),
      not proplists:is_defined(Key, Opts),
      Key =/= test
    ],
  MissingDefaults ++ Opts.

consistent(Options) ->
  consistent(Options, []).

consistent([], _) -> ok;
consistent([{delay_bound, N} = Bound|Rest], Acc) when is_integer(N) ->
  check_values(
    [{scheduling, round_robin},
     {optimal, false},
     {strict_scheduling, false}],
    Rest ++ Acc, {delay_bound, "an integer"}),
  consistent(Rest, [Bound|Acc]);
consistent([A|Rest], Acc) -> consistent(Rest, [A|Acc]).

check_values([], _, _) -> ok;
check_values([{Key, Value}|Rest], Other, Reason) ->
  Set = proplists:get_value(Key, Other),
  case Set =:= Value of
    true ->
      check_values(Rest, Other, Reason);
    false ->
      {ReasonKey, ReasonValue} = Reason,
      opt_error(
        "Setting '~p' to '~p' is not allowed when '~p' is set to ~s. Remove '~p'.",
        [Key, Set, ReasonKey, ReasonValue, Key])
  end.

-spec opt_error(string()) -> no_return().

opt_error(Format) ->
  opt_error(Format, []).

opt_error(Format, Data) ->
  io:format(standard_error, "concuerror: ERROR: " ++ Format ++ "~n", Data),
  io:format(standard_error, "concuerror: Use --help for more information.\n", []),
  throw(opt_error).

opt_warn(Format, Data, Options) ->
  case proplists:get_value(verbosity, Options) =:= ?lquiet of
    true -> ok;
    false ->
      io:format(standard_error, "concuerror: WARNING: " ++ Format ++ "~n", Data)
  end.
