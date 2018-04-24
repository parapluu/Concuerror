%% -*- erlang-indent-level: 2 -*-

-module(concuerror_logger).

-export([start/1, complete/2, plan/1, log/5, race/3, finish/2, print/3, time/2]).
-export([bound_reached/1, set_verbosity/2]).
-export([graph_set_node/3, graph_new_node/4, graph_race/3]).
-export([print_log_message/3]).
-export([showing_progress/1, progress_help/0]).

-include("concuerror.hrl").

-type log_level() :: ?lquiet..?MAX_VERBOSITY.

-define(TICKER_TIMEOUT, 500).
%%------------------------------------------------------------------------------

-type unique_id() :: concuerror_scheduler:unique_id().

-type stream() :: 'standard_io' | 'standard_error' | 'race' | file:filename().
-type graph_data() ::
        { file:io_device()
        , unique_id() | 'init'
        , unique_id() | 'none'
        }.

%%------------------------------------------------------------------------------

-ifdef(BEFORE_OTP_17).
-type unique_ids() :: set().
-else.
-type unique_ids() :: sets:set(integer()).
-endif.

%%------------------------------------------------------------------------------

-ifdef(BEFORE_OTP_18).

-type timestamp() :: erlang:timestamp().
timestamp() ->
  erlang:now().
timediff(After, Before) ->
  timer:now_diff(After, Before) / 1000000.

-else.

-type timestamp() :: integer().
timestamp() ->
  erlang:monotonic_time(milli_seconds).
timediff(After, Before) ->
  (After - Before) / 1000.

-endif.

%%------------------------------------------------------------------------------

-record(rate_info, {
          average   :: concuerror_window_average:average(),
          prev      :: non_neg_integer(),
          timestamp :: timestamp()
         }).

-record(logger_state, {
          already_emitted = sets:new() :: unique_ids(),
          bound_reached = false        :: boolean(),
          emit_logger_tips = initial   :: 'initial' | 'false',
          errors = 0                   :: non_neg_integer(),
          estimator                    :: concuerror_estimator:estimator(),
          graph_data                   :: graph_data() | 'disable',
          interleaving_bound           :: concuerror_options:bound(),
          last_had_errors = false      :: boolean(),
          log_msgs = []                :: [string()],
          output                       :: file:io_device() | 'disable',
          output_name                  :: string(),
          print_depth                  :: pos_integer(),
          rate_info = init_rate_info() :: #rate_info{},
          streams = []                 :: [{stream(), [string()]}],
          timestamp = timestamp()      :: timestamp(),
          ticker = none                :: pid() | 'none' | 'force',
          traces_explored = 0          :: non_neg_integer(),
          traces_ssb = 0               :: non_neg_integer(),
          traces_total = 0             :: non_neg_integer(),
          verbosity                    :: log_level()
         }).

%%------------------------------------------------------------------------------

-spec start(concuerror_options:options()) -> pid().

start(Options) ->
  Parent = self(),
  Ref = make_ref(),
  Fun =
    fun() ->
        State = initialize(Options),
        Parent ! Ref,
        loop(State)
    end,
  P = spawn_link(Fun),
  receive
    Ref -> P
  end.

initialize(Options) ->
  Timestamp = format_utc_timestamp(),
  [{Output, OutputName}, Graph, SymbolicNames, Processes, Verbosity] =
    get_properties(
      [output, graph, symbolic_names, processes, verbosity],
      Options),
  GraphData = graph_preamble(Graph),
  Header =
    io_lib:format(
      "~s started at ~s~n",
      [concuerror_options:version(), Timestamp]),
  Ticker =
    case showing_progress(Verbosity) of
      false -> none;
      true ->
        to_stderr("~s~n", [Header]),
        initialize_ticker(),
        ProgressHelpMsg = "Showing progress (-h progress, for details)~n",
        ?log(self(), ?linfo, ProgressHelpMsg, []),
        Self = self(),
        spawn_link(fun() -> ticker(Self) end)
    end,
  if Output =:= disable ->
      Msg = "No output report will be generated~n",
      ?log(self(), ?lwarning, Msg, []);
     true ->
      ?log(self(), ?linfo, "Writing results in ~s~n", [OutputName])
  end,
  if GraphData =:= disable -> ok;
     true ->
      {_, GraphName} = Graph,
      ?log(self(), ?linfo, "Writing graph in ~s~n", [GraphName])
  end,
  PrintableOptions =
    delete_props(
      [estimator, graph, output, processes, timers, verbosity],
      Options),
  to_file(Output, "~s", [Header]),
  to_file(
    Output,
    " Options:~n"
    "  ~p~n",
    [lists:sort(PrintableOptions)]),
  ?autoload_and_log(io_lib, self()),
  ok = setup_symbolic_names(SymbolicNames, Processes),
  #logger_state{
     estimator = ?opt(estimator, Options),
     graph_data = GraphData,
     interleaving_bound = ?opt(interleaving_bound, Options),
     output = Output,
     output_name = OutputName,
     print_depth = ?opt(print_depth, Options),
     ticker = Ticker,
     verbosity = Verbosity
    }.

