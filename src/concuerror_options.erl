%%% @doc
%%% Concuerror's options module
%%%
%%% Contains the handling of all of Concuerror's options.
%%%
%%% For general documentation go to the Overview page.
%%%
%%% == Table of Contents ==
%%%
%%% <ul>
%%% <li>{@section Help}</li>
%%% <li>{@section Options}</li>
%%% <li>{@section Standard Error Printout}</li>
%%% <li>{@section Report File}</li>
%%% </ul>
%%%
%%% == Help ==
%%%
%%% You can access documentation about options using the {@link
%%% help_option/0. `help'} option.  You can get more help with {@link
%%% help_option/0. `concuerror --help help'}.  In the future even more
%%% help might be added.
%%%
%%% == Options ==
%%% <ol>
%%% <li>All options have a long name.</li>
%%% <li>Some options also have a short name.</li>
%%% <li>Arguments: TODO</li>
%%% <li>Options marked with an asterisk <em>*</em> are considered
%%% experimental and may be brittle and disappear in future versions.</li>
%%% </ol>
%%%
%%% === Module attributes ===
%%%
%%%  `concuerror --help attributes'
%%%
%%% === Keywords ===
%%%
%%% Each option is associated with one or more
%%% <em>keywords</em>. These can be used with {@link help_option/0. `help'}
%%% to find related options.
%%%
%%% === Multiple arguments ===
%%%
%%% TODO
%%%
%%% == Standard Error Printout ==
%%%
%%% By default, Concuerror prints diagnostic messages in the standard
%%% error stream.  Such messages are also printed at the bottom of the
%%% {@section Report File} after the analysis is completed.  You can
%%% find explanation of the classification of these messages in the
%%% {@link verbosity_option/0. `verbosity'} option.
%%%
%%% By default, Concuerror also prints progress information in the
%%% standard error stream.  You can find what is the meaning of each field
%%% by running `concuerror --help progress'.
%%%
%%% The printout can be reduced or disabled (see {@link
%%% verbosity_option/0. `verbosity'} option).  Diagnostic messages are
%%% always printed in the {@section Report File}.
%%%
%%% == Report File ==
%%%
%%% By default, Concuerror prints analysis findings in a report file.
%%%
%%% This file contains:
%%%
%%% <ol>
%%%   <li>A header line containing the version used and starting time.</li>
%%%   <li>A list of all the options used in the particular run.</li>
%%%   <li>Zero or more {@section Error Reports} about erroneous
%%%   interleavings.</li>
%%%   <li>Diagnostic messages (see {@section Standard Error Printout}).</li>
%%%   <li>Summary about the analysis, including
%%%     <ul>
%%%       <li>completion time,</li>
%%%       <li>{@link concuerror:analysis_result(). analysis result}</li>
%%%       <li>total number of interleavings explored</li>
%%%       <li>total number of interleavings with errors</li>
%%%    </ul>
%%%   </li>
%%% </ol>
%%%
%%% === Error Reports ===
%%%
%%% An error report corresponds to an interleaving that lead to errors and
%%% contains at least the following sections:
%%%
%%% <ul>
%%% <li>Description of all errors encountered.</li>
%%% <li>Linear trace of all events in the interleaving. This contains only
%%% the operations that read/write shared information.</li>
%%% </ul>
%%%
%%% If the program produce any output, this is also included.
%%%
%%% By default, Concuerror reports the following errors:
%%% <ul>
%%% <li>A process exited abnormally.</li>
%%% <li>One or more processes are 'stuck' at a receive statement.</li>
%%% <li>The trace exceeded a (configurable but finite) number of events.</li>
%%% <li>Abnormal errors.</li>
%%% </ul>
%%%
%%% If the {@link show_races_option/0. `show_races'} option is used,
%%% the pairs of racing events that justify the exploration of new
%%% interleavings are also shown.  These are shown for all
%%% interleavings, not only the ones with errors.

-module(concuerror_options).

-export(
   [ after_timeout_option/0
   , assertions_only_option/0
   , assume_racing_option/0
   , depth_bound_option/0
   , disable_sleep_sets_option/0
   , dpor_option/0
   , exclude_module_option/0
   , file_option/0
   , first_process_errors_only_option/0
   , graph_option/0
   , help_option/0
   , ignore_error_option/0
   , instant_delivery_option/0
   , interleaving_bound_option/0
   , keep_going_option/0
   , module_option/0
   , no_output_option/0
   , non_racing_system_option/0
   , observers_option/0
   , optimal_option/0
   , output_option/0
   , pa_option/0
   , print_depth_option/0
   , pz_option/0
   , quiet_option/0
   , scheduling_bound_option/0
   , scheduling_bound_type_option/0
   , scheduling_option/0
   , show_races_option/0
   , strict_scheduling_option/0
   , symbolic_names_option/0
   , test_option/0
   , timeout_option/0
   , treat_as_normal_option/0
   , use_receive_patterns_option/0
   , verbosity_option/0
   , version_option/0
   ]).

-export([parse_cl/1, finalize/1]).

-export([generate_option_docfiles/1]).

-export_type([options/0, option_spec/0]).

-ifndef(DOC).
-export_type(
   [ bound/0
   , dpor/0
   , scheduling/0
   , scheduling_bound_type/0
   ]).
-endif.

%%%-----------------------------------------------------------------------------

-include("concuerror.hrl").

%%%-----------------------------------------------------------------------------

-type options() :: proplists:proplist().

-ifndef(DOC).
-type bound() :: 'infinity' | non_neg_integer().
-type dpor() :: 'none' | 'optimal' | 'persistent' | 'source'.
-type scheduling() :: 'oldest' | 'newest' | 'round_robin'.
-type scheduling_bound_type() :: 'bpor' | 'delay' | 'none' | 'ubpor'.
-endif.

%%%-----------------------------------------------------------------------------

-define(MINIMUM_TIMEOUT, 500).
-define(DEFAULT_VERBOSITY, ?linfo).
-define(DEFAULT_PRINT_DEPTH, 20).
-define(DEFAULT_OUTPUT, "concuerror_report.txt").

%%%-----------------------------------------------------------------------------

-define(ATTRIBUTE_OPTIONS, concuerror_options).
-define(ATTRIBUTE_FORCED_OPTIONS, concuerror_options_forced).
-define(ATTRIBUTE_TIP_THRESHOLD, 8).

%%%-----------------------------------------------------------------------------

-type long_name() :: atom().

-type keywords() ::
        [ 'advanced' |
          'basic' |
          'bound'|
          'console' |
          'erlang' |
          'errors' |
          'experimental' |
          'input' |
          'output' |
          'por' |
          'visual'
        ].

-type short_name() :: char() | undefined.
-type arg_spec() :: getopt:arg_spec().
-type short_help() :: string().
-type long_help() :: string() | 'nolong'.

-opaque option_spec() ::
        { long_name()
        , keywords()
        , short_name()
        , arg_spec()
        , short_help()
        , long_help()
        }.

-define(OPTION_KEY, 1).
-define(OPTION_KEYWORDS, 2).
-define(OPTION_SHORT, 3).
-define(OPTION_GETOPT_TYPE_DEFAULT, 4).
-define(OPTION_GETOPT_SHORT_HELP, 5).
-define(OPTION_GETOPT_LONG_HELP, 6).

options() ->
  [ module_option()
  , test_option()
  , output_option()
  , no_output_option()
  , verbosity_option()
  , quiet_option()
  , graph_option()
  , symbolic_names_option()
  , print_depth_option()
  , show_races_option()
  , file_option()
  , pa_option()
  , pz_option()
  , exclude_module_option()
  , depth_bound_option()
  , interleaving_bound_option()
  , dpor_option()
  , optimal_option()
  , scheduling_bound_type_option()
  , scheduling_bound_option()
  , disable_sleep_sets_option()
  , after_timeout_option()
  , instant_delivery_option()
  , use_receive_patterns_option()
  , observers_option()
  , scheduling_option()
  , strict_scheduling_option()
  , keep_going_option()
  , ignore_error_option()
  , treat_as_normal_option()
  , assertions_only_option()
  , first_process_errors_only_option()
  , timeout_option()
  , assume_racing_option()
  , non_racing_system_option()
  , help_option()
  , version_option()
  ].

%%%-----------------------------------------------------------------------------

%% @private
-spec generate_option_docfiles(filename:filename()) -> ok.

generate_option_docfiles(Dir) ->
  lists:foreach(fun(O) -> generate_option_docfile(O, Dir) end, options()).

-spec generate_option_docfile(option_spec(), filename:filename()) -> ok.

generate_option_docfile(Option, Dir) ->
  OptionName = element(?OPTION_KEY, Option),
  OptionShortHelp = element(?OPTION_GETOPT_SHORT_HELP, Option),
  OptionShort = element(?OPTION_SHORT, Option),
  OptionKeywords = element(?OPTION_KEYWORDS, Option),
  OptionLongHelp = element(?OPTION_GETOPT_LONG_HELP, Option),
  Arg = "...",
  Filename = filename:join([Dir, atom_to_list(OptionName) ++ "_option.edoc"]),
  {ok, File} = file:open(Filename, [write]),
  print_docfile_preamble(File),
  io:format(File, "@doc ~s~n~n", [OptionShortHelp]),
  io:format(File, "<ul>", []),
  item(
    File,
    "Long: <strong>`--~p ~s'</strong> or <strong>`@{~p, ~s@}'</strong>",
    [OptionName, Arg, OptionName, Arg]),
  case OptionShort =:= undefined of
    true -> ok;
    false -> item(File, "Short: `-~c'", [OptionShort])
  end,
  AllowedInModuleAttributes =
    not lists:member(OptionName, not_allowed_in_module_attributes()),
  item(
    File, "Allowed in {@section module attributes}: <em>~p</em>",
    [to_yes_or_no(AllowedInModuleAttributes)]),
  case OptionKeywords =:= [] of
    true -> ok;
    false ->
      StringKeywords =
        string:join([atom_to_list(K) || K <- OptionKeywords], ", "),
      item(File, "{@section Keywords}: ~s", [StringKeywords])
  end,
  io:format(File, "</ul>", []),
  case OptionLongHelp =:= nolong of
    true -> ok;
    false -> io:format(File, OptionLongHelp ++ "~n", [])
  end,
  file:close(File).

print_docfile_preamble(File) ->
  Format =
    "%% ATTENTION!~n"
    "%% This file is generated by ~w:generate_option_docfile/2~n"
    "~n",
  io:format(File, Format, [?MODULE]).

item(File, Format, Args) ->
  io:format(File, "<li>" ++ Format ++ "</li>", Args).

to_yes_or_no(true) -> yes;
to_yes_or_no(false) -> no.
%%%-----------------------------------------------------------------------------

%% @docfile "doc/module_option.edoc"
-spec module_option() -> option_spec().

module_option() ->
  { module
  , [basic, input]
  , $m
  , atom
  , "Module containing the test function"
  , "Concuerror begins exploration from a test function located in the module"
    " specified by this option.~n"
    "~n"
    "There is no need to specify modules used in the test if they are in"
    " Erlang's code path. Otherwise use `--file', `--pa' or `--pz'."
  }.

%% @docfile "doc/test_option.edoc"
-spec test_option() -> option_spec().

test_option() ->
  { test
  , [basic, input]
  , $t
  , {atom, test}
  , "Test function"
  , "This must be a 0-arity function located in the module specified by"
    " `--module'. Concuerror will start the test by spawning a process that"
    " calls this function."
  }.

%% @docfile "doc/output_option.edoc"
-spec output_option() -> option_spec().

output_option() ->
  { output
  , [basic, output]
  , $o
  , {string, ?DEFAULT_OUTPUT}
  , "Output report filename"
  , "This is where Concuerror writes the results of the analysis."
  }.

%% @docfile "doc/no_output_option.edoc"
-spec no_output_option() -> option_spec().

no_output_option() ->
  { no_output
  , [basic, output]
  , undefined
  , boolean
  , "Disable output file"
  , "Concuerror will not produce an output report."
  }.

%% @docfile "doc/verbosity_option.edoc"
-spec verbosity_option() -> option_spec().

verbosity_option() ->
  { verbosity
  , [advanced, basic, console]
  , $v
  , {integer, ?DEFAULT_VERBOSITY}
  , io_lib:format("Verbosity level (0-~w)", [?MAX_LOG_LEVEL])
  , "Verbosity decides what is shown on stderr. Messages up to info are"
    " always also shown in the output file. The available levels are the"
    " following:~n~n"
    "0 (quiet) Nothing is printed (equivalent to `--quiet')~n"
    "1 (error) Critical, resulting in early termination~n"
    "2 (warn)  Non-critical, notifying about weak support for a feature or~n"
    "           the use of an option that alters the output~n"
    "3 (tip)   Notifying of a suggested refactoring or option to make~n"
    "           testing more efficient~n"
    "4 (info)  Normal operation messages, can be ignored~n"
    "5 (time)  Timing messages~n"
    "6 (debug) Used only during debugging~n"
    "7 (trace) Everything else"
  }.

%% @docfile "doc/quiet_option.edoc"
-spec quiet_option() -> option_spec().

quiet_option() ->
  { quiet
  , [basic, console]
  , $q
  , undefined
  , "Do not write anything to stderr"
  , "Shorthand for `--verbosity 0'."
  }.

%% @docfile "doc/graph_option.edoc"
-spec graph_option() -> option_spec().

graph_option() ->
  { graph
  , [output, visual]
  , $g
  , string
  , "Produce a DOT graph in the specified file"
  , "The DOT graph can be converted to an image with"
    " e.g. `dot -Tsvg -o graph.svg graph'"
  }.

%% @docfile "doc/symbolic_names_option.edoc"
-spec symbolic_names_option() -> option_spec().

symbolic_names_option() ->
  { symbolic_names
  , [output, erlang, visual]
  , $s
  , {boolean, true}
  , "Use symbolic process names"
  , "Replace PIDs with symbolic names in outputs. The format used is:~n"
    "  `<[symbolic name]/[last registered name]>'~n"
    "where [symbolic name] is:~n"
    " * \"P\", for the first process and~n"
    " * \"[parent's symbolic name].[ordinal]\", for any other process,"
    " where [ordinal] shows the order of spawning (e.g. `<P.2>' is the"
    " second process spawned by `<P>').~n"
    "The [last registered name] part is shown only if relevant."
  }.

%% @docfile "doc/print_depth_option.edoc"
-spec print_depth_option() -> option_spec().

print_depth_option() ->
  { print_depth
  , [output, visual]
  , undefined
  , {integer, ?DEFAULT_PRINT_DEPTH}
  , "Print depth for log/graph"
  , "Specifies the max depth for any terms printed in the log (behaves just as"
    " the extra argument of ~~W and ~~P argument of `io:format/3'). If you want"
    " more info about a particular piece of data in an interleaving, consider"
    " using `erlang:display/1' and checking the standard output section; in the"
    " error reports of the analysis report instead."
  }.

%% @docfile "doc/show_races_option.edoc"
-spec show_races_option() -> option_spec().

show_races_option() ->
  { show_races
  , [output, por, visual]
  , undefined
  , {boolean, false}
  , "Show races in log/graph",
    "Determines whether information about pairs of racing instructions will be"
    " included in the logs of erroneous interleavings and the graph."
  }.

%% @docfile "doc/file_option.edoc"
-spec file_option() -> option_spec().

file_option() ->
  { file
  , [input]
  , $f
  , string
  , "Load specific files (.beam or .erl)"
  , "Explicitly load the specified file(s) (.beam or .erl)."
    " Source (.erl) files should not require any command line compile options."
    " Use a .beam file (preferably compiled with `+debug_info') if special"
    " compilation is needed."
  }.

%% @docfile "doc/pa_option.edoc"
-spec pa_option() -> option_spec().

pa_option() ->
  { pa
  , [input]
  , undefined
  , string
  , "Add directories to Erlang's code path (front)"
  , "Works exactly like `erl -pa'."
  }.

%% @docfile "doc/pz_option.edoc"
-spec pz_option() -> option_spec().

pz_option() ->
  { pz
  , [input]
  , undefined
  , string
  , "Add directories to Erlang's code path (rear)"
  , "Works exactly like `erl -pz'."
  }.

%% @docfile "doc/exclude_module_option.edoc"
-spec exclude_module_option() -> option_spec().

exclude_module_option() ->
  { exclude_module
  , [advanced, experimental, input]
  , $x
  , atom
  , "* Do not instrument the specified modules"
  , "Experimental. Concuerror needs to instrument all code in a test to be able"
    " to reset the state after each exploration. You can use this option to"
    " exclude a module from instrumentation, but you must ensure that any state"
    " is reset correctly, or Concuerror will complain that operations have"
    " unexpected results."
  }.

%% @docfile "doc/depth_bound_option.edoc"
-spec depth_bound_option() -> option_spec().

depth_bound_option() ->
  { depth_bound
  , [bound]
  , $d
  , {integer, 500}
  , "Maximum number of events"
  , "The maximum number of events allowed in an interleaving. Concuerror will"
    " stop exploring an interleaving that has events beyond this limit."
  }.

%% @docfile "doc/interleaving_bound_option.edoc"
-spec interleaving_bound_option() -> option_spec().

interleaving_bound_option() ->
  { interleaving_bound
  , [bound]
  , $i
  , {integer, infinity}
  , "Maximum number of interleavings"
  , "The maximum number of interleavings that will be explored. Concuerror will"
    " stop exploration beyond this limit."
  }.

%% @docfile "doc/dpor_option.edoc"
-spec dpor_option() -> option_spec().

dpor_option() ->
  { dpor
  , [por]
  , undefined
  , {atom, optimal}
  , "DPOR technique"
  , "Specifies which Dynamic Partial Order Reduction technique will be used."
    " The available options are:~n"
    "-       `none': Disable DPOR. Not recommended.~n"
    "-    `optimal': Using source sets and wakeup trees.~n"
    "-     `source': Using source sets only. Use this if the rate of~n"
    "                exploration is too slow. Use `optimal' if a lot of~n"
    "                interleavings are reported as sleep-set blocked.~n"
    "- `persistent': Using persistent sets. Not recommended."
  }.

%% @docfile "doc/optimal_option.edoc"
-spec optimal_option() -> option_spec().

optimal_option() ->
  { optimal
  , [por]
  , undefined
  , boolean
  , "Synonym for `--dpor optimal (true) | source (false)'"
  , nolong
  }.

%% @docfile "doc/scheduling_bound_type_option.edoc"
-spec scheduling_bound_type_option() -> option_spec().

scheduling_bound_type_option() ->
  { scheduling_bound_type
  , [bound, experimental]
  , $c, {atom, none}
  , "* Schedule bounding technique"
  , "Enables scheduling rules that prevent interleavings from being explored."
    " The available options are:~n"
    "-   `none': no bounding~n"
    "-   `bpor': how many times per interleaving the scheduler is allowed~n"
    "            to preempt a process.~n"
    "            * Not compatible with Optimal DPOR.~n"
    "-  `delay': how many times per interleaving the scheduler is allowed~n"
    "            to skip the process chosen by default in order to schedule~n"
    "            others.~n"
    "-  `ubpor': same as 'bpor' but without conservative backtrack points.~n"
    "            * Experimental, unsound, not compatible with Optimal DPOR.~n"
  }.

%% @docfile "doc/scheduling_bound_option.edoc"
-spec scheduling_bound_option() -> option_spec().

scheduling_bound_option() ->
  { scheduling_bound
  , [bound]
  , $b
  , integer
  , "Scheduling bound value"
  , "The maximum number of times the rule specified in"
    " `--scheduling_bound_type' can be violated."
  }.

%% @docfile "doc/disable_sleep_sets_option.edoc"
-spec disable_sleep_sets_option() -> option_spec().

disable_sleep_sets_option() ->
  { disable_sleep_sets
  , [advanced, por]
  , undefined
  , {boolean, false}
  , "Disable sleep sets"
  , "This option is only available with `--dpor none'."
  }.

%% @docfile "doc/after_timeout_option.edoc"
-spec after_timeout_option() -> option_spec().

after_timeout_option() ->
  { after_timeout
  , [erlang]
  , $a
  , {integer, infinity}
  , "Ignore timeouts greater than this value"
  , "Assume that `after' clause timeouts higher or equal to the specified value"
    " (integer) will never be triggered."
  }.

%% @docfile "doc/instant_delivery_option.edoc"
-spec instant_delivery_option() -> option_spec().

instant_delivery_option() ->
  { instant_delivery
  , [erlang]
  , undefined
  , {boolean, true}
  , "Messages and signals arrive instantly"
  , "Assume that messages and signals are delivered immediately, when sent to a"
    " process on the same node."
  }.

%% @docfile "doc/use_receive_patterns_option.edoc"
-spec use_receive_patterns_option() -> option_spec().

use_receive_patterns_option() ->
  { use_receive_patterns
  , [advanced, erlang, por]
  , undefined
  , {boolean, true}
  , "Use receive patterns for racing sends"
  , "If true, Concuerror will only consider two"
    " message deliveries as racing when the first message is really"
    " received and the patterns used could also match the second"
    " message."
  }.

%% @docfile "doc/observers_option.edoc"
-spec observers_option() -> option_spec().

observers_option() ->
  { observers
  , [advanced, erlang, por]
  , undefined
  , boolean
  , "Synonym of `--use_receive_patterns'"
  , nolong
  }.

%% @docfile "doc/scheduling_option.edoc"
-spec scheduling_option() -> option_spec().

scheduling_option() ->
  { scheduling
  , [advanced]
  , undefined
  , {atom, round_robin}
  , "Scheduling order"
  , "How Concuerror picks the next process to run. The available options are"
    " `oldest', `newest' and `round_robin'."
  }.

%% @docfile "doc/strict_scheduling_option.edoc"
-spec strict_scheduling_option() -> option_spec().

strict_scheduling_option() ->
  { strict_scheduling
  , [advanced]
  , undefined
  , {boolean, false}
  , "Forces preemptions"
  , "Whether Concuerror should enforce the scheduling strategy strictly or let"
    " a process run until blocked before reconsidering the scheduling policy."
  }.

%% @docfile "doc/keep_going_option.edoc"
-spec keep_going_option() -> option_spec().

keep_going_option() ->
  { keep_going
  , [basic, errors]
  , $k
  , {boolean, false}
  , "Keep running after an error is found"
  , "Concuerror stops by default when the first error is found. Enable this"
    " flag to keep looking for more errors. Preferably, modify the test, or"
    " use the `--ignore_error' / `--treat_as_normal' options."
  }.

%% @docfile "doc/ignore_error_option.edoc"
-spec ignore_error_option() -> option_spec().

ignore_error_option() ->
  { ignore_error
  , [errors]
  , undefined
  , atom,
    "Ignore particular kinds of errors",
    "Concuerror will not report errors of the specified kind:~n"
    "'abnormal_exit': processes exiting with any abnormal reason;"
    " check `-h treat_as_normal' and `-h assertions_only' for more refined"
    " control~n"
    "'abnormal_halt': processes executing erlang:halt/1,2 with status /= 0~n"
    "'deadlock': processes waiting at a receive statement~n"
    "'depth_bound': reaching the depth bound; check `-h depth_bound'"
  }.

%% @docfile "doc/treat_as_normal_option.edoc"
-spec treat_as_normal_option() -> option_spec().

treat_as_normal_option() ->
  { treat_as_normal
  , [errors]
  , undefined
  , atom
  , "Exit reasons treated as 'normal'"
  , "A process that exits with the specified atom as reason (or with a reason"
    " that is a tuple with the specified atom as a first element) will not be"
    " reported as exiting abnormally. Useful e.g. when analyzing supervisors"
    " ('shutdown' is usually a normal exit reason in this case)."
  }.

%% @docfile "doc/assertions_only_option.edoc"
-spec assertions_only_option() -> option_spec().

assertions_only_option() ->
  { assertions_only
  , [errors]
  , undefined
  , {boolean, false}
  , "Only report abnormal exits due to `?asserts'",
    "Only processes that exit with a reason of form `{{assert*, _}, _}' are"
    " considered errors. Such exit reasons are generated e.g. by the"
    " macros defined in the `stdlib/include/assert.hrl' header file."
  }.

%% @docfile "doc/first_process_errors_only_option.edoc"
-spec first_process_errors_only_option() -> option_spec().

first_process_errors_only_option() ->
  { first_process_errors_only
  , [errors]
  , undefined
  , {boolean, false}
  , "Only report errors that involve the first process"
  , "All errors involving only children processes will be ignored."
  }.

%% @docfile "doc/timeout_option.edoc"
-spec timeout_option() -> option_spec().

timeout_option() ->
  { timeout
  , [advanced, erlang]
  , undefined
  , {integer, 5000}
  , "How long to wait for an event (>= " ++
      integer_to_list(?MINIMUM_TIMEOUT) ++ "ms)"
  , "How many ms to wait before assuming that a process is stuck in an infinite"
    " loop between two operations with side-effects. Setting this to -1 will"
    " make Concuerror wait indefinitely. Otherwise must be >= " ++
      integer_to_list(?MINIMUM_TIMEOUT) ++ "."
  }.

%% @docfile "doc/assume_racing_option.edoc"
-spec assume_racing_option() -> option_spec().

assume_racing_option() ->
  { assume_racing
  , [advanced, por]
  , undefined
  , {boolean, true}
  , "Unknown operations are considered racing"
  , "Concuerror has a list of operation pairs that are known to be non-racing."
    " If there is no info about whether a specific pair of built-in operations"
    " may race, assume that they do indeed race. If this option is set to"
    " false, Concuerror will exit instead. Useful only for detecting missing"
    " racing info."
  }.

%% @docfile "doc/non_racing_system_option.edoc"
-spec non_racing_system_option() -> option_spec().

non_racing_system_option() ->
  { non_racing_system
  , [erlang]
  , undefined
  , atom
  , "No races due to 'system' messages"
  , "Assume that any messages sent to the specified (by registered name) system"
    " process are not racing with each-other. Useful for reducing the number of"
    " interleavings when processes have calls to e.g. io:format/1,2 or"
    " similar."
  }.

%% @docfile "doc/help_option.edoc"
-spec help_option() -> option_spec().

help_option() ->
  { help
  , [basic]
  , $h
  , atom
  , "Display help (use `-h h' for more help)"
  , "Without an argument, prints info for basic options.~n~n"
    "With `all' as argument, prints info for all options.~n~n"
    "With `attributes' as argument, prints info about passing options using"
    " module attributes.~n~n"
    "With `progress' as argument, prints info about what the items in the"
    " progress info mean.~n~n"
    "With an option name as argument, prints more help for that option.~n~n"
    "Options have keywords associated with them (shown in their help)."
    " With a keyword as argument, prints a list of all options with the"
    " keyword.~n~n"
    "If an expected argument is omitted, `true' or `1' is the implied"
    " value."
  }.

%% @docfile "doc/version_option.edoc"
-spec version_option() -> option_spec().

version_option() ->
  { version
  , [basic]
  , undefined
  , undefined
  , "Display version information"
  , nolong
  }.

%%%-----------------------------------------------------------------------------

synonyms() ->
  [ {{observers, true}, {use_receive_patterns, true}}
  , {{observers, false}, {use_receive_patterns, false}}
  , {{optimal, true}, {dpor, optimal}}
  , {{optimal, false}, {dpor, source}}
  , {{ignore_error, crash}, {ignore_error, abnormal_exit}}
  ].

groupable() ->
  [ exclude_module
  , ignore_error
  , non_racing_system
  , treat_as_normal
  ].

multiple_allowed() ->
  [ pa
  , pz
  ] ++
    groupable().

not_allowed_in_module_attributes() ->
  [ exclude_module
  , file
  , help
  , module
  , pa
  , pz
  , version
  ].

derived_defaults() ->
  [ {{disable_sleep_sets, true}, [{dpor, none}]}
  , {scheduling_bound, [{scheduling_bound_type, delay}]}
  , {{scheduling_bound_type, bpor}, [{dpor, source}, {scheduling_bound, 1}]}
  , {{scheduling_bound_type, delay}, [{scheduling_bound, 1}]}
  , {{scheduling_bound_type, ubpor}, [{dpor, source}, {scheduling_bound, 1}]}
  ] ++
  [{{dpor, NotObsDPOR}, [{use_receive_patterns, false}]}
    || NotObsDPOR <- [none, persistent, source]].

check_validity(Key) ->
  case Key of
    _
      when
        Key =:= after_timeout;
        Key =:= depth_bound;
        Key =:= print_depth
        ->
      {fun(V) -> V > 0 end, "a positive integer"};
    dpor ->
      [none, optimal, persistent, source];
    ignore_error ->
      Valid = [abnormal_halt, abnormal_exit, deadlock, depth_bound],
      {fun(V) -> [] =:= (V -- Valid) end,
       io_lib:format("one or more of ~w",[Valid])};
    scheduling ->
      [newest, oldest, round_robin];
    scheduling_bound ->
      {fun(V) -> V >= 0 end, "a non-negative integer"};
    scheduling_bound_type ->
      [bpor, delay, none, ubpor];
    _ -> skip
  end.

%%------------------------------------------------------------------------------

%% @doc Converts command-line arguments to a proplist using getopt
%%
%% This function also augments the interface of getopt, allowing
%% <ul>
%%   <li> multiple arguments to options</li>
%%   <li> correction of common errors</li>
%% </ul>

-spec parse_cl([string()]) ->
                  {'run', options()} | {'return', concuerror:exit_status()}.

parse_cl(CommandLineArgs) ->
  try
    %% CL parsing uses some version-dependent functions
    check_otp_version(),
    parse_cl_aux(CommandLineArgs)
  catch
    throw:opt_error -> options_fail()
  end.

options_fail() ->
  [concuerror_logger:print_log_message(Level, Format, Args)
   || {Level, Format, Args} <- get_logs()],
  {return, fail}.

parse_cl_aux([]) ->
  {run, [help]};
parse_cl_aux(RawCommandLineArgs) ->
  CommandLineArgs = fix_common_errors(RawCommandLineArgs),
  case getopt:parse(getopt_spec_no_default(), CommandLineArgs) of
    {ok, {Options, OtherArgs}} ->
      case OtherArgs of
        [] -> {run, Options};
        [MaybeFilename] ->
          Msg = "Converting dangling argument to '--file ~s'",
          opt_info(Msg, [MaybeFilename]),
          {run, Options ++ [{file, MaybeFilename}]};
        _ ->
          Msg = "Unknown argument(s)/option(s): ~s",
          opt_error(Msg, [?join(OtherArgs, " ")])
      end;
    {error, Error} ->
      case Error of
        {missing_option_arg, help} ->
          cl_usage(basic),
          {return, ok};
        {missing_option_arg, Option} ->
          opt_error("No argument given for '--~s'.", [Option], Option);
        _Other ->
          opt_error(getopt:format_error([], Error))
      end
  end.

fix_common_errors(RawCommandLineArgs) ->
  FixDashes = lists:map(fun fix_common_error/1, RawCommandLineArgs),
  fix_multiargs(FixDashes).

fix_common_error("--" ++ [C] = Option) ->
  opt_info("\"~s\" converted to \"-~c\"", [Option, C]),
  "-" ++ [C];
fix_common_error("--" ++ Text = Option) ->
  Underscored = lists:map(fun dash_to_underscore/1, lowercase(Text)),
  case Text =:= Underscored of
    true -> Option;
    false ->
      opt_info("\"~s\" converted to \"--~s\"", [Option, Underscored]),
      "--" ++ Underscored
  end;
fix_common_error("-p" ++ [A] = Option) when A =:= $a; A=:= $z ->
  opt_info("\"~s\" converted to \"-~s\"", [Option, Option]),
  fix_common_error("-" ++ Option);
fix_common_error("-" ++ [Short|[_|_] = MaybeArg] = MaybeMispelledOption) ->
  maybe_warn_about_mispelled_option(Short, MaybeArg),
  MaybeMispelledOption;
fix_common_error(OptionOrArg) ->
  OptionOrArg.

dash_to_underscore($-) -> $_;
dash_to_underscore(Ch) -> Ch.

maybe_warn_about_mispelled_option(Short, [_|_] = MaybeArg) ->
  ShortWithArgToLong =
    [{element(?OPTION_SHORT, O), element(?OPTION_KEY, O)}
     || O <- options(),
        element(?OPTION_SHORT, O) =/= undefined,
        not (option_type(O) =:= boolean),
        not (option_type(O) =:= integer)
    ],
  case lists:keyfind(Short, 1, ShortWithArgToLong) of
    {_, Long} ->
      opt_info(
        "Parsing '-~s' as '--~w ~s' (add a dash if this is not desired)",
        [[Short|MaybeArg], Long, MaybeArg]);
    _ -> ok
  end.

option_type(Option) ->
  case element(?OPTION_GETOPT_TYPE_DEFAULT, Option) of
    {Type, _Default} -> Type;
    Type -> Type
  end.

fix_multiargs(CommandLineArgs) ->
  fix_multiargs(CommandLineArgs, []).

fix_multiargs([], Fixed) ->
  lists:reverse(Fixed);
fix_multiargs([Flag1, Arg1, Arg2 | Rest], Fixed)
  when hd(Flag1) =:= $-, hd(Arg1) =/= $-, hd(Arg2) =/= $- ->
  opt_info(
    "\"~s ~s ~s\" converted to \"~s ~s ~s ~s\"",
    [Flag1, Arg1, Arg2, Flag1, Arg1, Flag1, Arg2]),
  fix_multiargs([Flag1,Arg2|Rest], [Arg1,Flag1|Fixed]);
fix_multiargs([Other|Rest], Fixed) ->
  fix_multiargs(Rest, [Other|Fixed]).

%%%-----------------------------------------------------------------------------

getopt_spec(Options) ->
  getopt_spec_map_type(Options, fun(X) -> X end).

%% Defaults are stripped and inserted in the end to allow for overrides from an
%% input file or derived defaults.
getopt_spec_no_default() ->
  getopt_spec_map_type(options(), fun no_default/1).

%% An option's long name is the same as the inner representation atom for
%% consistency.
getopt_spec_map_type(Options, Fun) ->
  [{Key, Short, atom_to_list(Key), Fun(Type), Help} ||
    {Key, _Keywords, Short, Type, Help, _Long} <- Options].

no_default({Type, _Default}) -> Type;
no_default(Type) -> Type.

%%%-----------------------------------------------------------------------------

cl_usage(all) ->
  Sort = fun(A, B) -> element(?OPTION_KEY, A) =< element(?OPTION_KEY, B) end,
  getopt:usage(getopt_spec(lists:sort(Sort, options())), "./concuerror"),
  print_suffix(all);
cl_usage(Attribute)
  when Attribute =:= attribute;
       Attribute =:= attributes ->
  Msg =
    "~n"
    "Passing options using module attributes:~n"
    "----------------------------------------~n"
    "You can use the following attributes in the module specified by '--module'"
    " to pass options to Concuerror:~n"
    "~n"
    "  -~s(Options).~n"
    "    A list of Options that can be overriden by other options.~n"
    "  -~s(Options).~n"
    "    A list of Options that override any other options.~n"
    ,
  to_stderr(Msg, [?ATTRIBUTE_OPTIONS, ?ATTRIBUTE_FORCED_OPTIONS]);
cl_usage(progress) ->
  Msg =
    "~n"
    "Progress bar item explanations:~n"
    "-------------------------------~n"
    "~n"
    "~s"
    ,
  to_stderr(Msg, [concuerror_logger:progress_help()]);
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
          KeywordWarningFormat =
            "~n"
            "NOTE: Only showing options with the keyword `~p'.~n"
            "      Use `--help all' to see all available options.~n",
          to_stderr(KeywordWarningFormat, [Name]),
          getopt:usage(getopt_spec(MaybeKeyword), "./concuerror"),
          print_suffix(Name);
        false ->
          ListName = atom_to_list(Name),
          case [dash_to_underscore(L) || L <- ListName] of
            "_" ++ Rest -> cl_usage(list_to_atom(Rest));
            Other when Other =/= ListName -> cl_usage(list_to_atom(Other));
            _ ->
              Msg = "invalid option/keyword (as argument to `--help'): '~w'.",
              opt_error(Msg, [Name], help)
          end
      end;
    Tuple ->
      getopt:usage(getopt_spec([Tuple]), "./concuerror"),
      case element(?OPTION_GETOPT_LONG_HELP, Tuple) of
        nolong -> to_stderr("No additional help available.~n");
        String -> to_stderr(String ++ "~n")
      end,
      {Keywords, Related} = get_keywords_and_related(Tuple),
      to_stderr("Option Keywords: ~p~nRelated Options: ~p~n", [Keywords, Related]),
      to_stderr("For general help use `-h' without an argument.~n")
  end.

options(Keyword) ->
  [T || T <- options(), lists:member(Keyword, element(?OPTION_KEYWORDS, T))].

print_suffix(Keyword) ->
  case Keyword =:= basic of
    false -> to_stderr("Options with '*' are experimental.~n");
    true -> ok
  end,
  to_stderr("More info & keywords about a specific option: `-h <option>'.~n"),
  case Keyword =:= basic orelse Keyword =:= all of
    true -> print_exit_status_info();
    false -> ok
  end,
  print_bugs_message().

print_exit_status_info() ->
  Message = concuerror:analysis_result_documentation(),
  to_stderr(Message).

print_bugs_message() ->
  Message = "Report bugs (and other FAQ): http://parapluu.github.io/Concuerror/faq~n",
  to_stderr(Message).

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
  {Keywords, lists:sort(Related)}.

%%%-----------------------------------------------------------------------------

%% @private
-type log_messages() :: [{concuerror_logger:log_level(), string(), [term()]}].

-spec finalize(options()) ->
                  {'run', options(), log_messages()} |
                  {'return', concuerror:exit_status()}.

finalize(Options) ->
  try
    %% We might have been invoked by an Erlang shell, so check again.
    check_otp_version(),
    case check_help_and_version(Options) of
      exit -> {return, ok};
      ok ->
        FinalOptions = finalize_2(Options),
        {run, FinalOptions, get_logs()}
    end
  catch
    throw:opt_error -> options_fail()
  end.

check_help_and_version(Options) ->
  case {proplists:get_bool(version, Options),
        proplists:is_defined(help, Options)} of
    {true, _} ->
      to_stderr("~s", [concuerror:version()]),
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

check_otp_version() ->
  CurrentOTPRelease =
    case erlang:system_info(otp_release) of
      "R" ++ _ -> 16; %% ... or earlier
      [D,U|_] -> list_to_integer([D,U])
    end,
  case CurrentOTPRelease =:= ?OTP_VERSION of
    true -> ok;
    false ->
      opt_error(
        "Concuerror has been compiled for a different version of Erlang/OTP."
        " Please run `make distclean; make` again.",[])
  end.

%%%-----------------------------------------------------------------------------

finalize_2(Options) ->
  Passes =
    [ normalize_fun("argument")
    , fun set_verbosity/1
    , fun open_files/1
    , fun add_to_path/1
    , fun add_missing_file/1
      %% We need group multiples to find excluded files before loading
    , fun group_multiples/1
    , fun initialize_loader/1
    , fun load_files/1
    , fun ensure_module/1
    , fun add_options_from_module/1
    , fun add_derived_defaults/1
    , fun add_getopt_defaults/1
    , fun group_multiples/1
    , fun fix_infinities/1
    , fun(O) ->
          add_defaults([{Opt, []} || Opt <- groupable()], false, O)
      end
    , fun ensure_entry_point/1
    ],
  FinalOptions = run_passes(Passes, Options),
  consistent(FinalOptions),
  FinalOptions.

run_passes([], Options) ->
  Options;
run_passes([Pass|Passes], Options) ->
  run_passes(Passes, Pass(Options)).

%%%-----------------------------------------------------------------------------

normalize_fun(Source) ->
  fun(Options) ->
      Passes =
        [ fun proplists:unfold/1
        , fun substitute_synonyms/1
        , fun expand_short_names/1
        , ensure_known_options_fun(Source)
        ],
      run_passes(Passes, Options)
  end.

substitute_synonyms(Options) ->
  Map =
    fun(Option) ->
        case lists:keyfind(Option, 1, synonyms()) of
          false -> Option;
          {{Key, Value}, {SKey, SValue} = Synonym} ->
            opt_info(
              "\"--~w ~w\" converted to \"--~w ~w\"",
              [Key, Value, SKey, SValue]),
            Synonym
        end
    end,
  [Map(Option) || Option <- Options].

expand_short_names(Options) ->
  Map =
    fun(Key) ->
        case lists:keyfind(Key, ?OPTION_SHORT, options()) of
          false -> Key;
          Option -> element(?OPTION_KEY, Option)
        end
    end,
  lists:keymap(Map, 1, Options).

ensure_known_options_fun(Source) ->
  fun(Options) ->
      KnownKeys =
        [element(?OPTION_KEY, O) || O <- options()]
        ++ [entry_point, files],
      Fun =
        fun(T) ->
            is_tuple(T) andalso
              size(T) =:= 2 andalso
              lists:member(element(1, T), KnownKeys)
        end,
      case lists:dropwhile(Fun, Options) of
        [] -> Options;
        [T|_] ->
          Error = "invalid ~s: '~w'",
          opt_error(Error, [Source, element(1, T)], input)
      end
  end.
%%%-----------------------------------------------------------------------------

set_verbosity(Options) ->
  HasQuiet = proplists:get_bool(quiet, Options),
  AllVerbosity = proplists:get_all_values(verbosity, Options),
  SpecifiedVerbosity =
    case {AllVerbosity, HasQuiet} of
      {[], false} -> ?DEFAULT_VERBOSITY;
      {[], true} -> 0;
      {_, true} ->
        Msg = "'--verbosity' specified together with '--quiet'.",
        opt_error(Msg, [], verbosity);
      {N, false} -> lists:sum(N)
    end,
  Verbosity = min(SpecifiedVerbosity, ?MAX_LOG_LEVEL),
  case ?has_dev orelse (Verbosity < ?ldebug) of
    true -> ok;
    false ->
      Error =
        "To use verbosity > ~w, rebuild Concuerror with"
        " 'make distclean; make dev'.",
      opt_error(Error, [?ldebug - 1])
  end,
  NewOptions = delete_options(verbosity, Options),
  [{verbosity, Verbosity}|NewOptions].

%%%-----------------------------------------------------------------------------

open_files(Options) ->
  HasNoOutput = proplists:get_bool(no_output, Options),
  OutputOption =
    form_file_option(Options, output, ?DEFAULT_OUTPUT, HasNoOutput),
  GraphOption =
    form_file_option(Options, graph, "/dev/null", HasNoOutput),
  NewOptions = delete_options([output, graph], Options),
  [{output, OutputOption}, {graph, GraphOption} | NewOptions].

form_file_option(Options, FileOption, Default, HasNoOutput) ->
  case {proplists:get_all_values(FileOption, Options), HasNoOutput} of
    {[], true} -> open_file("/dev/null", FileOption);
    {[], false} -> open_file(Default, FileOption);
    {[F], false} -> open_file(F, FileOption);
    {_, true} ->
      opt_error(
        "'--~p' cannot be used together with '--no_output'.",
        [FileOption], FileOption);
    {_, false} ->
      multiple_opt_error(output)
  end.

open_file("/dev/null", _FileOption) ->
  {disable, ""};
open_file(Filename, FileOption) ->
  case file:open(Filename, [write]) of
    {ok, IoDevice} ->
      {IoDevice, Filename};
    {error, _} ->
      opt_error(
        "Could not open '--~w' file ~s for writing.",
        [FileOption, Filename], FileOption)
  end.

%%%-----------------------------------------------------------------------------

add_to_path(Options) ->
  Foreach =
    fun({Key, Value}) when Key =:= pa; Key =:= pz ->
        PathAdd =
          case Key of
            pa -> fun code:add_patha/1;
            pz -> fun code:add_pathz/1
          end,
        case PathAdd(Value) of
          true -> ok;
          {error, bad_directory} ->
            Msg = "Could not add '~s' to code path.",
            opt_error(Msg, [Value], Key)
        end;
       (_) -> ok
    end,
  lists:foreach(Foreach, Options),
  Options.

%%%-----------------------------------------------------------------------------

add_missing_file(Options) ->
  case proplists:get_all_values(module, Options) of
    [Module] ->
      try
        _ = Module:module_info(attributes),
        Options
      catch
        _:_ ->
          case proplists:get_all_values(file, Options) of
            [] ->
              Source = atom_to_list(Module) ++ ".erl",
              Msg = "Automatically added '--file ~s'.",
              opt_info(Msg, [Source]),
              case filelib:is_file(Source) of
                true -> [{file, Source}|Options];
                false -> Options
              end;
            _ -> Options
          end
      end;
    _ -> Options
  end.

%%%-----------------------------------------------------------------------------

initialize_loader(Options) ->
  Excluded = proplists:get_value(exclude_module, Options, []),
  [opt_warn("Not instrumenting module ~p", [M]) || M <- Excluded],
  case concuerror_loader:initialize(Excluded) of
    ok -> Options;
    {error, Error} -> opt_error(Error)
  end.

%%%-----------------------------------------------------------------------------

load_files(Options) ->
  Singles = proplists:get_all_values(file, Options),
  Multis = proplists:get_all_values(files, Options),
  Files = lists:append([Singles|Multis]),
  compile_and_load(Files, [], false, Options).

compile_and_load([], [], _, Options) ->
  Options;
compile_and_load([], [_|More] = LoadedFiles, LastModule, Options) ->
  MissingModule =
    case
      More =:= [] andalso
      not proplists:is_defined(module, Options) andalso
      not proplists:is_defined(entry_point, Options)
    of
      true -> [{module, LastModule}];
      false -> []
    end,
  NewOptions = delete_options([file, files], Options),
  MissingModule ++ [{files, lists:sort(LoadedFiles)}|NewOptions];
compile_and_load([File|Rest], Acc, _LastModule, Options) ->
  case concuerror_loader:load_initially(File) of
    {ok, Module, Warnings} ->
      opt_info("Instrumented & loaded module ~p", [Module]),
      lists:foreach(fun(W) -> opt_warn(W, []) end, Warnings),
      compile_and_load(Rest, [File|Acc], Module, Options);
    {error, Error} ->
      opt_error(Error, [], file)
  end.

%%%-----------------------------------------------------------------------------

ensure_module(Options) ->
  Module =
    case proplists:get_all_values(entry_point, Options) of
      [] ->
        case proplists:get_all_values(module, Options) of
          [] ->
            UndefinedEntryPoint =
              "The module containing the main test function has not been specified.",
            opt_error(UndefinedEntryPoint, [], module);
          [M] -> M;
          _ ->
            multiple_opt_error(module)
        end;
      [{M,_,_}] -> M;
      [_,_|_] ->
        opt_error("Multiple instances of 'entry_point' specified.", [], module);
      [Other] ->
        opt_error("The specified 'entry_point' '~w' is invalid.", [Other], module)
    end,
  try
    Module:module_info(attributes)
  catch
    _:_ ->
      opt_error("Could not find module ~w.", [Module], module)
  end,
  [{module, Module}|delete_options(module,Options)].

%%%-----------------------------------------------------------------------------

add_options_from_module(Options) ->
  Module = proplists:get_value(module, Options),
  Attributes = Module:module_info(attributes),
  Forced =
    get_options_from_attribute(?ATTRIBUTE_FORCED_OPTIONS, Attributes),
  Others =
    get_options_from_attribute(?ATTRIBUTE_OPTIONS, Attributes),
  case Forced ++ Others =:= [] of
    true when length(Options) > ?ATTRIBUTE_TIP_THRESHOLD ->
      opt_tip("Check `--help attributes' for info on how to pass options via"
              " module attributes.", []);
    _ -> ok
  end,
  check_unique_options_from_module(Forced, Others),
  WithForced =
    override(?ATTRIBUTE_FORCED_OPTIONS, Forced, "command line", Options),
  KeepLast = keep_last_option(WithForced),
  override("command line", KeepLast, ?ATTRIBUTE_OPTIONS, Others).

get_options_from_attribute(Attribute, Attributes) ->
  case proplists:get_value(Attribute, Attributes) of
    undefined ->
      [];
    Options ->
      filter_from_attribute(Options, Attribute)
  end.

filter_from_attribute(OptionsRaw, Where) ->
  NormalizeFun =
    normalize_fun(io_lib:format("option in ~w attribute", [Where])),
  Options = NormalizeFun(OptionsRaw),
  AllowedPred =
    fun({Key, _Value}) ->
        not lists:member(Key, not_allowed_in_module_attributes())
    end,
  case lists:dropwhile(AllowedPred, Options) of
    [] -> Options;
    [{Key,_}|_] ->
      opt_error("Option '~p' not allowed in ~p.", [Key, Where])
  end.

check_unique_options_from_module(Forced, Options) ->
  Pred = fun({Key, _Value}) -> not lists:member(Key, multiple_allowed()) end,
  ForcedNonMultiple = lists:filter(Pred, Forced),
  OptionsNonMultiple = lists:filter(Pred, Options),
  check_unique_options_from_module_aux(ForcedNonMultiple, OptionsNonMultiple).

check_unique_options_from_module_aux([], []) -> ok;
check_unique_options_from_module_aux([], [{Key, _Value}|Rest]) ->
  case proplists:is_defined(Key, Rest) of
    true ->
      Msg = "Multiple instances of option ~p not allowed in ~p.",
      opt_error(Msg, [Key, ?ATTRIBUTE_OPTIONS]);
    false ->
      check_unique_options_from_module_aux([], Rest)
  end;
check_unique_options_from_module_aux([{Key, _Value}|Rest], Options) ->
  case proplists:is_defined(Key, Rest) of
    true ->
      Msg = "Multiple instances of option ~p not allowed in ~p.",
      opt_error(Msg, [Key, ?ATTRIBUTE_FORCED_OPTIONS]);
    false ->
      case proplists:is_defined(Key, Options) of
        true ->
          Msg = "Multiple instances of option ~p in ~p and ~p not allowed.",
          opt_error(Msg, [Key, ?ATTRIBUTE_FORCED_OPTIONS, ?ATTRIBUTE_OPTIONS]);
        false ->
          check_unique_options_from_module_aux(Rest, Options)
      end
  end.

%% This unintentionally puts the 'multiple_allowed' options in front.
%% Possible to do otherwise but not needed.
keep_last_option(Options) ->
  Pred = fun({Key, _Value}) -> lists:member(Key, multiple_allowed()) end,
  {Multiple, NonMultiple} = lists:partition(Pred, Options),
  Fold =
    fun({Key, _Value} = Option, Acc) ->
        case proplists:lookup(Key, Acc) of
          none -> [Option|Acc];
          {Key, Value} ->
            Msg = "Multiple instances of '--~s' defined. Using last value: ~p.",
            opt_warn(Msg, [Key, Value]),
            Acc
        end
    end,
  KeepLastNonMultiple = lists:foldr(Fold, [], NonMultiple),
  Multiple ++ KeepLastNonMultiple.

override(_Where1, [], _Where2, Options) -> Options;
override(Where1, [{Key, _Value} = Option|Rest], Where2, Options) ->
  NewOptions =
    case lists:member(Key, multiple_allowed()) of
      true -> Options;
      false ->
        NO = delete_options(Key, Options),
        case NO =:= Options of
          true -> Options;
          false ->
            Warn = "Option ~p from ~s overrides the one specified in ~s.",
            opt_warn(Warn, [Key, Where1, Where2]),
            NO
        end
    end,
  override(Where1, Rest, Where2, [Option|NewOptions]).

%%------------------------------------------------------------------------------

add_derived_defaults(Options) ->
  add_derived_defaults(derived_defaults(), Options).

add_derived_defaults([], Options) ->
  Options;
add_derived_defaults([{TestRaw, Defaults}|Rest], Options) ->
  Test =
    case is_tuple(TestRaw) of
      true -> fun(Os) -> lists:member(TestRaw, Os) end;
      false -> fun(Os) -> proplists:is_defined(TestRaw, Os) end
    end,
  ToAdd =
    case Test(Options) of
      true -> Defaults;
      false -> []
    end,
  NewOptions = add_defaults(ToAdd, {true, TestRaw}, Options),
  add_derived_defaults(Rest, NewOptions).

add_defaults([], _Notify, Options) -> Options;
add_defaults([{Key, Value} = Default|Rest], Notify, Options) ->
  case proplists:is_defined(Key, Options) of
    true -> add_defaults(Rest, Notify, Options);
    false ->
      case Notify of
        {true, Source} ->
          Form =
            case Source of
              {K, V} -> io_lib:format("'--~p ~p'", [K, V]);
              K -> io_lib:format("'--~p'", [K])
            end,
          Msg = "Using '--~p ~p' (default for ~s).",
          opt_info(Msg, [Key, Value, Form]);
        false -> ok
      end,
      add_defaults(Rest, Notify, [Default|Options])
  end.

%%------------------------------------------------------------------------------

add_getopt_defaults(Opts) ->
  Defaults =
    [{element(?OPTION_KEY, Opt), element(?OPTION_GETOPT_TYPE_DEFAULT, Opt)}
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

%%------------------------------------------------------------------------------

group_multiples(Options) ->
  group_multiples(Options, []).

group_multiples([], Acc) ->
  lists:reverse(Acc);
group_multiples([{Key, Value} = Option|Rest], Acc) ->
  case lists:member(Key, groupable()) of
    true ->
      Values = lists:flatten([Value|proplists:get_all_values(Key, Rest)]),
      NewRest = delete_options(Key, Rest),
      group_multiples(NewRest, [{Key, lists:usort(Values)}|Acc]);
    false ->
      group_multiples(Rest, [Option|Acc])
  end.

%%------------------------------------------------------------------------------

fix_infinities(Options) ->
  fix_infinities(Options, []).

fix_infinities([], Acc) -> lists:reverse(Acc);
fix_infinities([{Key, Value} = Option|Rest], Acc) ->
  case Key of
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
          fix_infinities(Rest, [Option|Acc]);
        -1 ->
          fix_infinities(Rest, [{MaybeInfinity, infinity}|Acc]);
        N when is_integer(N), N >= Limit ->
          fix_infinities(Rest, [Option|Acc]);
        _Else ->
          Error = "The value of '--~s' must be -1 (infinity) or >= ~w",
          opt_error(Error, [Key, Limit], Key)
      end;
    _ ->
      fix_infinities(Rest, [Option|Acc])
  end.

%%------------------------------------------------------------------------------

ensure_entry_point(Options) ->
  {M, F, B} = EntryPoint =
    case proplists:get_value(entry_point, Options) of
      {_,_,_} = EP -> EP;
      undefined ->
        Module = proplists:get_value(module, Options),
        Name = proplists:get_value(test, Options, test),
        {Module, Name, []}
    end,
  CleanOptions = delete_options([entry_point, module, test], Options),
  try
    true = is_atom(M),
    true = is_atom(F),
    true = is_list(B),
    true = lists:member({F,length(B)}, M:module_info(exports)),
    [{entry_point, EntryPoint}|CleanOptions]
  catch
    _:_ ->
      InvalidEntryPoint =
        "The entry point ~w:~w/~w is invalid. Make sure you have"
        " specified the correct module ('-m') and test function ('-t').",
      opt_error(InvalidEntryPoint, [M,F,length(B)], input)
  end.

%%------------------------------------------------------------------------------

consistent(Options) ->
  CheckValidity =
    fun({Key, Value}) ->
        ValidityCheck = check_validity(Key),
        check_validity(Key, Value, ValidityCheck)
    end,
  lists:foreach(CheckValidity, Options),
  consistent(Options, []).

check_validity(_Key, _Value, skip) -> ok;
check_validity(Key, Value, Valid) when is_list(Valid) ->
  case lists:member(Value, Valid) of
    true -> ok;
    false ->
      opt_error("The value of '--~s' must be one of ~w.", [Key, Valid], Key)
  end;
check_validity(Key, Value, {Valid, Explain}) when is_function(Valid) ->
  case Valid(Value) of
    true -> ok;
    false ->
      opt_error("The value of '--~s' must be ~s.", [Key, Explain], Key)
  end.

consistent([], _) -> ok;
consistent([{assertions_only, true} = Option|Rest], Acc) ->
  check_values(
    [{ignore_error, fun(X) -> not lists:member(abnormal_exit, X) end}],
    Rest ++ Acc, Option),
  consistent(Rest, [Option|Acc]);
consistent([{disable_sleep_sets, true} = Option|Rest], Acc) ->
  check_values(
    [{dpor, fun(X) -> X =:= none end}],
    Rest ++ Acc, Option),
  consistent(Rest, [Option|Acc]);
consistent([{scheduling_bound, _} = Option|Rest], Acc) ->
  VeryFun = fun(X) -> lists:member(X, [bpor, delay, ubpor]) end,
  check_values(
    [{scheduling_bound_type, VeryFun}],
    Rest ++ Acc,
    {scheduling_bound, "an integer"}),
  consistent(Rest, [Option|Acc]);
consistent([{scheduling_bound_type, Type} = Option|Rest], Acc)
  when Type =/= none ->
  DPORVeryFun =
    case Type of
      BPORvar when BPORvar =:= bpor; BPORvar =:= ubpor ->
        fun(X) -> lists:member(X, [source, persistent]) end;
      _ ->
        fun(_) -> true end
    end,
  check_values([{dpor, DPORVeryFun}], Rest ++ Acc, Option),
  consistent(Rest, [Option|Acc]);
consistent([{use_receive_patterns, true} = Option|Rest], Acc) ->
  check_values(
    [{dpor, fun(X) -> X =:= optimal end}],
    Rest ++ Acc, Option),
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

delete_options([], Proplist) ->
  Proplist;
delete_options([Option|Rest], Proplist) ->
  delete_options(Rest, proplists:delete(Option, Proplist));
delete_options(Else, Proplist) ->
  delete_options([Else], Proplist).

-spec opt_error(string()) -> no_return().

opt_error(Format) ->
  opt_error(Format, []).

-spec opt_error(string(), [term()]) -> no_return().

opt_error(Format, Data) ->
  opt_error(Format, Data, "`--help'").

-spec opt_error(string(), [term()], string() | atom()) -> no_return().

opt_error(Format, Data, Extra) when is_atom(Extra) ->
  ExtraS = io_lib:format("`--help ~p'", [Extra]),
  opt_error(Format, Data, ExtraS);
opt_error(Format, Data, Extra) ->
  opt_log(?lerror, Format ++ "~n    Use ~s for more information.", Data ++ [Extra]),
  throw(opt_error).

-spec multiple_opt_error(atom()) -> no_return().

multiple_opt_error(M) ->
  opt_error("Multiple instances of '--~s' specified.", [M], module).

opt_info(Format, Data) ->
  opt_log(?linfo, Format, Data).

opt_warn(Format, Data) ->
  opt_log(?lwarning, Format, Data).

opt_tip(Format, Data) ->
  opt_log(?ltip, Format, Data).

opt_log(Level, Format, Data) ->
  Logs =
    case get(log_messages) of
      undefined -> [];
      W -> W
    end,
  put(log_messages, [{Level, Format ++ "~n", Data}|Logs]),
  ok.

get_logs() ->
  case erase(log_messages) of
    undefined -> [];
    Whats -> lists:reverse(Whats)
  end.

-ifdef(BEFORE_OTP_20).

lowercase(String) ->
  string:to_lower(String).

-else.

lowercase(String) ->
  string:lowercase(String).

-endif.

to_stderr(Format) ->
  to_stderr(Format, []).

to_stderr(Format, Data) ->
  io:format(standard_error, Format ++ "~n", Data).
