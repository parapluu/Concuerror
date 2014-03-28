%% -*- erlang-indent-level: 2 -*-

-module(concuerror_logger).

-export([run/1, complete/2, plan/1, log/3, log/4, stop/2]).

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-record(logger_state, {
          errors = 0          :: non_neg_integer(),
          modules = []        :: [atom()],
          output              :: file:io_device(),
          output_name         :: string(),
          ticker = none       :: pid() | 'none',
          traces_explored = 0 :: non_neg_integer(),
          traces_ssb = 0      :: non_neg_integer(),
          traces_total = 0    :: non_neg_integer(),
          verbosity           :: non_neg_integer()
         }).

%%------------------------------------------------------------------------------

-spec run(options()) -> ok.

run(Options) ->
  [Verbosity,{Output, OutputName},SymbolicNames,Processes,Modules] =
    concuerror_common:get_properties(
      [verbose,output,symbolic,processes,modules], Options),
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

-spec log(logger(), log_level(), string()) -> ok.

log(Logger, Level, Format) ->
  log(Logger, Level, Format, []).

-spec log(logger(), log_level(), string(), [term()]) -> ok.

log(Logger, Level, Format, Data) ->
  Logger ! {log, self(), Level, Format, Data},
  receive
    logged -> ok
  end.

-spec stop(logger(), term()) -> ok.

stop(Logger, Status) ->
  Logger ! {close, Status, self()},
  receive
    closed -> ok
  end.

%%------------------------------------------------------------------------------

loop_entry(State) ->
  #logger_state{output_name = OutputName, verbosity = Verbosity} = State,
  Ticker =
    case Verbosity < ?linfo of
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
     errors = Errors,
     modules = Modules,
     output = Output,
     ticker = Ticker,
     traces_explored = TracesExplored,
     traces_total = TracesTotal,
     verbosity = Verbosity
    } = State,
  receive
    {log, Pid, Level, Format, Data} ->
      case Verbosity < Level of
        true  -> ok;
        false -> diagnostic(State, Format, Data)
      end,
      Pid ! logged,
      loop(State);
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
      Format = "Done! (Exit status: ~p)~n  Summary: ",
      IntMsg = interleavings_message(Errors, TracesExplored, TracesTotal),
      io:format(Output, Format, [Status]),
      io:format(Output, "~s", [IntMsg]),
      ok = file:close(Output),
      case Verbosity < ?linfo of
        true  -> ok;
        false ->
          clear_progress(),
          inner_diagnostic(Format, [Status]),
          IntMsg = interleavings_message(Errors, TracesExplored, TracesTotal),
          inner_diagnostic("~s", [IntMsg])
      end,
      Scheduler ! closed,
      ok;
    plan ->
      NewState = State#logger_state{traces_total = TracesTotal + 1},
      update_on_ticker(NewState),
      loop(NewState);
    {complete, Warn} ->
      %% XXX: Print error info
      %% io:format("\n"),
      %% ReversedTrace = lists:reverse(UpdatedState#scheduler_state.trace),
      %% Map = fun(#trace_state{done = [A|_]}) -> A end,
      %%
      %% io:format("\n"),
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
            WarnStr = [concuerror_printer:error_s(W) || W <-Warnings],
            io:format(Output, "~s", [WarnStr]),
            separator(Output, $-),
            io:format(Output, "Interleaving info:~n", []),
            concuerror_printer:pretty(Output, TraceInfo),
            NE
        end,
      NewState =
        State#logger_state{
          traces_explored = TracesExplored + 1,
          errors = NewErrors
         },
      update_on_ticker(NewState),
      loop(NewState);
    {module, M} ->
      case ordsets:is_element(M, Modules) of
        true -> loop(State);
        false ->
          case Verbosity < ?ldebug of
            true  -> ok;
            false -> diagnostic(State, "Including ~p~n", [M])
          end,
          loop(State#logger_state{modules = ordsets:add_element(M, Modules)})
      end
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
  #logger_state{verbosity = Verbosity} = State,
  case Verbosity =/= ?linfo of
    true  -> inner_diagnostic(Format, Data);
    false ->
      #logger_state{
         errors = Errors,
         traces_explored = TracesExplored,
         traces_total = TracesTotal
        } = State,
      clear_progress(),
      inner_diagnostic(Format, Data),
      IntMsg = interleavings_message(Errors, TracesExplored, TracesTotal),
      inner_diagnostic("~s", [IntMsg])
  end.

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