get_properties(Props, PropList) ->
  get_properties(Props, PropList, []).

get_properties([], _, Acc) -> lists:reverse(Acc);
get_properties([Prop|Props], PropList, Acc) ->
  PropVal = proplists:get_value(Prop, PropList),
  get_properties(Props, PropList, [PropVal|Acc]).

delete_props([], Proplist) ->
  Proplist;
delete_props([Key|Rest], Proplist) ->
  delete_props(Rest, proplists:delete(Key, Proplist)).

-spec bound_reached(logger()) -> ok.

bound_reached(Logger) ->
  Logger ! bound_reached,
  ok.

-spec plan(logger()) -> ok.

plan(Logger) ->
  Logger ! plan,
  ok.

-spec complete(logger(), concuerror_scheduler:interleaving_result()) -> ok.

complete(Logger, Warnings) ->
  Ref = make_ref(),
  Logger ! {complete, Warnings, self(), Ref},
  receive
    Ref -> ok
  end.

-spec log(logger(), log_level(), term(), string(), [term()]) -> ok.

log(Logger, Level, Tag, Format, Data) ->
  Logger ! {log, Level, Tag, Format, Data},
  ok.

-spec finish(logger(), term()) -> concuerror:exit_status().

finish(Logger, Status) ->
  Logger ! {finish, Status, self()},
  receive
    {finished, ExitStatus} -> ExitStatus
  end.

-spec print(logger(), stream(), string()) -> ok.

print(Logger, Type, String) ->
  Logger ! {print, Type, String},
  ok.

-spec time(logger(), term()) -> ok.

time(Logger, Tag) ->
  Logger ! {time, Tag},
  ok.

-spec race(logger(), {index(), event()}, {index(), event()}) -> ok.

race(Logger, EarlyEvent, Event) ->
  Logger ! {race, EarlyEvent, Event},
  ok.

-spec set_verbosity(logger(), ?lquiet..?MAX_VERBOSITY) -> ok.

set_verbosity(Logger, Verbosity) ->
  Logger ! {set_verbosity, Verbosity},
  ok.

-spec print_log_message(log_level(), string(), [term()]) -> ok.

print_log_message(Level, Format, Args) ->
  LevelFormat = level_to_tag(Level),
  NewFormat = "* " ++ LevelFormat ++ Format,
  to_stderr(NewFormat, Args).

-spec showing_progress(log_level()) -> boolean().

showing_progress(Verbosity) ->
  (Verbosity =/= ?lquiet) andalso (Verbosity < ?ltiming).

%%------------------------------------------------------------------------------

loop(State) ->
  Message =
    receive
      {finish, _, _} = Finish ->
        receive
          M -> self() ! Finish, M
        after
          0 -> Finish
        end;
      M -> M
    end,
  loop(Message, State).

