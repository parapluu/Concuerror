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

-spec parse_cl([string()]) ->
                  {'ok', options()} | {'exit', concuerror:exit_status()}.

parse_cl(CommandLineArgs) ->
  try
    parse_cl_aux(CommandLineArgs)
  catch
    throw:opt_error -> {exit, fail}
  end.

parse_cl_aux([]) ->
  {ok, [help]};
parse_cl_aux(CommandLineArgs) ->
  case getopt:parse(getopt_spec(), CommandLineArgs) of
    {ok, {Options, OtherArgs}} ->
      case OtherArgs =:= [] of
        true -> ok;
        false ->
          Msg = "Unknown argument(s)/option(s): ~s",
          opt_error(Msg, [string:join(OtherArgs, " ")])
      end,
      {ok, Options};
    {error, Error} ->
      case Error of
        {missing_option_arg, help} ->
          cl_usage(basic),
          {exit, ok};
        {missing_option_arg, Option} ->
          opt_error("no argument given for '--~s'", [Option]);
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
     {Key, _Keywords, Short, Type, Help} ->
       {Key, Short, atom_to_list(Key), Type, Help};
     {Key, _Keywords, Short, Type, Help, _Long} ->
       {Key, Short, atom_to_list(Key), Type, Help}
   end || Option <- Options].

-define(OPTION_KEY, 1).
-define(OPTION_KEYWORDS, 2).
-define(OPTION_SHORT, 3).
-define(OPTION_GETOPT_DEFAULT, 4).
-define(OPTION_GETOPT_SHORT_HELP, 5).
-define(OPTION_GETOPT_LONG_HELP, 6).

-define(DEFAULT_OUTPUT, "concuerror_report.txt").

options(Keyword) ->
  [T || T <- options(), lists:member(Keyword, element(?OPTION_KEYWORDS, T))].

