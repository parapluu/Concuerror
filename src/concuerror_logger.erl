%% -*- erlang-indent-level: 2 -*-

-module(concuerror_logger).

-export([run/1, complete/2, plan/1, log/5, stop/2, print/3, time/2]).

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-record(logger_state, {
          already_emitted = sets:new() :: set(),
          errors = 0                   :: non_neg_integer(),
          log_msgs = []                :: [string()],
          output                       :: file:io_device(),
          output_name                  :: string(),
          print_depth                  :: pos_integer(),
          streams = []                 :: [{stream(), [string()]}],
          timestamp = erlang:now()     :: erlang:timestamp(),
          ticker = none                :: pid() | 'none',
          traces_explored = 0          :: non_neg_integer(),
          traces_ssb = 0               :: non_neg_integer(),
          traces_total = 0             :: non_neg_integer(),
          verbosity                    :: non_neg_integer()
         }).

%%------------------------------------------------------------------------------

-spec run(options()) -> ok.

run(Options) ->
  [Verbosity,{Output, OutputName},SymbolicNames,PrintDepth,Processes,Modules] =
    concuerror_common:get_properties(
      [verbosity,output,symbolic,print_depth,processes,modules], Options),
  ok = setup_symbolic_names(SymbolicNames, Processes, Modules),
  PrintableOptions = delete_many([processes, output, modules], Options),
  separator(Output, $#),
  io:format(Output,
            "Concuerror started with options:~n"
            "  ~p~n",
            [lists:sort(PrintableOptions)]),
  separator(Output, $#),
  State =
    #logger_state{
       output = Output,
       output_name = OutputName,
       print_depth = PrintDepth,
       verbosity = Verbosity},
  loop_entry(State).

delete_many([], Proplist) ->
  Proplist;
delete_many([Key|Rest], Proplist) ->
  delete_many(Rest, proplists:delete(Key, Proplist)).

-spec plan(logger()) -> ok.

plan(Logger) ->
  Logger ! plan,
  ok.

-spec complete(logger(), concuerror_warnings()) -> ok.

complete(Logger, Warnings) ->
  Logger ! {complete, Warnings},
  ok.

-spec log(logger(), log_level(), term(), string(), [term()]) -> ok.

log(Logger, Level, Tag, Format, Data) ->
  Logger ! {log, Level, Tag, Format, Data},
  ok.

-spec stop(logger(), term()) -> ok.

stop(Logger, Status) ->
  Logger ! {close, Status, self()},
  receive
    closed -> ok
  end.

-spec print(logger(), stream(), string()) -> ok.

print(Logger, Type, String) ->
  Logger ! {print, Type, String},
  ok.

-spec time(logger(), term()) -> ok.

time(Logger, Tag) ->
  Logger ! {time, Tag},
  ok.

%%------------------------------------------------------------------------------

loop_entry(State) ->
  #logger_state{output_name = OutputName, verbosity = Verbosity} = State,
  Ticker =
    case Verbosity < ?lprogress of
      true -> none;
      false ->
        Timestamp = format_utc_timestamp(),
        inner_diagnostic("Concuerror started at ~s~n", [Timestamp]),
        inner_diagnostic("Writing results in ~s~n", [OutputName]),
        inner_diagnostic("Verbosity is set to ~p~n~n~n", [Verbosity]),
        Self = self(),
        spawn_link(fun() -> ticker(Self) end)
    end,
  loop(State#logger_state{ticker = Ticker}).

loop(State) ->
  #logger_state{
     already_emitted = AlreadyEmitted,
     errors = Errors,
     log_msgs = LogMsgs,
     output = Output,
     print_depth = PrintDepth,
     streams = Streams,
     ticker = Ticker,
     timestamp = Timestamp,
     traces_explored = TracesExplored,
     traces_total = TracesTotal,
     verbosity = Verbosity
    } = State,
  receive
    {time, Tag} ->
      Now = erlang:now(),
      Diff = timer:now_diff(Now, Timestamp) / 1000000,
      Msg = "Timer: +~5.2fs ~s~n",
      self() ! {log, ?ltiming, none, Msg, [Diff, Tag]},
      loop(State#logger_state{timestamp = Now});
    {log, Level, Tag, Format, Data} ->
      {NewLogMsgs, NewAlreadyEmitted} =
        case Tag =/= ?nonunique andalso sets:is_element(Tag, AlreadyEmitted) of
          true -> {LogMsgs, AlreadyEmitted};
          false ->
            case Verbosity < Level of
              true  -> ok;
              false -> diagnostic(State, Format, Data)
            end,
            NLM =
              case Level =< ?linfo of
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
    {close, Status, Scheduler} ->
      case is_pid(Ticker) of
        true -> Ticker ! stop;
        false -> ok
      end,
      case Errors =:= 0 of
        true -> io:format(Output, "  No errors found!~n",[]);
        false -> ok
      end,
      separator(Output, $#),
      print_log_msgs(Output, LogMsgs),
      Format = "Done! (Exit status: ~p)~n  Summary: ",
      IntMsg = interleavings_message(Errors, TracesExplored, TracesTotal),
      io:format(Output, Format, [Status]),
      io:format(Output, "~s", [IntMsg]),
      ok = file:close(Output),
      case Verbosity < ?lprogress of
        true -> ok;
        false ->
          ForcePrintState = State#logger_state{verbosity = ?lprogress},
          diagnostic(ForcePrintState, Format, [Status])
      end,
      Scheduler ! closed,
      ok;
    plan ->
      NewState = State#logger_state{traces_total = TracesTotal + 1},
      update_on_ticker(NewState),
      loop(NewState);
    {print, Type, String} ->
      NewStreams = orddict:append(Type, String, Streams),
      NewState = State#logger_state{streams = NewStreams},
      loop(NewState);
    {complete, Warn} ->
      NewErrors =
        case Warn of
          none -> Errors;
          {Warnings, TraceInfo} ->
            NE = Errors + 1,
            case NE > 1 of
              true -> separator(Output, $#);
              false -> ok
            end,
            io:format(Output, "Erroneous interleaving ~p:~n", [NE]),
            WarnStr =
              [concuerror_printer:error_s(W, PrintDepth) || W <-Warnings],
            io:format(Output, "~s", [WarnStr]),
            separator(Output, $-),
            print_streams(Streams, Output),
            io:format(Output, "Interleaving info:~n", []),
            concuerror_printer:pretty(Output, TraceInfo, PrintDepth),
            NE
        end,
      NewState =
        State#logger_state{
          streams = [],
          traces_explored = TracesExplored + 1,
          errors = NewErrors
         },
      update_on_ticker(NewState),
      loop(NewState)
  end.

format_utc_timestamp() ->
  TS = os:timestamp(),
  {{Year, Month, Day}, {Hour, Minute, Second}} =
    calendar:now_to_universal_time(TS),
  Mstr =
    element(Month, {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
                    "Sep", "Oct", "Nov", "Dec"}),
  io_lib:format("~2..0w ~s ~4w ~2..0w:~2..0w:~2..0w",
                [Day, Mstr, Year, Hour, Minute, Second]).

diagnostic(State, Format) ->
  diagnostic(State, Format, []).

diagnostic(State, Format, Data) ->
  #logger_state{
     errors = Errors,
     traces_explored = TracesExplored,
     traces_total = TracesTotal,
     verbosity = Verbosity
    } = State,
  case Verbosity =/= ?lprogress of
    true ->
      inner_diagnostic(Format, Data);
    false ->
      IntMsg = interleavings_message(Errors, TracesExplored, TracesTotal),
      clear_progress(),
      inner_diagnostic(Format, Data),
      inner_diagnostic("~s", [IntMsg])
  end.

print_log_msgs(Output, LogMsgs) ->
  ForeachInner = fun({Format, Data}) -> io:format(Output,Format,Data) end,
  Foreach =
    fun({Type, Messages}) ->
        Header =
          case Type of
            ?lerror   -> "Errors";
            ?lwarning -> "Warnings";
            ?linfo    -> "Info"
          end,
        io:format(Output, "Concuerror ~s:~n", [Header]),
        separator(Output, $-),
        lists:foreach(ForeachInner, Messages),
        separator(Output, $#)
    end,
  lists:foreach(Foreach, LogMsgs).

clear_progress() ->
  inner_diagnostic("~c[1A~c[2K\r", [27, 27]).

inner_diagnostic(Format, Data) ->
  io:format(standard_error, Format, Data).

ticker(Logger) ->
  Logger ! tick,
  receive
    stop -> ok
  after
    ?TICKER_TIMEOUT -> ticker(Logger)
  end.

update_on_ticker(State) ->
  case has_tick() of
    true  -> diagnostic(State, "");
    false -> ok
  end.

has_tick() ->
  has_tick(false).

has_tick(Result) ->
  receive
    tick -> has_tick(true)
  after
    0 -> Result
  end.

separator(Output, Char) ->
  io:format(Output, "~s~n", [lists:duplicate(80, Char)]).

print_streams(Streams, Output) ->
  Fold =
    fun(Tag, Buffer, ok) ->
        print_stream(Tag, Buffer, Output),
        ok
    end,
  orddict:fold(Fold, ok, Streams).

print_stream(Tag, Buffer, Output) ->
  io:format(Output, "Text printed to ~s:~n", [tag_to_filename(Tag)]),
  io:format(Output, "~s~n", [lists:reverse(Buffer)]),
  separator(Output, $-).

tag_to_filename(standard_io) -> "Standard Output";
tag_to_filename(standard_error) -> "Standard Error";
tag_to_filename(Filename) when is_list(Filename) -> Filename.

interleavings_message(Errors, TracesExplored, TracesTotal) ->
  io_lib:format("~p errors, ~p/~p interleavings explored~n",
                [Errors, TracesExplored, TracesTotal]).

%%------------------------------------------------------------------------------

setup_symbolic_names(SymbolicNames, Processes, Modules) ->
  case SymbolicNames of
    false -> ok;
    true ->
      put(concuerror_info, {logger, Processes, Modules}),
      ok
  end.