loop(Message,
     #logger_state{
        emit_logger_tips = initial,
        errors = Errors,
        traces_explored = 10,
        traces_total = TracesTotal
       } = State) ->
  case TracesTotal > 250 of
    true ->
      ManyMsg =
        "A lot of events in this test are racing. You can see such pairs"
        " by using '--show_races' true. You may want to consider reducing some"
        " parameters in your test (e.g. number of processes or events).~n",
      ?log(self(), ?ltip, ManyMsg, []);
    false -> ok
  end,
  case Errors =:= 10 of
    true ->
      ErrorsMsg =
        "Each of the first 10 interleavings explored so far had some error."
        " This can make later debugging difficult, as the generated report will"
        " include too much info. Consider refactoring your code, or using the"
        " appropriate options to filter out irrelevant errors.~n",
      ?log(self(), ?ltip, ErrorsMsg, []);
    false -> ok
  end,
  loop(Message, State#logger_state{emit_logger_tips = false});

loop(Message, State) ->
  #logger_state{
     already_emitted = AlreadyEmitted,
     errors = Errors,
     last_had_errors = LastHadErrors,
     log_msgs = LogMsgs,
     output = Output,
     output_name = OutputName,
     print_depth = PrintDepth,
     streams = Streams,
     ticker = Ticker,
     timestamp = Timestamp,
     traces_explored = TracesExplored,
     traces_ssb = TracesSSB,
     traces_total = TracesTotal,
     verbosity = Verbosity
    } = State,
  case Message of
    {time, Tag} ->
      Now = timestamp(),
      Diff = timediff(Now, Timestamp),
      Msg = "~nTimer: +~6.3fs ~s~n",
      loop(
        {log, ?ltiming, none, Msg, [Diff, Tag]},
        State#logger_state{timestamp = Now});
    {race, EarlyEvent, Event} ->
      print_depth_tip(),
      Msg =
        io_lib:format(
          "~n* ~s~n  ~s~n",
          [concuerror_io_lib:pretty_s(E, PrintDepth)
           || E <- [EarlyEvent,Event]]),
      loop({print, race, Msg}, State);
    {log, Level, Tag, Format, Data} ->
      {NewLogMsgs, NewAlreadyEmitted} =
        case Tag =/= ?nonunique andalso sets:is_element(Tag, AlreadyEmitted) of
          true -> {LogMsgs, AlreadyEmitted};
          false ->
            case Verbosity < Level of
              true  -> ok;
              false ->
                LevelFormat = level_to_tag(Level),
                NewFormat = "* " ++ LevelFormat ++ Format,
                printout(State, NewFormat, Data)
            end,
            NLM =
              case Level < ?ltiming of
                true  -> orddict:append(Level, {Format,Data}, LogMsgs);
                false -> LogMsgs
              end,
            NAE =
              case Tag =/= ?nonunique of
                true -> sets:add_element(Tag, AlreadyEmitted);
                false -> AlreadyEmitted
              end,
            {NLM, NAE}
        end,
      loop(State#logger_state{
             already_emitted = NewAlreadyEmitted,
             log_msgs = NewLogMsgs});
    {graph, Command} ->
      loop(graph_command(Command, State));
    {finish, SchedulerStatus, Scheduler} ->
      stop_ticker(Ticker),
      separator(Output, $#),
      to_file(Output, "Exploration completed!~n",[]),
      ExitStatus =
        case SchedulerStatus =:= normal of
          true ->
            case Errors =/= 0 of
              true ->
                case Verbosity =:= ?lquiet of
                  true -> ok;
                  false ->
                    Form = "Errors were found! (check ~s)~n",
                    force_printout(State, Form, [OutputName])
                end,
                error;
              false ->
                to_file(Output, "  No errors found!~n",[]),
                ok
            end;
          false -> fail
        end,
      separator(Output, $#),
      print_log_msgs(Output, LogMsgs),
      FinishTimestamp = format_utc_timestamp(),
      Format = "Done at ~s (Exit status: ~p)~n  Summary: ",
      Args = [FinishTimestamp, ExitStatus],
      to_file(Output, Format, Args),
      IntMsg = final_interleavings_message(State),
      to_file(Output, "~s", [IntMsg]),
      ok = close_files(State),
      case Verbosity =:= ?lquiet of
        true -> ok;
        false ->
          FinalFormat = Format ++ IntMsg,
          printout(State#logger_state{ticker = none}, FinalFormat, Args)
      end,
      Scheduler ! {finished, ExitStatus},
      ok;
    plan ->
      NewState = State#logger_state{traces_total = TracesTotal + 1},
      loop(NewState);
    bound_reached ->
      NewState = State#logger_state{bound_reached = true},
      loop(NewState);
    {print, Type, String} ->
      NewStreams = orddict:append(Type, String, Streams),
      NewState = State#logger_state{streams = NewStreams},
      loop(NewState);
    {set_verbosity, NewVerbosity} ->
      NewState = State#logger_state{verbosity = NewVerbosity},
      loop(NewState);
    {complete, Warn, Scheduler, Ref} ->
      %% We may have race information referring to the previous
      %% interleaving, as race analysis happens after trace logging.
      RaceInfo = [S || S = {T, _} <- Streams, T =:= race],
      case RaceInfo =:= [] of
        true -> ok;
        false ->
          case LastHadErrors of
            true -> ok;
            false ->
              %% Add missing header
              separator(Output, $#),
              to_file(Output, "Interleaving #~p~n", [TracesExplored])
          end,
          separator(Output, $-),
          print_streams(RaceInfo, Output)
      end,
      {NewErrors, NewSSB, GraphFinal, GraphColor} =
        case Warn of
          sleep_set_block ->
            %% Can only happen if --dpor is not optimal (scheduler
            %% crashes otherwise).
            case TracesSSB =:= 0 of
              true ->
                Msg =
                  "Some interleavings were 'sleep-set blocked' (SSB). This"
                  " is expected, since you are not using '--dpor"
                  " optimal', but indicates wasted effort.~n",
                ?log(self(), ?lwarning, Msg, []);
              false -> ok
            end,
            {Errors, TracesSSB + 1, "SSB", "yellow"};
          none ->
            {Errors, TracesSSB, "Ok", "limegreen"};
          {Warnings, TraceInfo} ->
            separator(Output, $#),
            to_file(Output, "Interleaving #~p~n", [TracesExplored + 1]),
            separator(Output, $-),
            to_file(Output, "Errors found:~n", []),
            print_depth_tip(),
            WarnStr =
              [concuerror_io_lib:error_s(W, PrintDepth) || W <-Warnings],
            to_file(Output, "~s", [WarnStr]),
            separator(Output, $-),
            print_streams([S || S = {T, _} <- Streams, T =/= race], Output),
            to_file(Output, "Event trace:~n", []),
            concuerror_io_lib:pretty(Output, TraceInfo, PrintDepth),
            ErrorString =
              case proplists:get_value(fatal, Warnings) of
                true -> " (Concuerror crashed)";
                undefined ->
                  case proplists:get_value(deadlock, Warnings) of
                    undefined -> "";
                    Deadlocks ->
                      Pids = [element(1, D) || D <- Deadlocks],
                      io_lib:format(" (~p blocked)", [Pids])
                  end
              end,
            {Errors + 1, TracesSSB, "Error" ++ ErrorString, "red"}
        end,
      _ =
        graph_command({status, TracesExplored, GraphFinal, GraphColor}, State),
      NewState =
        State#logger_state{
          last_had_errors = NewErrors =/= Errors,
          streams = [],
          traces_explored = TracesExplored + 1,
          traces_ssb = NewSSB,
          errors = NewErrors
         },
      Scheduler ! Ref,
      loop(NewState);
    tick ->
      clear_ticks(),
      loop(progress_refresh(State))
  end.

format_utc_timestamp() ->
  TS = os:timestamp(),
  {{Year, Month, Day}, {Hour, Minute, Second}} =
    calendar:now_to_local_time(TS),
  Mstr =
    element(Month, {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
                    "Sep", "Oct", "Nov", "Dec"}),
  io_lib:format("~2..0w ~s ~4w ~2..0w:~2..0w:~2..0w",
                [Day, Mstr, Year, Hour, Minute, Second]).

force_printout(State, Format, Data) ->
  printout(State#logger_state{ticker = force}, Format, Data).

printout(#logger_state{ticker = Ticker} = State, Format, Data)
  when Ticker =/= none ->
  progress_clear(),
  to_stderr(Format, Data),
  progress_print(State);
printout(_, Format, Data) ->
  to_stderr(Format, Data).

print_log_msgs(Output, LogMsgs) ->
  ForeachInner =
    fun({Format, Data}) ->
        to_file(Output, "* " ++ Format, Data)
    end,
  Foreach =
    fun({Type, Messages}) ->
        Header = level_to_string(Type),
        Suffix =
          case Type of
            ?linfo    -> "";
            _         -> "s"
          end,
        to_file(Output, "~s~s:~n", [Header, Suffix]),
        separator(Output, $-),
        lists:foreach(ForeachInner, Messages),
        to_file(Output, "~n", []),
        separator(Output, $#)
    end,
  lists:foreach(Foreach, LogMsgs).

level_to_tag(Level) ->
  Suffix =
    case Level > ?linfo of
      true -> "";
      false -> ": "
    end,
  level_to_string(Level) ++ Suffix.

level_to_string(Level) ->
  case Level of
    ?lerror   -> "Error";
    ?lwarning -> "Warning";
    ?ltip     -> "Tip";
    ?linfo    -> "Info";
    _ -> ""
  end.

%%------------------------------------------------------------------------------

initialize_ticker() ->
  self() ! tick,
  progress_initial_padding().

ticker(Logger) ->
  Logger ! tick,
  receive
    {stop, L} -> L ! stopped
  after
    ?TICKER_TIMEOUT -> ticker(Logger)
  end.

clear_ticks() ->
  receive
    tick -> clear_ticks()
  after
    0 -> ok
  end.

stop_ticker(Ticker) ->
  case is_pid(Ticker) of
    true ->
      Ticker ! {stop, self()},
      progress_clear(),
      receive
        stopped -> ok
      end;
    false -> ok
  end.

%%------------------------------------------------------------------------------

separator_string(Char) ->
  lists:duplicate(80, Char).

separator(Output, Char) ->
  to_file(Output, "~s~n", [separator_string(Char)]).

print_streams(Streams, Output) ->
  Fold =
    fun(Tag, Buffer, ok) ->
        print_stream(Tag, Buffer, Output),
        ok
    end,
  orddict:fold(Fold, ok, Streams).

print_stream(Tag, Buffer, Output) ->
  to_file(Output, stream_tag_to_string(Tag), []),
  to_file(Output, "~s~n", [Buffer]),
  case Tag =/= race of
    true ->
      to_file(Output, "~n", []),
      separator(Output, $-);
    false -> ok
  end.

stream_tag_to_string(standard_io) -> "Standard Output:~n";
stream_tag_to_string(standard_error) -> "Standard Error:~n";
stream_tag_to_string(race) -> "New races found:". % ~n is added by buffer

%%------------------------------------------------------------------------------

progress_initial_padding() ->
  Line = progress_line(0),
  to_stderr("~s~n", [Line]),
  to_stderr("~s~n", [progress_header(0)]),
  to_stderr("~s~n", [Line]),
  to_stderr("~n",[]).

progress_clear() ->
  delete_lines(4).

progress_refresh(State) ->
  %% No extra line afterwards to ease printing of 'running logs'.
  delete_lines(1),
  {Str, NewState} = progress_content(State),
  to_stderr("~s~n", [Str]),
  NewState.

delete_lines(0) -> ok;
delete_lines(N) ->
  to_stderr("~c[1A~c[2K\r", [27, 27]),
  delete_lines(N - 1).

progress_print(#logger_state{traces_ssb = SSB} = State) ->
  Line = progress_line(SSB),
  to_stderr("~s~n", [Line]),
  to_stderr("~s~n", [progress_header(SSB)]),
  to_stderr("~s~n", [Line]),
  {Str, _NewState} = progress_content(State),
  to_stderr("~s~n", [Str]).

progress_header(0) ->
  progress_header_common("");
progress_header(_State) ->
  progress_header_common("|     SSB ").

-spec progress_help() -> string().

progress_help() ->
  io_lib:format(
    "Errors    : Schedulings with errors~n"
    "Explored  : Schedulings already explored~n"
    "(SSB)     : Sleep set blocked schedulings (wasted effort)~n"
    "Planned   : Schedulings that will certainly be explored~n"
    "~~ Rate    : Average rate of exploration (in schedulings/s)~n"
    "Total(?)  : Estimation of total number of schedulings (see below)~n"
    "Time(?)   : Estimated time to completion (see below)~n"
    "~n"
    "Estimations:~n"
    "The total number of schedulings is estimated from the shape of the"
    " exploration tree. It has been observed to be WITHIN ONE ORDER OF"
    " MAGNITUDE of the actual number, when using default options.~n"
    "The time to completion is estimated using the estimated remaining"
    " schedulings (Total - Explored) divided by the current Rate.~n"
    , []).

progress_header_common(SSB) ->
  "    Errors |  Explored " ++ SSB ++
    "| Planned |  ~ Rate |  Total(?) | Time(?) ".

progress_line(0) ->
  progress_line_common("");
progress_line(_State) ->
  progress_line_common("-----------").

progress_line_common(SSB) ->
  "-----------------------" ++ SSB ++
    "------------------------------------------".

progress_content(State) ->
  #logger_state{
     errors = Errors,
     estimator = Estimator,
     rate_info = RateInfo,
     traces_explored = TracesExplored,
     traces_ssb = TracesSSB,
     traces_total = TracesTotal
    } = State,
  Estimation = max(concuerror_estimator:get_estimation(Estimator), TracesTotal),
  Useful = TracesExplored - TracesSSB,
  {Rate, NewRateInfo} = update_rate(RateInfo, Useful),
  Planned = TracesTotal - TracesExplored,
  SSBStr =
    case TracesSSB =:= 0 of
      true -> "";
      false -> io_lib:format(" ~7w |", [TracesSSB])
    end,
  CompletionStr =
    concuerror_estimator:estimate_completion(Estimation, TracesExplored, Rate),
  RateStr =
    case Rate of
      0    -> "  <1 /s";
      _    -> io_lib:format("~4w /s", [Rate])
    end,
  Str =
    io_lib:format(
      " ~9w | ~9w |~s ~7w | ~s | ~9w | ~s",
      [Errors, TracesExplored, SSBStr, Planned,
       RateStr, Estimation, CompletionStr]
     ),
  NewState = State#logger_state{rate_info = NewRateInfo},
  {Str, NewState}.

%%------------------------------------------------------------------------------

init_rate_info() ->
  #rate_info{
     average   = concuerror_window_average:init(0, 10),
     prev      = 0,
     timestamp = timestamp()
    }.

update_rate(RateInfo, Useful) ->
  #rate_info{
     average   = Average,
     prev      = Prev,
     timestamp = Old
    } = RateInfo,
  New = timestamp(),
  Time = timediff(New, Old),
  Diff = Useful - Prev,
  CurrentRate = Diff / (Time + 0.0001),
  {Rate, NewAverage} = concuerror_window_average:update(CurrentRate, Average),
  NewRateInfo =
    RateInfo#rate_info{
      average   = NewAverage,
      prev      = Useful,
      timestamp = New
     },
  {round(Rate), NewRateInfo}.

%%------------------------------------------------------------------------------

to_stderr(Format, Data) ->
  to_file(standard_error, Format, Data).

to_file(disable, _, _) ->
  ok;
to_file(Output, Format, Data) ->
  Msg = io_lib:format(Format, Data),
  io:format(Output, "~s", [Msg]).

%%------------------------------------------------------------------------------

final_interleavings_message(State) ->
  #logger_state{
     bound_reached = BoundReached,
     errors = Errors,
     interleaving_bound = InterleavingBound,
     traces_explored = TracesExplored,
     traces_ssb = TracesSSB,
     traces_total = TracesTotal
    } = State,
  SSB =
    case TracesSSB =:= 0 of
      true -> "";
      false -> io_lib:format(" (~p sleep-set blocked)",[TracesSSB])
    end,
  BR =
    case BoundReached of
      true -> " (the scheduling bound was reached)";
      false -> ""
    end,
  ExploreTotal = min(TracesTotal, InterleavingBound),
  io_lib:format("~p errors, ~p/~p interleavings explored~s~s~n",
                [Errors, TracesExplored, ExploreTotal, SSB, BR]).

%%------------------------------------------------------------------------------

-spec graph_set_node(logger(), unique_id(), unique_id()) -> ok.

graph_set_node(Logger, Parent, Sibling) ->
  Logger ! {graph, {set_node, Parent, Sibling}},
  ok.

-spec graph_new_node(logger(), unique_id(), index(), event()) -> ok.

graph_new_node(Logger, Ref, Index, Event) ->
  Logger ! {graph, {new_node, Ref, Index, Event}},
  ok.

-spec graph_race(logger(), unique_id(), unique_id()) -> ok.
graph_race(Logger, EarlyRef, Ref) ->
  Logger ! {graph, {race, EarlyRef, Ref}},
  ok.

graph_preamble({disable, ""}) -> disable;
graph_preamble({GraphFile, _}) ->
  to_file(
    GraphFile,
    "digraph {~n"
    "  graph [ranksep=0.3]~n"
    "  node [shape=box,width=7,fontname=Monospace]~n"
    "  \"init\" [label=\"Initial\"];~n"
    "  subgraph interleaving_1 {~n", []),
  {GraphFile, init, none}.

graph_command(_Command, #logger_state{graph_data = disable} = State) -> State;
graph_command(Command, State) ->
  #logger_state{
     graph_data = {GraphFile, Parent, Sibling} = Graph,
     print_depth = PrintDepth
    } = State,
  NewGraph =
    case Command of
      {new_node, Ref, I, Event} ->
        ErrorS =
          case Event#event.event_info of
            #exit_event{reason = normal} ->
              ",color=limegreen,penwidth=5";
            #exit_event{} ->
              ",color=red,penwidth=5";
            #builtin_event{status = {crashed, _}} ->
              ",color=orange,penwidth=5";
            _ -> ""
          end,
        print_depth_tip(),
        Label = concuerror_io_lib:pretty_s({I,Event#event{location=[]}}, PrintDepth - 19),
        to_file(
          GraphFile,
          "    \"~p\" [label=\"~s\\l\"~s];~n",
          [Ref, Label, ErrorS]),
        case Sibling =:= none of
          true ->
            to_file(GraphFile,"~s [weight=1000];~n",[ref_edge(Parent, Ref)]);
          false ->
            to_file(
              GraphFile,
              "~s [style=invis,weight=1];~n"
              "~s [constraint=false];~n",
              [ref_edge(Parent, Ref), ref_edge(Sibling, Ref)])
        end,
        {GraphFile, Ref, none};
      {race, EarlyRef, Ref} ->
        to_file(
          GraphFile,
          "~s [constraint=false, color=red, dir=back, penwidth=3, style=dashed];~n",
          [dref_edge(EarlyRef, Ref)]),
        Graph;
      {set_node, {I, _} = NewParent, NewSibling} ->
        to_file(
          GraphFile,
          "  }~n"
          "  subgraph interleaving_~w {~n",
          [I + 1]),
        {GraphFile, NewParent, NewSibling};
      {status, Count, String, Color} ->
        Final = {Count + 1, final},
        to_file(
          GraphFile,
          "    \"~p\" [label=\"~p: ~s\",style=filled,fillcolor=~s];~n"
          "~s [weight=1000];~n",
          [Final, Count+1, String, Color, ref_edge(Parent, Final)]),
        Graph
    end,
  State#logger_state{graph_data = NewGraph}.

ref_edge(RefA, RefB) ->
  io_lib:format("    \"~p\" -> \"~p\"",[RefA,RefB]).

dref_edge(RefA, RefB) ->
  io_lib:format("    \"~p\":e -> \"~p\":e",[RefA,RefB]).

close_files(State) ->
  graph_close(State),
  file_close(State#logger_state.output).

graph_close(#logger_state{graph_data = disable}) -> ok;
graph_close(#logger_state{graph_data = {GraphFile, _, _}}) ->
  to_file(
    GraphFile,
    "  }~n"
    "}~n", []),
  file_close(GraphFile).

file_close(disable) ->
  ok;
file_close(File) ->
  ok = file:close(File).

%%------------------------------------------------------------------------------

print_depth_tip() ->
  Tip = "Increase '--print_depth' if output/graph contains \"...\".~n",
  ?unique(self(), ?ltip, Tip, []).

%%------------------------------------------------------------------------------

setup_symbolic_names(SymbolicNames, Processes) ->
  case SymbolicNames of
    false -> ok;
    true ->
      print_symbolic_info(),
      concuerror_callback:setup_logger(Processes)
  end.

print_symbolic_info() ->
  Tip =
    "Showing PIDs as \"<symbolic name(/last registered name)>\""
    " ('-h symbolic_names').~n",
  ?unique(self(), ?linfo, Tip, []).
