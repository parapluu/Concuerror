%% -*- erlang-indent-level: 2 -*-

-module(concuerror_options).

-export([parse_cl/1, finalize/1]).

-export_type([options/0]).

%%%-----------------------------------------------------------------------------

-include("concuerror.hrl").

-type options() :: proplists:proplist().

%%%-----------------------------------------------------------------------------

-define(MINIMUM_TIMEOUT, 1000).
-define(DEFAULT_VERBOSITY, ?linfo).
-define(DEFAULT_PRINT_DEPTH, 20).

%%%-----------------------------------------------------------------------------

-spec parse_cl([string()]) -> options() | {'exit', concuerror:status()}.

parse_cl(CommandLineArgs) ->
  try
    parse_cl_aux(CommandLineArgs)
  catch
    throw:opt_error -> {exit, error}
  end.

parse_cl_aux(CommandLineArgs) ->
  case getopt:parse(getopt_spec(), CommandLineArgs) of
    {ok, {Options, OtherArgs}} ->
      case {proplists:get_bool(version, Options),
            proplists:is_defined(help, Options)} of
        {true, _} ->
          cl_version(),
          {exit, completed};
        {false, true} ->
          cl_usage(proplists:get_value(help, Options)),
          {exit, completed};
        _ ->
          case OtherArgs =:= [] of
            true -> ok;
            false ->
              opt_error("Unknown options: ~s", [string:join(OtherArgs, " ")])
          end,
          Options
      end;
    {error, Error} ->
      case Error of
        {missing_option_arg, help} ->
          cl_usage(all),
          {exit, completed};
        {missing_option_arg, Option} ->
          opt_error("no argument given for --~s", [Option]);
        _Other ->
          opt_error(getopt:format_error([], Error))
      end
  end.

%%%-----------------------------------------------------------------------------

getopt_spec() ->
  getopt_spec(options()).

getopt_spec(Options) ->
  %% Option's long name is the same as the inner representation atom for
  %% consistency.
  [case Option of
     {Key, Short, Type, Help} ->
       {Key, Short, atom_to_list(Key), Type, Help};
     {Key, Short, Type, Help, _Long} ->
       {Key, Short, atom_to_list(Key), Type, Help}
   end || Option <- Options].

