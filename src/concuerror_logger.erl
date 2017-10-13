%% -*- erlang-indent-level: 2 -*-

-module(concuerror_logger).

-export([start/1, complete/2, plan/1, log/5, race/3, finish/2, print/3, time/2]).
-export([bound_reached/1, set_verbosity/2]).
-export([graph_set_node/3, graph_new_node/5, graph_race/3]).

-include("concuerror.hrl").

-type log_level() :: ?lquiet..?MAX_VERBOSITY.

-define(TICKER_TIMEOUT, 500).
%%------------------------------------------------------------------------------

-type stream() :: 'standard_io' | 'standard_error' | 'race' | file:filename().
-type graph_data() ::
        {file:io_device(), reference() | 'init', reference() | 'none'}.

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

-record(logger_state, {
          already_emitted = sets:new() :: unique_ids(),
          bound_reached = false        :: boolean(),
          emit_logger_tips = initial   :: 'initial' | 'false',
          errors = 0                   :: non_neg_integer(),
          graph_data                   :: graph_data() | 'undefined',
          interleaving_bound           :: concuerror_options:bound(),
          log_msgs = []                :: [string()],
          output                       :: file:io_device(),
          output_name                  :: string(),
          print_depth                  :: pos_integer(),
          rate_timestamp = timestamp() :: timestamp(),
          rate_prev = 0                :: non_neg_integer(),
          rate_width = 3               :: non_neg_integer(),
          streams = []                 :: [{stream(), [string()]}],
          timestamp = timestamp()      :: timestamp(),
          ticker = none                :: pid() | 'none' | 'show',
          traces_explored = 0          :: non_neg_integer(),
          traces_ssb = 0               :: non_neg_integer(),
          traces_total = 0             :: non_neg_integer(),
          verbosity                    :: log_level()
         }).

%%------------------------------------------------------------------------------

-spec start(concuerror_options:options()) -> pid().

start(Options) ->
  Parent = self(),
  Fun =
    fun() ->
        State = initialize(Options),
        Parent ! logger_ready,
        loop(State)
    end,
  P = spawn_link(Fun),
  receive
    logger_ready -> P
  end.

initialize(Options) ->
  Timestamp = format_utc_timestamp(),
  [{Output, OutputName}, SymbolicNames, Processes, Verbosity] =
    get_properties([output, symbolic_names, processes, verbosity], Options),
  ?autoload_and_log(io_lib, self()),
  ok = setup_symbolic_names(SymbolicNames, Processes),
  Graph = ?opt(graph, Options),
  Header =
    io_lib:format(
      "~s started at ~s~n",
      [concuerror_options:version(), Timestamp]),
  Ticker =
    case (Verbosity =:= ?lquiet) orelse (Verbosity >= ?ltiming) of
      true -> none;
      false ->
        to_stderr("~s", [Header]),
        to_stderr("~nWriting results in ~s~n", [OutputName]),
        if Graph =:= undefined -> ok;
           true ->
            {_, GraphName} = Graph,
            to_stderr("Writing graph in ~s~n", [GraphName])
        end,
        to_stderr("~n~n",[]),
        Self = self(),
        spawn_link(fun() -> ticker(Self) end)
    end,
  PrintableOptions =
    delete_props(
      [graph, output, processes, timers, verbosity],
      Options),
  io:format(Output, "~s", [Header]),
  io:format(
    Output,
    " Options:~n"
    "  ~p~n",
    [lists:sort(PrintableOptions)]),
  GraphData = graph_preamble(Graph),
  #logger_state{
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
  Msg = "Some interleavings were not considered due to schedule bounding.~n",
  ?unique(Logger, ?lwarning, Msg, []),
  ?debug(Logger, "OVER BOUND~n",[]),
  Logger ! bound_reached,
  ok.

-spec plan(logger()) -> ok.

plan(Logger) ->
  Logger ! plan,
  ok.

