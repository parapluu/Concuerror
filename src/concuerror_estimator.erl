%% -*- erlang-indent-level: 2 -*-

%% @doc The estimator process is being updated by the scheduler and
%%      polled independently by the logger. It stores a lightweight
%%      representation/summarry of the exploration tree and uses it to
%%      give an estimation of the total size.

-module(concuerror_estimator).

-behaviour(gen_server).

%% API
-export([start_link/1, finish/1, restart/2, plan/2, get_estimation/1]).

%% Other
-export([estimate_completion/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%------------------------------------------------------------------------------

-export_type([estimator/0, estimation/0]).

-type estimator()  :: pid() | 'none'.
-type estimation() :: pos_integer() | 'unknown'.

-type average() :: concuerror_window_average:average().

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

-define(INITIAL_DELAY, 100).
-define(DELAY, 10).

-record(state, {
          average    = initial        :: 'initial' | average(),
          delay      = ?INITIAL_DELAY :: non_neg_integer(),
          estimation = unknown        :: estimation(),
          explored   = dict:new()     :: explored(),
          planned    = dict:new()     :: planned(),
          style                       :: estimation_style()
         }).

%%%=============================================================================
%%% API
%%%=============================================================================

-type call() :: 'get_estimation'.
-type cast() ::  {'restart' | 'plan', index()}.

%%%=============================================================================

-spec start_link(concuerror_options:options()) -> estimator().

start_link(Options) ->
  case estimation_style(Options) of
    unknown -> none;
    Other ->
      {ok, Pid} = gen_server:start_link(?MODULE, Other, []),
      Pid
  end.

%%------------------------------------------------------------------------------

-record(delay_bounded, {
          bound     = 0                   :: pos_integer(),
          races_avg = init_average(4, 20) :: average()
         }).

-type estimation_style() ::
        {'hard_bound', pos_integer(), estimation_style()} |
        {'recursive', 'one_step' | 'tree'} |
        #delay_bounded{} |
        'unknown'.

-spec estimation_style(concuerror_options:options()) -> estimation_style().

estimation_style(Options) ->
  Verbosity = ?opt(verbosity, Options),
  case concuerror_logger:showing_progress(Verbosity) of
    false -> unknown;
    true ->
      Style =
        case ?opt(scheduling_bound_type, Options) of
          delay ->
            Bound = ?opt(scheduling_bound, Options),
            #delay_bounded{bound = Bound};
          none ->
            case ?opt(dpor, Options) =:= optimal of
              false -> {recursive, one_step};
              true -> {recursive, tree}
            end;
          _ ->
            unknown
        end,
      case ?opt(interleaving_bound, Options) of
        IBound when is_number(IBound), Style =/= unknown ->
          {hard_bound, IBound, Style};
        _ ->
          Style
      end
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
  %% io:format("Restart: ~p~n", [Index]),
  gen_server:cast(Estimator, {restart, Index}).

%%------------------------------------------------------------------------------

-spec plan(estimator(), index()) -> 'ok'.

plan(none, _Index) -> ok;
plan(Estimator, Index) ->
  %% io:format("Plan: ~p~n", [Index]),
  gen_server:cast(Estimator, {plan, Index}).

%%------------------------------------------------------------------------------

-spec get_estimation(estimator()) -> estimation().

get_estimation(none) -> unknown;
get_estimation(Estimator) ->
  gen_server:call(Estimator, get_estimation).

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

-spec init(estimation_style()) -> {'ok', #state{}}.

init(Style) ->
  {ok, #state{style = Style}}.

%%------------------------------------------------------------------------------

-spec handle_call(call(), _From, #state{}) -> {'reply', term(), #state{}}.

handle_call(get_estimation, _From, #state{estimation = Estimation} = State) ->
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
  NewPlanned =
    case dict:find(I, Planned) of
      {ok, Value} when Value > 0 ->
        dict:update_counter(I, -1, Planned);
      _ ->
        CleanupFun = fun(_, V) -> V > 0 end,
        CleanPlanned = dict:filter(CleanupFun, Planned),
        AllPlanned = lists:sort(dict:fetch_keys(CleanPlanned)),
        [NI|_] = lists:reverse(lists:takewhile(SmallerFun, AllPlanned)),
        %% io:format("Miss! Hit @ ~p~n", [NI]),
        dict:update_counter(NI, -1, Planned)
    end,
  FoldFun =
    fun(M, {Total, E}) ->
        Sum = lists:sum(dict:fetch(M, E)),
        NE = dict:erase(M, E),
        {Total + Sum, NE}
    end,
  Marks = ordsets:from_list(dict:fetch_keys(Explored)),
  Larger = lists:dropwhile(SmallerFun, Marks),
  {Sum, OutExplored} = lists:foldl(FoldFun, {1, Explored}, Larger),
  NewExplored = dict:append(I, Sum, OutExplored),
  NewState = State#state{explored = NewExplored, planned = NewPlanned},
  FinalState = reestimate(NewState),
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

init_average(Value, Window) ->
  concuerror_window_average:init(Value, Window).

update_average(Value, Average) ->
  concuerror_window_average:update(Value, Average).

reestimate(#state{average = Average, delay = Delay} = State) ->
  case Delay > 0 of
    true -> State#state{delay = Delay - 1};
    false ->
      {Value, NewState} = estimate(State),
      {Estimation, NewAverage} =
        case Average =:= initial of
          false -> update_average(Value, Average);
          true -> {Value, init_average(Value, 10)}
        end,
      NewState#state{
        average = NewAverage,
        delay = ?DELAY,
        estimation = two_significant(round(Estimation))
       }
  end.

all_keys(Explored, Planned) ->
  [ExploredKeys, PlannedKeys] =
    [ordsets:from_list(dict:fetch_keys(D)) ||
      D <- [Explored, Planned]],
  ordsets:union(ExploredKeys, PlannedKeys).

estimate(#state{style = {hard_bound, Bound, Style}} = State) ->
  {Est, NewState} = estimate(State#state{style = Style}),
  NewStyle = NewState#state.style,
  {min(Est, Bound), NewState#state{style = {hard_bound, Bound, NewStyle}}};
estimate(State) ->
  #state{
     explored = Explored,
     planned = RawPlanned,
     style = Style
    } = State,
  CleanupFun = fun(_, V) -> V > 0 end,
  Planned = dict:filter(CleanupFun, RawPlanned),
  NewState = State#state{planned = Planned},
  case Style of
    {recursive, Subtree} ->
      Marks = all_keys(Explored, Planned),
      FoldFun =
        fun(M, L) ->
            AllExplored =
              case dict:find(M, Explored) of
                error -> [L];
                {ok, More} -> [L|More]
              end,
            Sum = lists:sum(AllExplored),
            AllPlanned =
              case dict:find(M, Planned) of
                error -> 0;
                {ok, P} ->
                  case Subtree of
                    one_step ->
                      %% Each one-step plan will explore a similar tree
                      P * Sum / length(AllExplored);
                    tree ->
                      %% Each plan is a single planned execution so
                      %% plans are the size of the tree and the
                      %% estimation is an average between everything
                      %% we so far know (already explored plus this
                      %% planned tree).
                      (Sum + P) / (length(AllExplored) + 1)
                  end
              end,
            Sum + AllPlanned
        end,
      AllButLast = lists:reverse(Marks),
      {round(lists:foldl(FoldFun, 1, AllButLast)), NewState};
    #delay_bounded{
       bound = Bound,
       races_avg = RacesAvg
      } ->
      MoreThanOne = fun(_, V) -> V > 1 end,
      SignificantPlanned = dict:filter(MoreThanOne, Planned),
      Marks = all_keys(Explored, SignificantPlanned),
      Length = length(Marks),
      {Races, NewRacesAvg} = update_average(Length, RacesAvg),
      Est = bounded_estimation(Races, Bound),
      %% io:format("~w~n~w~n", [lists:sort(dict:to_list(Explored)), lists:sort(dict:to_list(Planned))]),
      %% io:format("~w, ~.2f, ~.2f~n", [Length, Races, Est]),
      NewStyle = Style#delay_bounded{races_avg = NewRacesAvg},
      {round(Est), NewState#state{style = NewStyle}}
  end.

bounded_estimation(Races, Bound) ->
  bounded_estimation(Races, Bound, 1).

bounded_estimation(_Races, 0, Acc) ->
  Acc;
bounded_estimation(Races, N , Acc) ->
  %% XXX: Think more about this...
  bounded_estimation(Races, N - 1, 1 + Races * Acc).

two_significant(Number) when Number < 100 -> Number;
two_significant(Number) -> 10 * two_significant(Number div 10).

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
  " " ++ approximate_time_string(Completion).

-type posint() :: pos_integer().
-type split_fun() :: fun((posint()) -> posint() | {posint(), posint()}).

-record(approximate_time_formatter, {
          threshold  = 1       :: pos_integer() | 'infinity',
          rounding   = 1       :: pos_integer(),
          split_fun            :: split_fun(),
          one_format = "~w"    :: string(),
          two_format = "~w ~w" :: string()
         }).

approximate_time_formatters() ->
  SecondsSplitFun = fun(_) -> 1 end,
  SecondsATF =
    #approximate_time_formatter{
       threshold  = 1 * 60,
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
  MinutesATF =
    #approximate_time_formatter{
       threshold  = 60,
       rounding   = 15,
       split_fun  = MinutesSplitFun,
       one_format = "   ~2wm",
       two_format = "~2wh~2..0wm"
      },
  QuartersSplitFun =
    fun(Quarters) -> {Quarters div 4, (Quarters rem 4) * 15} end,
  QuartersATF =
    #approximate_time_formatter{
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
  HoursATF =
    #approximate_time_formatter{
       threshold  = 3 * 24,
       rounding   = 6,
       split_fun  = HoursSplitFun,
       one_format = "   ~2wh",
       two_format = "~2wd~2..0wh"
      },
  DayQuartersSplitFun =
    fun(Quarters) -> {Quarters div 4, (Quarters rem 4) * 6} end,
  DayQuartersATF =
    #approximate_time_formatter{
       threshold  = 4 * 15,
       rounding   = 4,
       split_fun  = DayQuartersSplitFun,
       one_format = "   ~2wh",
       two_format = "~2wd~2..0wh"
      },
  DaysSplitFun = fun(Days) -> Days end,
  DaysATF =
    #approximate_time_formatter{
       threshold  = infinity,
       split_fun  = DaysSplitFun,
       one_format = "~5wd"
      },
  [ SecondsATF
  , MinutesATF
  , QuartersATF
  , HoursATF
  , DayQuartersATF
  , DaysATF
  ].

approximate_time_string(Seconds) ->
  approximate_time_string(approximate_time_formatters(), Seconds).

approximate_time_string([ATF|Rest], Value) ->
  #approximate_time_formatter{
     threshold  = Threshold,
     rounding   = Rounding,
     split_fun  = SplitFun,
     one_format = OneFormat,
     two_format = TwoFormat
    } = ATF,
  case Value > Threshold of
    true -> approximate_time_string(Rest, round(Value/Rounding));
    false ->
      case SplitFun(Value) of
        {High, Low} -> io_lib:format(TwoFormat, [High, Low]);
        Single -> io_lib:format(OneFormat, [Single])
      end
  end.