options() ->
  [{module, $m, atom,
    "Module containing the test function",
    "Concuerror begins exploration from a test function located in the module"
    " specified by this option."}
  ,{test, $t, {atom, test},
    "Test function",
    "This must be a 0-arity function located in the module specified by '-m'."
    " Concuerror will start the test by spawning a process that calls this function."}
  ,{help, $h, atom,
    "Display help",
    "You already know how to use this option :-)"}
  ,{version, undefined, undefined,
    "Display version information"}
  ,{verbosity, $v, integer,
    io_lib:format("Sets the verbosity level (0-~p). [default: ~p]",
                  [?MAX_VERBOSITY, ?DEFAULT_VERBOSITY]),
    "Verbosity decides what is shown on stderr. Messages up to info are~n"
    "always also shown in the output file. The available levels are the~n"
    "following:~n~n"
    "0 <quiet> Nothing is printed (equivalent to -q)~n"
    "1 <error> Critical, resulting in early termination~n"
    "2 <warn>  Non-critical, notifying about weak support for a feature or~n"
    "           the use of an option that alters the output~n"
    "3 <tip>   Notifying of a suggested refactoring or option to make~n"
    "           testing more efficient~n"
    "4 <info>  Normal operation messages, can be ignored~n"
    "5 <time>  Timing messages~n"
    "6 <debug> Used only during debugging~n"
    "7 <trace> Everything else"
   }
  ,{quiet, $q, undefined,
    "Do not write anything to stderr",
    "Equivalent to -v 0."}
  ,{output, $o, {string, "concuerror_report.txt"},
    "Output file",
    "This is where Concuerror writes the results of the analysis."}
  ,{graph, undefined, string,
    "Produce a DOT graph in the specified file",
    "The graph can be drawn with 'dot -Tsvg -o graph.svg <graph>"}
  ,{symbolic_names, $s, {boolean, true},
    "Symbolic PIDs in graph/log",
    "Use symbolic names for process identifiers in the output report."}
  ,{print_depth, undefined, {integer, ?DEFAULT_PRINT_DEPTH},
    "Print depth for log/graph",
    "Specifies the max depth for any terms printed in the log (behaves just as"
    " the extra argument of ~W and ~P argument of io:format/3. If you want more"
    " info about a particular piece of data consider using erlang:display/1"
    " and check the standard output section instead."}
  ,{show_races, undefined, {boolean, false},
    "Mark races in log/graph",
    "Determines whether information about pairs of racing instructions will be"
    " included in the graph and the logs of erroneous interleavings."}
  ,{pa, undefined, string,
    "Add directory to Erlang's code path (front)",
    "Works exactly like 'erl -pa'."}
  ,{pz, undefined, string,
    "Add directory to Erlang's code path (rear)",
    "Works exactly like 'erl -pz'."}
  ,{file, $f, string,
    "Load a specific file",
    "Explicitly load a file (.beam or .erl). Source (.erl) files should not"
    " require any special command line compile options. Use a .beam file if"
    " special compilation is needed."}
  ,{depth_bound, $d, {integer, 5000},
    "Maximum number of events",
    "The maximum number of events allowed in an interleaving. Concuerror will"
    " stop exploration beyond this limit."}
  ,{interleaving_bound, undefined, {integer, infinity},
    "Maximum number of interleavings",
    "The maximum number of interleavings that will be explored. Concuerror will"
    " stop exploration beyond this limit."}
  ,{optimal, undefined, boolean,
    "Whether Optimal DPOR is used [default: true]",
    "Setting this to false enables a more lightweight DPOR algorithm. Use this"
    " if the rate of exploration is too slow. Don't use it if a lot of"
    " interleavings are reported as sleep-set blocked."}
  ,{scheduling_bound_type, $c, {atom, none},
    "Enable 'delay' or 'preemption' bounding",
    "Enables scheduling rules that prevent particular interleavings from being"
    " explored. The available options are:~n"
    "'delay' - limits the number of times a round-robin scheduler is allowed to"
    "deviate from the default scheduling order in order to reverse the order of"
    " racing events.~n"
    "'preemption' - limits the number of times the scheduler is allowed to"
    " preempt a process."}
  ,{scheduling_bound, $b, {integer, infinity},
    "Scheduling bound value",
    "The maximum number of times the rule specified in --scheduling_bound_type"
    " can be violated."}
  ,{after_timeout, $a, {integer, infinity},
    "Ignore timeouts greater than this value",
    "Assume that 'after' clause timeouts higher or equal to the specified value"
    " (integer) will never be triggered."}
  ,{instant_delivery, undefined, {boolean, false},
    "Messages and signals arrive instantly",
    "Assume that messages and signals are delivered immediately, when sent to a"
    " process on the same node."}
  ,{scheduling, undefined, {atom, round_robin},
    "Scheduling order",
    "How Concuerror picks the next process to run. Valid choices are 'oldest',"
    " 'newest' and 'round_robin'."}
  ,{strict_scheduling, undefined, {boolean, false},
    "Forces preemptions",
    "Whether Concuerror should enforce the scheduling strategy strictly or let"
    " a process run until blocked before reconsidering the scheduling policy."}
  ,{keep_going, $k, {boolean, false},
    "Continue running after an error is found",
    "Concuerror stops by default when the first error is found. Enable this"
    " flag to keep looking for more errors. Preferably, modify the test, or"
    " use the --ignore_error / --treat_as_normal options."}
  ,{ignore_error, undefined, atom,
    "Ignore 'crash', 'deadlock' or 'depth_bound' errors",
    "Concuerror will not report errors of the specified kind:~n"
    "'crash' (any process crash - check '-h treat_as_normal' for more refined"
    " control)~n"
    "'deadlock' (processes waiting at a receive statement)~n"
    "'depth_bound' (the depth bound was reached - check '-h depth_bound')."}
  ,{treat_as_normal, undefined, atom,
    "Exit reasons considered 'normal'",
    "A process that exits with the specified atom as reason (or with a reason"
    " that is a tuple with the specified atom as a first element) will not be"
    " reported as exiting abnormally. Useful e.g. when analyzing supervisors"
    " ('shutdown' is usually a normal exit reason in this case)."}
  ,{timeout, undefined, {integer, ?MINIMUM_TIMEOUT},
    "How long to wait for an event (>= " ++
      integer_to_list(?MINIMUM_TIMEOUT) ++ "ms)",
    "How many ms to wait before assuming that a process is stuck in an infinite"
    " loop between two operations with side-effects. Setting this to -1 will"
    " make Concuerror wait indefinitely. Otherwise must be >= " ++
      integer_to_list(?MINIMUM_TIMEOUT) ++ "."}
  ,{assume_racing, undefined, {boolean, true},
    "Unknown operations as considered racing",
    "Concuerror has a list of operation pairs that are known to be non-racing."
    " If there is no info about a specific pair of built-in operations"
    " may race, assume that they do indeed race. If this is set to false,"
    " Concuerror will exit instead. Useful for detecting"
    " missing dependency info."}
  ,{non_racing_system, undefined, atom,
    "No races due to 'system' messages",
    "Assume that any messages sent to the specified (by registered name) system"
    " process are not racing with each-other. Useful for reducing the number of"
    " interleavings when processes have calls to e.g. io:format/1,2 or similar."}
   ].

cl_usage(all) ->
  getopt:usage(getopt_spec(), "./concuerror"),
  to_stderr("More info about a specific option: -h <option>.~n", []);
