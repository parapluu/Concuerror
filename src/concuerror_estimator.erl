%% -*- erlang-indent-level: 2 -*-

%% @doc The estimator process is being updated by the scheduler and
%%      polled independently by the logger. It stores a lightweight
%%      representation/summarry of the exploration tree and uses it to
%%      give an estimation of the total size.

-module(concuerror_estimator).

-behaviour(gen_server).

%% API
-export([start_link/1, finish/1, restart/2, plan/2, poll/1]).

%% Other
-export([estimate_completion/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%------------------------------------------------------------------------------

-export_type([estimator/0, estimation/0]).

-type estimator()  :: pid() | 'none'.
-type estimation() :: 'unknown' | pos_integer().

%%------------------------------------------------------------------------------

-define(SERVER, ?MODULE).

%%------------------------------------------------------------------------------

-include("concuerror.hrl").

-ifdef(BEFORE_OTP_17).
-type explored() :: dict().
-type planned()  :: dict().
-else.
-type explored() :: dict:dict(index(), [pos_integer()]).
-type planned()  :: dict:dict(index(), pos_integer()).
-endif.

%%------------------------------------------------------------------------------

-define(COUNTDOWN, 50).

-record(state, {
          countdown   = ?COUNTDOWN :: non_neg_integer(),
          delay_bound = false      :: boolean(),
          estimation  = unknown    :: estimation(),
          explored    = dict:new() :: explored(),
          planned     = dict:new() :: planned()
         }).

%%%=============================================================================
%%% API
%%%=============================================================================

-type call() :: 'poll'.
-type cast() ::  {'restart' | 'plan', index()}.

%%%=============================================================================

-spec start_link(concuerror_options:options()) -> estimator().

start_link(Options) ->
  Verbosity = ?opt(verbosity, Options),
  case
    (Verbosity =:= ?lquiet) orelse
    (Verbosity >= ?ltiming)
  of
    true -> none;
    false ->
      DelayBound = ?opt(scheduling_bound_type, Options) =:= delay,
      {ok, Pid} = gen_server:start_link(?MODULE, DelayBound, []),
      Pid
  end.

%%------------------------------------------------------------------------------

-spec finish(estimator()) -> 'ok'.

finish(none) -> ok;
finish(Estimator) ->
  gen_server_stop(Estimator).

-ifdef(BEFORE_OTP_18).

gen_server_stop(Server) ->
  M = monitor(process, Server),
  gen_server:cast(Server, stop),
  receive
    {'DOWN', M, process, Server, _} -> ok
  end.

-else.

gen_server_stop(Server) ->
  gen_server:stop(Server).

-endif.

%%------------------------------------------------------------------------------

-spec restart(estimator(), index()) -> 'ok'.

restart(none, _Index) -> ok;
restart(Estimator, Index) ->
  gen_server:cast(Estimator, {restart, Index}).

%%------------------------------------------------------------------------------

-spec plan(estimator(), index()) -> 'ok'.

plan(none, _Index) -> ok;
plan(Estimator, Index) ->
  gen_server:cast(Estimator, {plan, Index}).

%%------------------------------------------------------------------------------

-spec poll(estimator()) -> estimation().

poll(none) -> -1;
poll(Estimator) ->
  gen_server:call(Estimator, poll).

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

-spec init(boolean()) -> {'ok', #state{}}.

init(DelayBound) ->
  {ok, #state{delay_bound = DelayBound}}.

%%------------------------------------------------------------------------------

-spec handle_call(call(), _From, #state{}) -> {'reply', term(), #state{}}.

handle_call(poll, _From, #state{estimation = Estimation} = State) ->
  {reply, Estimation, State}.

%%------------------------------------------------------------------------------

-spec handle_cast(cast(), #state{}) -> {'noreply', #state{}}.

handle_cast(stop, State) ->
  {stop, normal, State};
handle_cast({plan, I}, State) ->
  #state{planned = Planned} = State,
  NewPlanned = dict:update_counter(I, 1, Planned),
  {noreply, State#state{planned = NewPlanned}};
handle_cast({restart, I}, State) ->
  #state{explored = Explored, planned = Planned} = State,
  SmallerFun = fun(K) -> K =< I end,
  Marks = all_keys(Explored, dict:new()),
  Larger = lists:dropwhile(SmallerFun, Marks),
  NewPlanned =
    case dict:find(I, Planned) of
      {ok, Value} when Value > 0 ->
        dict:update_counter(I, -1, Planned);
      _ ->
        AllPlanned = lists:sort(dict:fetch_keys(Planned)),
        [NI|_] = lists:reverse(lists:takewhile(SmallerFun, AllPlanned)),
        dict:update_counter(NI, -1, Planned)
    end,
  FoldFun =
    fun(M, {Total, E}) ->
        Sum = lists:sum(dict:fetch(M, E)),
        NE = dict:erase(M, E),
        {Total + Sum, NE}
    end,
  {Sum, OutExplored} = lists:foldl(FoldFun, {1, Explored}, Larger),
  NewExplored = dict:append(I, Sum, OutExplored),
  NewState = State#state{explored = NewExplored, planned = NewPlanned},
  FinalState = countdown(NewState),
  {noreply, FinalState}.

%%------------------------------------------------------------------------------

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.

handle_info(_Info, State) ->
  {noreply, State}.

%%------------------------------------------------------------------------------

-spec terminate('normal', #state{}) -> 'ok'.

terminate(normal, _State) ->
  ok.

%%------------------------------------------------------------------------------

-spec code_change(term(), #state{}, term()) -> {'ok', #state{}}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

countdown(#state{countdown = Countdown} = State) ->
  case Countdown > 0 of
    true -> State#state{countdown = Countdown - 1};
    false ->
      {Estimation, NewState} = estimate(State),
      NewState#state{countdown = ?COUNTDOWN, estimation = Estimation}
  end.

all_keys(Explored, Planned) ->
  [ExploredKeys, PlannedKeys] =
    [ordsets:from_list(dict:fetch_keys(D)) ||
      D <- [Explored, Planned]],
  ordsets:union(ExploredKeys, PlannedKeys).

estimate(State) ->
  #state{
     delay_bound = DelayBound,
     explored = Explored,
     planned = Planned
    } = State,
  CleanupFun = fun(_, V) -> V > 0 end,
  NewPlanned = dict:filter(CleanupFun, Planned),
  Marks = all_keys(Explored, NewPlanned),
  NewState = State#state{planned = NewPlanned},
  FoldFun =
    fun(M, L) ->
        AllExplored =
          case dict:find(M, Explored) of
            error -> [L];
            {ok, More} -> [L|More]
          end,
        Sum = lists:sum(AllExplored),
        AllPlanned =
          case dict:find(M, NewPlanned) of
            error -> 0;
            {ok, P} ->
              case DelayBound of
                false -> round(P*Sum/length(AllExplored));
                true ->
                  Min = max(1, lists:min(AllExplored)),
                  round(scale(P, Min))
              end
          end,
        Sum + AllPlanned
    end,
  AllButLast = lists:reverse(Marks),
  Sum = lists:foldl(FoldFun, 1, AllButLast),
  {Sum, NewState}.

scale(0, _Acc) -> 0;
scale(N, Acc) ->
  NewAcc = Acc / 2,
  NewAcc + scale(N - 1, NewAcc).

%%%=============================================================================
%%% Other functions
%%%=============================================================================

%% @doc This code is purely functional and does not use/depend on the
%%      estimator process.

-spec estimate_completion(term(), term(), term()) -> string().

estimate_completion(Estimated, Explored, Rate)
  when not is_number(Estimated);
       not is_number(Explored);
       not is_number(Rate) ->
  "unknown";
estimate_completion(Estimated, Explored, Rate) ->
  Remaining = Estimated - Explored,
  Completion = round(Remaining/(Rate + 0.001)),
  " " ++ estimated_completion_to_string(Completion).

-type posint() :: pos_integer().
-type split_fun() :: fun((posint()) -> posint() | {posint(), posint()}).

-record(estimated_completion_formatter, {
          threshold  = 1       :: posint() | 'infinity',
          rounding   = 1       :: posint(),
          split_fun            :: split_fun(),
          one_format = "~w"    :: string(),
          two_format = "~w ~w" :: string()
         }).

estimated_completion_formatters() ->
  SecondsSplitFun = fun(_) -> 5 end,
  SecondsECF =
    #estimated_completion_formatter{
       threshold  = 5 * 60,
       rounding   = 60,
       split_fun  = SecondsSplitFun,
       one_format = "   <~pm"
      },
  MinutesSplitFun =
    fun(Minutes) ->
        case Minutes < 60 of
          true -> Minutes;
          false -> {Minutes div 60, Minutes rem 60}
        end
    end,
  MinutesECF =
    #estimated_completion_formatter{
       threshold  = 60,
       rounding   = 15,
       split_fun  = MinutesSplitFun,
       one_format = "   ~2wm",
       two_format = "~2wh~2..0wm"
      },
  QuartersSplitFun =
    fun(Quarters) -> {Quarters div 4, (Quarters rem 4) * 15} end,
  QuartersECF =
    #estimated_completion_formatter{
       threshold  = 4 * 3,
       rounding   = 4,
       split_fun  = QuartersSplitFun,
       two_format = "~2wh~2..0wm"
      },
  HoursSplitFun =
    fun(Hours) ->
        case Hours < 60 of
          true -> Hours;
          false -> {Hours div 24, Hours rem 24}
        end
    end,
  HoursECF =
    #estimated_completion_formatter{
       threshold  = 3 * 24,
       rounding   = 6,
       split_fun  = HoursSplitFun,
       one_format = "   ~2wh",
       two_format = "~2wd~2..0wh"
      },
  DayQuartersSplitFun =
    fun(Quarters) -> {Quarters div 4, (Quarters rem 4) * 6} end,
  DayQuartersECF =
    #estimated_completion_formatter{
       threshold  = 4 * 15,
       rounding   = 4,
       split_fun  = DayQuartersSplitFun,
       one_format = "   ~2wh",
       two_format = "~2wd~2..0wh"
      },
  DaysSplitFun = fun(Days) -> Days end,
  DaysECF =
    #estimated_completion_formatter{
       threshold  = infinity,
       split_fun  = DaysSplitFun,
       one_format = "~5wd"
      },
  [SecondsECF, MinutesECF, QuartersECF, HoursECF, DayQuartersECF, DaysECF].

estimated_completion_to_string(Seconds) ->
  estimated_completion_to_string(estimated_completion_formatters(), Seconds).

estimated_completion_to_string([ECF|Rest], Value) ->
  #estimated_completion_formatter{
     threshold  = Threshold,
     rounding   = Rounding,
     split_fun  = SplitFun,
     one_format = OneFormat,
     two_format = TwoFormat
    } = ECF,
  case Value > Threshold of
    true -> estimated_completion_to_string(Rest, round(Value/Rounding));
    false ->
      case SplitFun(Value) of
        {High, Low} -> io_lib:format(TwoFormat, [High, Low]);
        Single -> io_lib:format(OneFormat, [Single])
      end
  end.