-spec complete(logger(), concuerror_warnings()) -> ok.

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
      Msg = "~nTimer: +~5.2fs ~s~n",
      loop(
        {log, ?ltiming, none, Msg, [Diff, Tag]},
        State#logger_state{timestamp = Now});
    {race, EarlyEvent, Event} ->
      print_depth_tip(),
      Msg =
        io_lib:format(
          "* ~s~n  ~s~n~n",
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
                LevelFormat = verbosity_to_tag(Level),
                NewFormat = LevelFormat ++ Format,
                printout(State, "* " ++ NewFormat, Data)
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
      case is_pid(Ticker) of
        true -> Ticker ! stop;
        false -> ok
      end,
      separator(Output, $#),
      io:format(Output, "Exploration completed!~n",[]),
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
                io:format(Output, "  No errors found!~n",[]),
                ok
            end;
          false -> fail
        end,
      separator(Output, $#),
      print_log_msgs(Output, LogMsgs),
      FinishTimestamp = format_utc_timestamp(),
      Format = "Done at ~s (Exit status: ~p)~n  Summary: ",
      Args = [FinishTimestamp, ExitStatus],
      io:format(Output, Format, Args),
      IntMsg = interleavings_message(State),
      io:format(Output, "~s", [IntMsg]),
      ok = file:close(Output),
      ok = graph_close(State),
      case Verbosity =:= ?lquiet of
        true -> ok;
        false ->
          force_printout(State, Format, Args)
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
      {NewErrors, NewSSB, GraphFinal, GraphColor} =
        case Warn of
          sleep_set_block ->
            {Errors, TracesSSB + 1, "SSB", "yellow"};
          none ->
            RaceInfo = [S || S = {T, _} <- Streams, T =:= race],
            case RaceInfo =:= [] of
              true -> ok;
              false ->
                separator(Output, $#),
                io:format(Output, "Interleaving #~p~n", [TracesExplored + 1]),
                print_streams(RaceInfo, Output)
            end,
            {Errors, TracesSSB, "Ok", "limegreen"};
          {Warnings, TraceInfo} ->
            separator(Output, $#),
            io:format(Output, "Interleaving #~p~n", [TracesExplored + 1]),
            separator(Output, $-),
            io:format(Output, "Errors found:~n", []),
            print_depth_tip(),
            WarnStr =
              [concuerror_io_lib:error_s(W, PrintDepth) || W <-Warnings],
            io:format(Output, "~s", [WarnStr]),
            separator(Output, $-),
            print_streams([S || S = {T, _} <- Streams, T =/= race], Output),
            io:format(Output, "Event trace:~n", []),
            concuerror_io_lib:pretty(Output, TraceInfo, PrintDepth),
            print_streams([S || S = {T, _} <- Streams, T =:= race], Output),
            ErrorString =
              case proplists:get_value(fatal, Warnings) of
                true -> " (Concuerror crashed)";
                undefined ->
                  case proplists:get_value(deadlock, Warnings) of
                    undefined -> "";
                    Ps -> io_lib:format(" (~p blocked)", [[P || {P,_} <- Ps]])
                  end
              end,
            {Errors + 1, TracesSSB, "Error" ++ ErrorString, "red"}
        end,
      _ =
        graph_command({status, TracesExplored, GraphFinal, GraphColor}, State),
      NewState =
        State#logger_state{
          streams = [],
          traces_explored = TracesExplored + 1,
          traces_ssb = NewSSB,
          errors = NewErrors
         },
      Scheduler ! Ref,
      loop(NewState);
    tick ->
      clear_ticks(),
      NewState = update_on_ticker(State),
      loop(NewState)
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
  printout(State#logger_state{ticker = show}, Format, Data).

printout(#logger_state{ticker = Ticker} = State, Format, Data)
  when Ticker =/= none ->
  IntMsg = interleavings_message(State),
  clear_progress(),
  to_stderr(Format, Data),
  to_stderr("~s", [IntMsg]);
printout(_, Format, Data) ->
  to_stderr(Format, Data).

print_log_msgs(Output, LogMsgs) ->
  ForeachInner =
    fun({Format, Data}) ->
        io:format(Output, "* " ++ Format, Data)
    end,
  Foreach =
    fun({Type, Messages}) ->
        Header = verbosity_to_string(Type),
        Suffix =
          case Type of
            ?linfo    -> "";
            _         -> "s"
          end,
        io:format(Output, "~s~s:~n", [Header, Suffix]),
        separator(Output, $-),
        lists:foreach(ForeachInner, Messages),
        io:format(Output, "~n", []),
        separator(Output, $#)
    end,
  lists:foreach(Foreach, LogMsgs).

verbosity_to_tag(Level) ->
  Suffix =
    case Level > ?linfo of
      true -> "";
      false -> ": "
    end,
  verbosity_to_string(Level) ++ Suffix.

verbosity_to_string(Level) ->
  case Level of
    ?lerror   -> "Error";
    ?lwarning -> "Warning";
    ?ltip     -> "Tip";
    ?linfo    -> "Info";
    _ -> ""
  end.

clear_progress() ->
  to_stderr("~c[1A~c[2K\r", [27, 27]).

to_stderr(Format, Data) ->
  io:format(standard_error, Format, Data).

ticker(Logger) ->
  Logger ! tick,
  receive
    stop -> ok
  after
    ?TICKER_TIMEOUT -> ticker(Logger)
  end.

clear_ticks() ->
  receive
    tick -> clear_ticks()
  after
    0 -> ok
  end.

update_on_ticker(State) ->
  {Rate, NewState} = update_rate(State),
  printout(State, "~s", [Rate]),
  NewState.

update_rate(State) ->
  #logger_state{
     rate_timestamp = Old,
     rate_prev = Prev,
     rate_width = OldWidth,
     traces_explored = Current,
     traces_ssb = TracesSSB
    } = State,
  New = timestamp(),
  Time = timediff(New, Old),
  Useful = Current - TracesSSB,
  Diff = Useful - Prev,
  Rate = (Diff / (Time + 0.0001)) + 0.01,
  Width = max(OldWidth, trunc(math:log10(Rate)) + 3),
  WidthStr = [$0 + Width],
  RateStr = io_lib:format("(~"++WidthStr++".1f/s) ", [Rate]),
  NewState =
    State#logger_state{
      rate_timestamp = New,
      rate_prev = Useful,
      rate_width = Width},
  {RateStr, NewState}.

separator_string(Char) ->
  lists:duplicate(80, Char).

separator(Output, Char) ->
  io:format(Output, "~s~n", [separator_string(Char)]).

print_streams(Streams, Output) ->
  Fold =
    fun(Tag, Buffer, ok) ->
        print_stream(Tag, Buffer, Output),
        ok
    end,
  orddict:fold(Fold, ok, Streams).

print_stream(Tag, Buffer, Output) ->
  io:format(Output, tag_to_filename(Tag) ++ ":~n", []),
  io:format(Output, "~s~n", [Buffer]),
  case Tag =/= race of
    true ->
      io:format(Output, "~n", []),
      separator(Output, $-);
    false -> ok
  end.

tag_to_filename(standard_io) -> "Standard Output";
tag_to_filename(standard_error) -> "Standard Error";
tag_to_filename(race) ->
  separator_string($-) ++
    "~nNew races found";
tag_to_filename(Filename) when is_list(Filename) ->
  io_lib:format("Text printed to ~s", [Filename]).

interleavings_message(State) ->
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

-spec graph_set_node(logger(), reference(), reference()) -> ok.

graph_set_node(Logger, Parent, Sibling) ->
  Logger ! {graph, {set_node, Parent, Sibling}},
  ok.

-spec graph_new_node(logger(), reference(), index(), event(), integer()) -> ok.

graph_new_node(Logger, Ref, Index, Event, BoundConsumed) ->
  Logger ! {graph, {new_node, Ref, Index, Event, BoundConsumed}},
  ok.

-spec graph_race(logger(), reference(), reference()) -> ok.
graph_race(Logger, EarlyRef, Ref) ->
  Logger ! {graph, {race, EarlyRef, Ref}},
  ok.

graph_preamble(undefined) -> undefined;
graph_preamble({GraphFile, _}) ->
  io:format(
    GraphFile,
    "digraph {~n"
    "  graph [ranksep=0.3]~n"
    "  node [shape=box,width=7,fontname=Monospace]~n"
    "  init [label=\"Initial\"];~n"
    "  subgraph {~n", []),
  {GraphFile, init, none}.

graph_command(_Command, #logger_state{graph_data = undefined} = State) -> State;
graph_command(Command, State) ->
  #logger_state{
     graph_data = {GraphFile, Parent, Sibling} = Graph,
     print_depth = PrintDepth
    } = State,
  NewGraph =
    case Command of
      {new_node, Ref, I, Event, BoundConsumed} ->
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
        EnabledLabel =
          case BoundConsumed =:= 0 of
            true -> "    ";
            false -> io_lib:format("!~2w",[BoundConsumed])
          end,
        io:format(
          GraphFile,
          "    \"~p\" [label=\"~s ~s\\l\"~s];~n",
          [Ref, EnabledLabel, Label, ErrorS]),
        case Sibling =:= none of
          true ->
            io:format(GraphFile,"~s[weight=1000];~n",[ref_edge(Parent, Ref)]);
          false ->
            io:format(
              GraphFile,
              "~s[style=invis,weight=1];~n"
              "~s[constraint=false];~n",
              [ref_edge(Parent, Ref), ref_edge(Sibling, Ref)])
        end,
        {GraphFile, Ref, none};
      {race, EarlyRef, Ref} ->
        io:format(
          GraphFile,
          "~s[constraint=false, color=red, dir=back, penwidth=3, style=dashed];~n",
          [dref_edge(EarlyRef, Ref)]),
        Graph;
      {set_node, NewParent, NewSibling} ->
        io:format(
          GraphFile,
          "  }~n"
          "  subgraph{~n",
          []),
        {GraphFile, NewParent, NewSibling};
      {status, Count, String, Color} ->
        Ref = make_ref(),
        io:format(
          GraphFile,
          "    \"~p\" [label=\"~p: ~s\",style=filled,fillcolor=~s];~n"
          "~s[weight=1000];~n",
          [Ref, Count+1, String, Color, ref_edge(Parent, Ref)]),
        Graph
    end,
  State#logger_state{graph_data = NewGraph}.

ref_edge(RefA, RefB) ->
  io_lib:format("    \"~p\" -> \"~p\"",[RefA,RefB]).

dref_edge(RefA, RefB) ->
  io_lib:format("    \"~p\":e -> \"~p\":e",[RefA,RefB]).

graph_close(#logger_state{graph_data = undefined}) -> ok;
graph_close(#logger_state{graph_data = {GraphFile, _, _}}) ->
  io:format(
    GraphFile,
    "  }~n"
    "}~n", []),
  file:close(GraphFile).

%%------------------------------------------------------------------------------

print_depth_tip() ->
  Tip = "Increase '--print_depth' if output/graph contains \"...\".~n",
  ?unique(self(), ?ltip, Tip, []).

%%------------------------------------------------------------------------------

setup_symbolic_names(SymbolicNames, Processes) ->
  case SymbolicNames of
    false -> ok;
    true -> concuerror_callback:setup_logger(Processes)
  end.