options() ->
  [{module, [basic, input], $m, atom,
    "Module containing the test function",
    "Concuerror begins exploration from a test function located in the module"
    " specified by this option."}
  ,{test, [basic, input], $t, {atom, test},
    "Test function",
    "This must be a 0-arity function located in the module specified by '-m'."
    " Concuerror will start the test by spawning a process that calls this"
    " function."}
  ,{output, [basic, output], $o, {string, ?DEFAULT_OUTPUT},
    "Output file",
    "This is where Concuerror writes the results of the analysis."}
  ,{quiet, [basic, console], $q, undefined,
    "Do not write anything to stderr",
    "Shorthand for '--verbosity 0'."}
  ,{verbosity, [basic, console, advanced], $v, integer,
    io_lib:format("Sets the verbosity level (0-~w). [default: ~w]",
                  [?MAX_VERBOSITY, ?DEFAULT_VERBOSITY]),
    "Verbosity decides what is shown on stderr. Messages up to info are"
    " always also shown in the output file. The available levels are the"
    " following:~n~n"
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
  ,{graph, [output, visual], undefined, string,
    "Produce a DOT graph in the specified file",
    "The DOT graph can be converted to an image with 'dot -Tsvg -o graph.svg"
    " <graph>"}
  ,{symbolic_names, [output, visual, erlang], $s, {boolean, true},
    "Use symbolic PIDs in graph/log",
    "Use symbolic names for process identifiers in the output report (and"
    " graph)."}
  ,{print_depth, [output, visual], undefined, {integer, ?DEFAULT_PRINT_DEPTH},
    "Print depth for log/graph",
    "Specifies the max depth for any terms printed in the log (behaves just as"
    " the extra argument of ~~W and ~~P argument of io:format/3). If you want"
    " more info about a particular piece of data in an interleaving, consider"
    " using erlang:display/1 and checking the 'standard output section; in the"
    " log instead."}
  ,{show_races, [output, visual, dpor], undefined, {boolean, false},
    "Show races in log/graph",
    "Determines whether information about pairs of racing instructions will be"
    " included in the logs of erroneous interleavings and the graph."}
  ,{file, [input], $f, string,
    "Load a specific file",
    "Explicitly load a file (.beam or .erl). Source (.erl) files should not"
    " require any special command line compile options. Use a .beam file if"
    " special compilation is needed (preferably compiled with +debug_info)."}
  ,{pa, [input], undefined, string,
    "Add directory to Erlang's code path (front)",
    "Works exactly like 'erl -pa'."}
  ,{pz, [input], undefined, string,
    "Add directory to Erlang's code path (rear)",
    "Works exactly like 'erl -pz'."}
  ,{depth_bound, [bound], $d, {integer, 500},
    "Maximum number of events",
    "The maximum number of events allowed in an interleaving. Concuerror will"
    " stop exploring an interleaving that has events beyond this limit."}
  ,{interleaving_bound, [bound], $i, {integer, infinity},
    "Maximum number of interleavings",
    "The maximum number of interleavings that will be explored. Concuerror will"
    " stop exploration beyond this limit."}
  ,{dpor, [por], undefined, atom,
    "DPOR techique to use. [default: optimal]",
    "Specifies which Dynamic Partial Order Reduction techique will be used. The"
    " available options are:~n"
    "-       'none': Disable DPOR. Do not use.~n"
    "-    'optimal': Using source sets and wakeup trees.~n"
    "-     'source': Using source sets only. Use this if the rate of~n"
    "                exploration is too slow. Use 'optimal' if a lot of~n"
    "                interleavings are reported as sleep-set blocked.~n"
    "- 'persistent': Using persistent sets. Do not use."}
  ,{optimal, [por], undefined, boolean,
    "Deprecated. Use '--dpor (optimal | source)' instead."}
  ,{scheduling_bound_type, [bound], $c, atom,
    "Use schedule bounding [default: none]",
    "Enables scheduling rules that prevent interleavings from being explored."
    " The available options are:~n"
    "-   'none': no bounding~n"
    "-   'bpor': how many times per interleaving the scheduler is allowed~n"
    "            to preempt a process.~n"
    "            * Not compatible with Optimal DPOR.~n"
    "-  'delay': how many times per interleaving the scheduler is allowed~n"
    "            to skip a chosen process in order to schedule others.~n"}
  ,{scheduling_bound, [bound], $b, integer,
    "Scheduling bound value",
    "The maximum number of times the rule specified in '--scheduling_bound_type'"
    " can be violated."}
  ,{disable_sleep_sets, [por, advanced], undefined, {boolean, false},
    "Disables use of sleep sets",
    "This option is only available with '--dpor none'."}
  ,{after_timeout, [erlang], $a, {integer, infinity},
    "Ignore timeouts greater than this value",
    "Assume that 'after' clause timeouts higher or equal to the specified value"
    " (integer) will never be triggered."}
  ,{instant_delivery, [erlang], undefined, {boolean, true},
    "Messages and signals arrive instantly",
    "Assume that messages and signals are delivered immediately, when sent to a"
    " process on the same node."}
  ,{scheduling, [advanced], undefined, {atom, round_robin},
    "Scheduling order",
    "How Concuerror picks the next process to run. The available options are"
    " 'oldest', 'newest' and 'round_robin'."}
  ,{strict_scheduling, [advanced], undefined, {boolean, false},
    "Forces preemptions",
    "Whether Concuerror should enforce the scheduling strategy strictly or let"
    " a process run until blocked before reconsidering the scheduling policy."}
  ,{keep_going, [basic, bug], $k, {boolean, false},
    "Keep running after an error is found",
    "Concuerror stops by default when the first error is found. Enable this"
    " flag to keep looking for more errors. Preferably, modify the test, or"
    " use the '--ignore_error' / '--treat_as_normal' options."}
  ,{ignore_error, [bug], undefined, atom,
    "Ignore 'crash', 'deadlock' or 'depth_bound' errors",
    "Concuerror will not report errors of the specified kind:~n"
    "'crash' (any process crash - check '-h treat_as_normal' for more refined"
    " control)~n"
    "'deadlock' (processes waiting at a receive statement)~n"
    "'depth_bound' (the depth bound was reached - check '-h depth_bound')."}
  ,{treat_as_normal, [bug], undefined, atom,
    "Exit reasons considered 'normal'",
    "A process that exits with the specified atom as reason (or with a reason"
    " that is a tuple with the specified atom as a first element) will not be"
    " reported as exiting abnormally. Useful e.g. when analyzing supervisors"
    " ('shutdown' is usually a normal exit reason in this case)."}
  ,{assertions_only, [bug], undefined, {boolean, false},
    "Only crashes due to failed ?asserts are reported.",
    "Only processes that exit with a reason of form '{{assert*, _}, _}' are"
    " considered crashes. Such exit reasons are generated e.g. by the"
    " stdlib/include/assert.hrl header file."}
  ,{timeout, [erlang, advanced], undefined, {integer, ?MINIMUM_TIMEOUT},
    "How long to wait for an event (>= " ++
      integer_to_list(?MINIMUM_TIMEOUT) ++ "ms)",
    "How many ms to wait before assuming that a process is stuck in an infinite"
    " loop between two operations with side-effects. Setting this to -1 will"
    " make Concuerror wait indefinitely. Otherwise must be >= " ++
      integer_to_list(?MINIMUM_TIMEOUT) ++ "."}
  ,{assume_racing, [por, advanced], undefined, {boolean, true},
    "Unknown operations as considered racing",
    "Concuerror has a list of operation pairs that are known to be non-racing."
    " If there is no info about a specific pair of built-in operations"
    " may race, assume that they do indeed race. If this is set to false,"
    " Concuerror will exit instead. Useful for detecting"
    " missing dependency info."}
  ,{non_racing_system, [erlang], undefined, atom,
    "No races due to 'system' messages",
    "Assume that any messages sent to the specified (by registered name) system"
    " process are not racing with each-other. Useful for reducing the number of"
    " interleavings when processes have calls to e.g. io:format/1,2 or similar."}
  ,{help, [basic], $h, atom,
    "Display help (use also as '-h <option/keyword>')",
    "You already know how to use this option! :-)"}
  ,{version, [basic], undefined, undefined,
    "Display version information"}
   ].

cl_usage(all) ->
  Sort = fun(A, B) -> element(?OPTION_KEY, A) =< element(?OPTION_KEY, B) end,
  getopt:usage(getopt_spec(lists:sort(Sort, options())), "./concuerror"),
  print_suffix(all);
cl_usage(Name) ->
  Optname =
    case lists:keyfind(Name, ?OPTION_KEY, options()) of
      false ->
        Str = atom_to_list(Name),
        Name =/= undefined andalso
          length(Str) =:= 1 andalso
          lists:keyfind(hd(Str), ?OPTION_SHORT, options());
      R -> R
    end,
  case Optname of
    false ->
      MaybeKeyword = options(Name),
      case MaybeKeyword =/= [] of
        true ->
          getopt:usage(getopt_spec(MaybeKeyword), "./concuerror"),
          KeywordWarningFormat =
            "NOTE: Only showing options with the keyword '~p'.~n"
            "      Use '--help all' to see all available options.~n",
          to_stderr(KeywordWarningFormat, [Name]),
          print_suffix(Name);
        false ->
          case atom_to_list(Name) of
            "-" ++ Rest -> cl_usage(list_to_atom(Rest));
            _ ->
              Msg = "Invalid option name/keyword (as argument to --help): '~w'",
              opt_error(Msg, [Name])
          end
      end;
    Tuple ->
      getopt:usage(getopt_spec([Tuple]), "./concuerror"),
      try
        element(?OPTION_GETOPT_LONG_HELP, Tuple)
      of
        String -> to_stderr(String ++ "~n", [])
      catch
        _:_ -> to_stderr("No additional help available.~n", [])
      end,
      {Keywords, Related} = get_keywords_and_related(Tuple),
      to_stderr("Option Keywords: ~p~nRelated Options: ~p~n", [Keywords, Related]),
      to_stderr("For general help use '-h' without an argument.~n", [])
  end.

cl_version() ->
  to_stderr("Concuerror v~s (~w)",[?VSN, ?GIT_SHA]).

print_suffix(Keyword) ->
  to_stderr("More info & keywords about a specific option: -h <option>.~n", []),
  case Keyword =:= basic orelse Keyword =:= all of
    true -> print_exit_status_info();
    false -> ok
  end,
  print_bugs_message().

print_exit_status_info() ->
  Message =
    "Exit status:~n"
    " 0    ('ok') : Test went well. No errors were found.~n"
    " 1 ('error') : Test went bad. Errors were found.~n"
    " 2  ('fail') : Incorrect use. Bad options used, unsupported code, etc.~n",
  to_stderr(Message, []).

print_bugs_message() ->
  Message = "Report bugs (and other FAQ): http://parapluu.github.io/Concuerror/faq~n",
  to_stderr(Message, []).

get_keywords_and_related(Tuple) ->
  Keywords = element(?OPTION_KEYWORDS, Tuple),
  Filter =
    fun(OtherKeywords) ->
        Any = fun(E) -> lists:member(E, Keywords) end,
        lists:any(Any, OtherKeywords)
    end,
  Related =
    [element(?OPTION_KEY, T) ||
      T <- options(), Filter(element(?OPTION_KEYWORDS, T))],
  {lists:sort(Keywords), lists:sort(Related)}.

%%%-----------------------------------------------------------------------------

-spec finalize(options()) ->
                  {'ok', options(), [iolist()]} |
                  {'exit', concuerror:exit_status()}.

finalize(Options) ->
  try
    case check_help_and_version(Options) of
      exit -> {exit, ok};
      ok ->
        FinalOptions = finalize_2(Options),
        Warnings = get_all_warnings(),
        {ok, FinalOptions, Warnings}
    end
  catch
    throw:opt_error -> {exit, fail}
  end.

finalize_2(Options) ->
  FinalOptions =
    try
      Passes =
        [ fun proplists:unfold/1
        , fun rename_equivalent/1
        , fun(O) ->
              add_missing_defaults(
                [{verbosity, ?DEFAULT_VERBOSITY},
                 {output, ?DEFAULT_OUTPUT},
                 {test, test}
                ], O)
          end
        , fun finalize_aux/1
        , fun add_missing_getopt_defaults/1
        , fun(O) ->
              add_missing_defaults(
                [{dpor, optimal},
                 {ignore_error, []},
                 {non_racing_system, []},
                 {scheduling_bound_type, none},
                 {treat_as_normal, []}
                ], O)
          end
        ],
      run_passes(Passes, Options)
    catch
      throw:{file_defined, FileOptions} ->
        NewOptions = proplists:delete(file, Options),
        Fold = fun({K,_}, Override) -> lists:keydelete(K, 1, Override) end,
        OverridenOptions = lists:foldl(Fold, NewOptions, FileOptions),
        finalize_2(FileOptions ++ OverridenOptions)
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
            "The entry point ~w:~w/~w is not valid. Make sure you have"
            " specified the correct module ('-m') and test function ('-t').",
          opt_error(InvalidEntryPoint, [M,F,length(B)])
      end;
    _ ->
      UndefinedEntryPoint =
        "The module containing the main test function has not been specified."
        " Add '-m <module>' or use '-h module' for more info.",
      opt_error(UndefinedEntryPoint)
  end.

run_passes([], Options) ->
  Options;
run_passes([Pass|Passes], Options) ->
  run_passes(Passes, Pass(Options)).

check_help_and_version(Options) ->
  case {proplists:get_bool(version, Options),
        proplists:is_defined(help, Options)} of
    {true, _} ->
      cl_version(),
      exit;
    {false, true} ->
      Value = proplists:get_value(help, Options),
      case Value =:= true of
        true -> cl_usage(basic);
        false -> cl_usage(Value)
      end,
      exit;
    _ ->
      ok
  end.

%%%-----------------------------------------------------------------------------

rename_equivalent(Options) ->
  rename_equivalent(Options, []).

rename_equivalent([{quiet, true}|Rest], Acc) ->
  case proplists:is_defined(verbosity, Rest ++ Acc) of
    true -> opt_error("'--verbosity' specified together with '--quiet'");
    false ->
      rename_equivalent(Rest, [{verbosity, ?lquiet}|Acc])
  end;
rename_equivalent([Other|Rest], Acc) ->
  rename_equivalent(Rest, [Other|Acc]);
rename_equivalent([], Acc) -> lists:reverse(Acc).

finalize_aux(Options) ->
  {value, Verbosity, RestOptions} = lists:keytake(verbosity, 1, Options),
  case proplists:get_all_values(file, Options) of
    [] -> finalize([Verbosity|RestOptions], []);
    Files -> compile_and_load(Files, [Verbosity])
  end.

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
  if Verbosity < ?ldebug; ?has_dev -> ok;
     true ->
      Error = "To use verbosity > ~w, build Concuerror with 'make dev'.",
      opt_error(Error, [?ldebug - 1])
  end,
  finalize(NewRest, [{verbosity, Verbosity}|Acc]);
finalize([{Key, Value}|Rest], Acc)
  when
    Key =:= pa;
    Key =:=pz
    ->
  PathAdd =
    case Key of
      pa -> fun code:add_patha/1;
      pz -> fun code:add_pathz/1
    end,
  case PathAdd(Value) of
    true -> ok;
    {error, bad_directory} ->
      opt_error("could not add ~s to code path.", [Value])
  end,
  finalize(Rest, Acc);
finalize([{Key, Value} = Option|Rest], Acc)
  when
    Key =:= after_timeout;
    Key =:= depth_bound;
    Key =:= print_depth
    ->
  check_validity(Key, Value, {fun(V) -> V > 0 end, "a positive integer"}),
  finalize(Rest, [Option|Acc]);
finalize([{Key, Value} = Option|Rest], AccIn) ->
  Acc =
    case proplists:is_defined(Key, AccIn) of
      true ->
        Format = "multiple instances of '--~s' defined. Using last value: ~w.",
        opt_warn(Format, [Key, Value]),
        proplists:delete(Key, AccIn);
      false -> AccIn
    end,
  case Key of
    dpor ->
      check_validity(Key, Value, [none, optimal, persistent, source]),
      finalize(Rest, [Option|Acc]);
    disable_sleep_sets ->
      NewRest =
        case Value =:= false orelse proplists:is_defined(dpor, Acc ++ Rest) of
          true -> Rest;
          false -> [{dpor, none}|Rest]
        end,
      finalize(NewRest, [Option|Acc]);
    graph ->
      case file:open(Value, [write]) of
        {ok, IoDevice} -> finalize(Rest, [{Key, IoDevice}|Acc]);
        {error, _} -> file_error(Key, Value)
      end;
    module ->
      case proplists:is_defined(module, Rest) of
        true -> opt_error("Multiple instances of '--module'");
        false -> ok
      end,
      case proplists:get_value(test, Rest, 1) of
        Name when is_atom(Name) ->
          NewRest = proplists:delete(test, Rest),
          finalize(NewRest, [{entry_point, {Value, Name, []}}|Acc]);
        _ -> opt_error("The name of the test function is missing.")
      end;
    optimal ->
      "0.1" ++ [_|_] = ?VSN,
      Msg =
        "The '--optimal' option is deprecated."
        " Use '--dpor (optimal | source)' instead.",
      opt_error(Msg);
    output ->
      case file:open(Value, [write]) of
        {ok, IoDevice} -> finalize(Rest, [{Key, {IoDevice, Value}}|Acc]);
        {error, _} -> file_error(Key, Value)
      end;
    scheduling ->
      check_validity(Key, Value, [newest, oldest, round_robin]),
      finalize(Rest, [Option|Acc]);
    scheduling_bound ->
      ValidityCheck = {fun(V) -> V >= 0 end, "a non-negative integer"},
      check_validity(Key, Value, ValidityCheck),
      NewRest =
        case proplists:is_defined(scheduling_bound_type, Acc ++ Rest) of
          true -> Rest;
          false -> assume(scheduling_bound_type, delay, Rest)
        end,
      finalize(NewRest, [Option|Acc]);
    scheduling_bound_type ->
      check_validity(Key, Value, [bpor, delay, none]),
      NewRest =
        case Value =:= none orelse proplists:is_defined(scheduling_bound, Acc ++ Rest) of
          true -> Rest;
          false -> assume(scheduling_bound, 1, Rest)
        end,
      NewRest1 =
        case Value =/= bpor orelse proplists:is_defined(dpor, Acc ++ Rest) of
          true -> NewRest;
          false -> assume(dpor, source, NewRest)
        end,
      finalize(NewRest1, [Option|Acc]);
    MaybeInfinity
      when
        MaybeInfinity =:= interleaving_bound;
        MaybeInfinity =:= timeout
        ->
      Limit =
        case MaybeInfinity of
          interleaving_bound -> 0;
          timeout -> ?MINIMUM_TIMEOUT
        end,
      case Value of
        infinity ->
          finalize(Rest, [Option|Acc]);
        -1 ->
          finalize(Rest, [{MaybeInfinity, infinity}|Acc]);
        N when is_integer(N), N >= Limit ->
          finalize(Rest, [Option|Acc]);
        _Else ->
          Error = "The value of '--~s' must be -1 (infinity) or >= ~w.",
          opt_error(Error, [Key, Limit])
      end;
    test ->
      case Rest =:= [] of
        true -> finalize(Rest, Acc);
        false -> finalize(Rest ++ [Option], Acc)
      end;
    _ ->
      finalize(Rest, [Option|Acc])
  end.

-spec file_error(atom(), term()) -> no_return().

file_error(Key, Value) ->
  opt_error("could not open '--~w' file ~s for writing.", [Key, Value]).

compile_and_load(Files, Options) ->
  {LoadedFiles, MoreOptions} =
    compile_and_load(Files, {[], {none, []}}, Options),
  Preserved = [{files, LoadedFiles}|MoreOptions],
  throw({file_defined, proplists:unfold(Preserved)}).

compile_and_load([], {Acc, {_, MoreOpts}}, _Options) ->
  {lists:sort(Acc), MoreOpts};
compile_and_load([File|Rest], {Acc, {Already, MoreOpts}}, Options) ->
  case concuerror_loader:load_initially(File) of
    {ok, Module, Warnings} ->
      lists:foreach(fun(W) -> opt_warn(W, []) end, Warnings),
      MissingModule =
        case
          Rest =:= [] andalso
          Acc =:= [] andalso
          not proplists:is_defined(module, Options)
        of
          true -> [{module, Module}];
          false -> []
        end,
      NewMoreOpts =
        case try Module:concuerror_options() catch _:_ -> [] end of
          [] -> {Already, MissingModule ++ MoreOpts};
          More when Already =:= none -> {File, MissingModule ++ More};
          _ ->
            Error =
              "Both ~s and ~s export concuerror_options/0. Please remove one of"
              " them.",
            opt_error(Error, [Already, File])
        end,
      compile_and_load(Rest, {[File|Acc], NewMoreOpts}, Options);
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
    [{element(?OPTION_KEY, Opt), element(?OPTION_GETOPT_DEFAULT, Opt)}
     || Opt <- options()],
  NoTestIfEntryPoint =
    case proplists:is_defined(entry_point, Opts) of
      true -> fun(X) -> X =/= test end;
      false -> fun(_) -> true end
    end,
  MissingDefaults =
    [{Key, Default} ||
      {Key, {_, Default}} <- Defaults,
      not proplists:is_defined(Key, Opts),
      NoTestIfEntryPoint(Key)
    ],
  MissingDefaults ++ Opts.

check_validity(Key, Value, Valid) when is_list(Valid) ->
  case lists:member(Value, Valid) of
    true -> ok;
    false ->
      opt_error("The value of '--~s' must be one of ~w.", [Key, Valid])
  end;
check_validity(Key, Value, {Valid, Explain}) when is_function(Valid) ->
  case Valid(Value) of
    true -> ok;
    false ->
      opt_error("The value of '--~s' must be ~s.", [Key, Explain])
  end.

consistent(Options) ->
  consistent(Options, []).

consistent([], _) -> ok;
consistent([{assertions_only, true} = Option|Rest], Acc) ->
  check_values(
    [{ignore_error, fun(X) -> not lists:member(crash, X) end}],
    Rest ++ Acc, Option),
  consistent(Rest, [Option|Acc]);
consistent([{disable_sleep_sets, true} = Option|Rest], Acc) ->
  check_values(
    [{dpor, fun(X) -> X =:= none end}],
    Rest ++ Acc, Option),
  consistent(Rest, [Option|Acc]);
consistent([{scheduling_bound, _} = Option|Rest], Acc) ->
  VeryFun = fun(X) -> lists:member(X, [bpor, delay]) end,
  check_values(
    [{scheduling_bound_type, VeryFun}],
    Rest ++ Acc,
    {scheduling_bound, "an integer"}),
  consistent(Rest, [Option|Acc]);
consistent([{scheduling_bound_type, Type} = Option|Rest], Acc)
  when Type =/= none ->
  DPORVeryFun =
    case Type of
      bpor ->
        fun(X) -> lists:member(X, [source, persistent]) end;
      _ ->
        fun(_) -> true end
    end,
  check_values([{dpor, DPORVeryFun}], Rest ++ Acc, Option),
  consistent(Rest, [Option|Acc]);
consistent([A|Rest], Acc) -> consistent(Rest, [A|Acc]).

check_values([], _, _) -> ok;
check_values([{Key, Validate}|Rest], Other, Reason) ->
  All = proplists:lookup_all(Key, Other),
  case lists:all(fun({_, X}) -> Validate(X) end, All) of
    true ->
      check_values(Rest, Other, Reason);
    false ->
      {ReasonKey, ReasonValue} = Reason,
      [Set|_] = [S || {_, S} <- All, not Validate(S)],
      opt_error(
        "Setting '~w' to '~w' is not allowed when '~w' is set to ~s.",
        [Key, Set, ReasonKey, ReasonValue])
  end.

%%%-----------------------------------------------------------------------------

-spec opt_error(string()) -> no_return().

opt_error(Format) ->
  opt_error(Format, []).

opt_error(Format, Data) ->
  to_stderr("Error: " ++ Format, Data),
  to_stderr("  Use --help for more information.", []),
  throw(opt_error).

opt_warn(Format, Data) ->
  Warnings =
    case get(warnings) of
      undefined -> [];
      W -> W
    end,
  put(warnings, [io_lib:format(Format ++ "~n", Data)|Warnings]),
  ok.

assume(Opt, Value, Options) ->
  Msg = "Missing value for --~p. Assuming '--~p ~p'.",
  opt_warn(Msg, [Opt, Opt, Value]),
  [{Opt, Value}|Options].

get_all_warnings() ->
  case erase(warnings) of
    undefined -> [];
    Warnings -> lists:reverse(Warnings)
  end.

to_stderr(Format, Data) ->
  io:format(standard_error, Format ++ "~n", Data).
