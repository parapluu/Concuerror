%% -*- erlang-indent-level: 2 -*-

-module(concuerror_logger).

-export([run/1, complete/2, plan/1, log/3, log/4, stop/2]).

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-record(logger_state, {
          errors = 0          :: non_neg_integer(),
          modules = []        :: [atom()],
          output              :: file:io_device(),
          ticker = none       :: pid() | 'none',
          traces_explored = 0 :: non_neg_integer(),
          traces_ssb = 0      :: non_neg_integer(),
          traces_total = 0    :: non_neg_integer(),
          verbosity           :: non_neg_integer()
         }).

%%------------------------------------------------------------------------------

run(Options) ->
  Verbosity =
    case proplists:lookup(verbose, Options) of
      none -> ?DEFAULT_VERBOSITY;
      {verbose, V} -> V
    end,
  Output = proplists:get_value(output, Options),
  SymbolicNames = proplists:get_value(symbolic, Options),
  Processes = proplists:get_value(processes, Options),
  ok = setup_symbolic_names(SymbolicNames, Processes),
  PrintableOptions =
    proplists:delete(processes, proplists:delete(output, Options)),
  separator(Output, $#),
  io:format(Output,
            "Concuerror started with options:~n"
            "  ~p~n",
            [PrintableOptions]),
  separator(Output, $#),
  State = #logger_state{output = Output, verbosity = Verbosity},
  loop_entry(State).

plan(Logger) ->
  Logger ! plan.

complete(Logger, Warnings) ->
  Logger ! {complete, Warnings}.

log(Logger, Level, Format) ->
  log(Logger, Level, Format, []).

log(Logger, Level, Format, Data) ->
  Logger ! {log, self(), Level, Format, Data},
  receive
    logged -> ok
  end.

stop(Logger, Status) ->
  Logger ! {close, Status, self()},
  receive
    closed -> ok
  end.

%%------------------------------------------------------------------------------

loop_entry(#logger_state{verbosity = Verbosity} = State) ->
  Ticker =
    case Verbosity < ?linfo of
      true -> none;
      false ->
        Timestamp = format_utc_timestamp(),
        inner_diagnostic("Concuerror started at ~s~n", [Timestamp]),
        inner_diagnostic("Verbosity is set to ~p~n", [Verbosity]),
        inner_diagnostic("(Enter q to quit)~n~n"),
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
      file:close(Output),
      case Verbosity < ?linfo of
        true  -> ok;
        false ->
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
      %% Clear last progress message.
      #logger_state{
         errors = Errors,
         traces_explored = TracesExplored,
         traces_total = TracesTotal
        } = State,
      inner_diagnostic("~c[1A~c[2K\r", [27, 27]),
      inner_diagnostic(Format, Data),
      IntMsg = interleavings_message(Errors, TracesExplored, TracesTotal),
      inner_diagnostic("~s", [IntMsg])
  end.

inner_diagnostic(Format) ->
  inner_diagnostic(Format, []).

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

setup_symbolic_names(SymbolicNames, Processes) ->
  case SymbolicNames of
    false -> ok;
    true ->
      MyWrite = make_my_write(Processes),
      meck:new(io_lib, [unstick, passthrough]),
      meck:expect(io_lib, write, MyWrite),
      meck:expect(io_lib, write, fun(A) -> MyWrite(A, -1) end),
      ok
  end.

make_my_write(Processes) ->
  Logger = self(),
  fun(Term, Depth) ->
      case self() =:= Logger andalso is_pid(Term) of
        false -> meck:passthrough([Term, Depth]);
        true -> ets:lookup_element(Processes, Term, ?process_symbolic)
      end
  end.