cl_usage(Name) ->
  Optname =
    case lists:keyfind(Name, 1, options()) of
      false ->
        Str = atom_to_list(Name),
        Name =/= undefined andalso
          length(Str) =:= 1 andalso
          lists:keyfind(hd(Str), 2, options());
      R -> R
    end,
  case Optname of
    false ->
      opt_error("Invalid option name: ~p", [Name]);
    Tuple ->
      getopt:usage(getopt_spec([Tuple]), "./concuerror"),
      try
        element(5, Tuple)
      of
        String -> to_stderr(String ++ "~n", [])
      catch
        _:_ -> to_stderr("No additional help available.~n", [])
      end
  end.

cl_version() ->
  to_stderr("Concuerror v~s",[?VSN]).

%%%-----------------------------------------------------------------------------

-spec finalize(options()) -> options().

finalize(Options) ->
  FinalOptions =
    try
      Options1 = rename_equivalent(Options),
      Options2 = add_missing_getopt_defaults(Options1),
      Options3 =
        add_missing_defaults(
          [{modules, ets:new(modules, [public])},
           {verbosity, ?DEFAULT_VERBOSITY}
          ], Options2),
      Options4 = finalize_aux(proplists:unfold(Options3)),
      add_missing_defaults(
        [{ignore_error, []},
         {non_racing_system, []},
         {optimal, true},
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
        " Use '-m <module>' or '-h module' for more info.",
      opt_error(UndefinedEntryPoint)
  end.

%%%-----------------------------------------------------------------------------

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
     true -> opt_error("To use this verbosity, run 'make dev' first")
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
    graph ->
      case file:open(Value, [write]) of
        {ok, IoDevice} -> finalize(Rest, [{Key, IoDevice}|Acc]);
        {error, _} -> file_error(Key, Value)
      end;
    module ->
      case proplists:is_defined(module, Rest) of
        true -> opt_error("Multiple instances of --module.");
        false -> ok
      end,
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
    scheduling_bound_type ->
      NewRest =
        case Value =:= none of
          true -> Rest;
          false -> [{optimal, false}|Rest]
        end,
      finalize(NewRest, [{Key, Value}|Acc]);
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
  Defaults =
    [case Opt of
       {Key, _Short, Default, _Help} -> {Key, Default};
       {Key, _Short, Default, _Help, _MoreHelp} -> {Key, Default}
     end || Opt <- options()],
  MissingDefaults =
    [{Key, Default} ||
      {Key, {_, Default}} <- Defaults,
      not proplists:is_defined(Key, Opts),
      Key =/= test
    ],
  MissingDefaults ++ Opts.

consistent(Options) ->
  consistent(Options, []).

consistent([], _) -> ok;
consistent([{scheduling_bound, N} = Bound|Rest], Acc) when is_integer(N) ->
  check_values(
    [{scheduling_bound_type, fun(X) -> lists:member(X,[delay, preemption]) end},
     {optimal,               fun(X) -> not X end},
     {strict_scheduling,     fun(X) -> not X end}],
    Rest ++ Acc, {scheduling_bound, "an integer"}),
  consistent(Rest, [Bound|Acc]);
consistent([{scheduling_bound_type, T} = BoundType|Rest], Acc) ->
  case T =:= none of
    true -> consistent(Rest, [BoundType|Acc]);
    false ->
      case is_integer(proplists:get_value(scheduling_bound, Rest ++ Acc)) of
        false ->
          Warn =
            "No bound value set for ~p bound. Use --scheduling_bound to specify"
            " an integer value as a bound, or remove the bound type"
            " specification.",
          opt_error(Warn, [T]);
        true ->
          case T =:= 'delay' of
            true ->
              check_values(
                [{scheduling, fun(X) -> X =:= round_robin end}],
                Rest ++ Acc, {scheduling_bound, T}),
              consistent(Rest, [BoundType|Acc]);
            false ->
              consistent(Rest, [BoundType|Acc])
          end
      end
  end;
consistent([A|Rest], Acc) -> consistent(Rest, [A|Acc]).

check_values([], _, _) -> ok;
check_values([{Key, Validate}|Rest], Other, Reason) ->
  Set = proplists:get_value(Key, Other),
  case Validate(Set) of
    true ->
      check_values(Rest, Other, Reason);
    false ->
      {ReasonKey, ReasonValue} = Reason,
      opt_error(
        "Setting '~p' to '~p' is not allowed when '~p' is set to ~s.",
        [Key, Set, ReasonKey, ReasonValue])
  end.

%%%-----------------------------------------------------------------------------

-spec opt_error(string()) -> no_return().

opt_error(Format) ->
  opt_error(Format, []).

opt_error(Format, Data) ->
  to_stderr("concuerror: ERROR: " ++ Format, Data),
  to_stderr("concuerror: Use --help for more information.", []),
  throw(opt_error).

opt_warn(Format, Data, Options) ->
  case proplists:get_value(verbosity, Options) =:= ?lquiet of
    true -> ok;
    false ->
      to_stderr("concuerror: WARNING: " ++ Format, Data)
  end.

to_stderr(Format, Data) ->
  io:format(standard_error, Format ++ "~n", Data).
