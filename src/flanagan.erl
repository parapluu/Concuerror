%% -*- erlang-indent-level: 2 -*-

-module(flanagan).

-export([test/1, explore/2]).

%% -define(DEBUG, true).
%% -define(STEPWISE, true).
%% -define(STATS, true).

-ifdef(DEBUG).
-define(STACK, true).
-endif.

%%------------------------------------------------------------------------------

-record(state, {
          i,
          last,
          pstates,
          backtrack = [],
          done = []
         }).

-record(pstate, {
          commands,
          mailbox = 0
         }).

%%------------------------------------------------------------------------------

%% Sample Inputs

%% M1 : INDEPENDENT SENDER RECEIVER PAIRS

%% The following program has 5 processes: m1 (main), a & b (sender), c & d
%% (receiver). Run with test(m1).

%% main() ->
%%     Parent = self(),
%%     Rec1 = spawn(fun() -> receiver(Parent) end),
%%     Rec2 = spawn(fun() -> receiver(Parent) end),
%%     Snd1 = spawn(fun() -> sender(Rec1) end),
%%     Snd2 = spawn(fun() -> sender(Rec2) end),
%%     receive
%%         ok ->
%%             receive
%%                 ok -> done
%%             end
%%     end.

%% sender(Pid) ->
%%     Pid ! ok.

%% receiver(Parent) ->
%%     receive
%%         ok -> Parent ! ok
%%     end.


-ifdef(STATS).
-define(stats_start, put(interleavings, 0)).
-define(stats_report, io:format("Interleavings: ~p\n", [get(interleavings)])).
-define(stats_inc, begin
                     I = get(interleavings) + 1,
                     put(interleavings, I)
                   end).
-else.
-define(stats_start, ok).
-define(stats_report, ok).
-define(stats_inc, ok).
-endif.

test(M) ->
  InitPStates = dict:store(M, new_pstate(M), dict:new()),
  ?stats_start,
  Trace = init_trace(InitPStates),
  explore(Trace, new_clock_vector_dict()),
  ?stats_report.

new_pstate(P) -> #pstate{commands = p(P)}.

init_trace(InitPStates) -> [#state{i = 0, last = init, pstates = InitPStates}].

new_clock_vector_dict() -> dict:new().

p(m1) ->
  [{spawn, c},
   {spawn, d},
   {spawn, a},
   {spawn, b},
   rec,
   rec,
   exit];

p(a) ->
  [{send, c},
   exit];
p(b) ->
  [{send, d},
   exit];
p(c) ->
  [rec,
   {send, m1},
   exit];
p(d) ->
  [rec,
   {send, m1},
   exit].


%%------------------------------------------------------------------------------

do_command(#pstate{commands = [Command|Rest]} = PState) ->
  {Command, PState#pstate{commands = Rest}}.

inc_mail(#pstate{mailbox = Mailbox} = PState) ->
  PState#pstate{mailbox = Mailbox + 1}.

dec_mail(#pstate{mailbox = Mailbox} = PState) ->
  PState#pstate{mailbox = Mailbox - 1}.

is_p_enabled(#pstate{commands = [Command|_], mailbox = Mailbox}) ->
  Value =
    case Command of
      exit -> true;
      {spawn, _Q} -> true;
      {send, _Q} -> true;
      rec -> Mailbox > 0
    end,
  case Value of
    true -> {true, Command};
    false -> false
  end;
is_p_enabled(_) -> false.

run(P, PStates) ->
  PState = dict:fetch(P, PStates),
  {Command, NextPState} = do_command(PState),
  case Command of
    {spawn, Q} ->
      NewPStates0 = dict:store(Q, #pstate{commands = p(Q)}, PStates),
      {Command, {ok, dict:store(P, NextPState, NewPStates0)}};
    {send, Q} ->
      QState = dict:fetch(Q, PStates),
      NewPStates0 = dict:store(Q, inc_mail(QState), PStates),
      {Command, {ok, dict:store(P, NextPState, NewPStates0)}};
    rec ->
      {Command, {ok, dict:store(P, dec_mail(NextPState), PStates)}};
    exit ->
      {Command, {ok, dict:store(P, NextPState, PStates)}}
  end.

%%------------------------------------------------------------------------------

%% ---------------------------
%% Erlang dependency semantics
%% ---------------------------

dependent({ P1,        _C1}, { P2,        _C2}) when P1 =:= P2 -> true;
dependent({_P1, {send, P2}}, {_P3, {send, P4}}) when P2 =:= P4 -> true;
dependent({_P1, {send, P2}}, { P3,        rec}) when P2 =:= P3 -> true;
dependent({ P1,        rec}, {_P2, {send, P3}}) when P1 =:= P3 -> true;
dependent(                _,                 _)                -> false.

%%------------------------------------------------------------------------------

-define(breakpoint, case io:get_line("") of "q\n" -> throw(q); _ -> ok end).

-ifdef(STEPWISE).
-define(stepwise, ?breakpoint).
-else.
-define(stepwise, ok).
-endif.

-ifdef(DEBUG).
-define(debug(A, B), io:format(A, B), ?stepwise).
-define(debug_break(A, B), io:format(A, B), ?breakpoint).
-else.
-define(debug(_A, _B), ok).
-define(debug_break(_A, _B), ok).
-endif.

-define(debug(A), ?debug(A, [])).

explore(Trace, ClockMap) ->
  ?debug("Explore ~p:\n", [get_stack(Trace)]),
  UpdatedTrace = add_old_backtracks(Trace, ClockMap),
  FinalTrace =
    case pick_random_enabled(Trace) of
      none ->
        %% TODO: Report Check for deadlocks
        ?stats_inc,
        UpdatedTrace;
      {ok, P} ->
        ?debug("Picking ~p for new step.\n", [P]),
        NewTrace = add_new_backtrack(P, UpdatedTrace),
        explore_backtracks(NewTrace, ClockMap)
    end,
  remove_last(FinalTrace).

add_old_backtracks([#state{pstates=PStates}|_] = Trace, ClockMap) ->
  Nexts = get_all_nexts(PStates),
  ?debug("Backtrack points: Forall processes: ~p\n", [Nexts]),
  add_old_backtracks(Nexts, Trace, ClockMap).

get_all_nexts(PStates) ->
  Fold =
    fun(P, #pstate{commands = Commands}, Acc) ->
        case Commands of
          [] -> Acc;
          [C|_] -> [{P,C}|Acc]
        end
    end,
  dict:fold(Fold, [], PStates).

add_old_backtracks([], Trace, _ClockMap) ->
  ?debug("Done adding backtrack points\n"),
  Trace;
add_old_backtracks([Command|Rest], Trace, ClockMap) ->
  ?debug("  ~p:\n",[Command]),
  NewTrace = add_old_backtracks_for_p(Command, Trace, [], ClockMap),
  add_old_backtracks(Rest, NewTrace, ClockMap).

add_old_backtracks_for_p(_Cmd1, [], Acc, _ClockMap) ->
  lists:reverse(Acc);
add_old_backtracks_for_p({ProcNext, _} = Next, [StateI|Rest], Acc, ClockMap) ->
  case StateI of
    #state{i = I, last = {ProcSi, _} = Si} ->
      Dependent = dependent(Next, Si),
      Clock = lookup_clock_value(ProcSi, lookup_clock(ProcNext, ClockMap)),
      ?debug("    ~p: ~p (Dep: ~p C: ~p)\n",
             [I, Si] ++ [Dependent] ++ [Clock]),
      case Dependent andalso I > Clock of
        false ->
          add_old_backtracks_for_p(Next, Rest, [StateI|Acc], ClockMap);
        true ->
          ?debug("      Dependent and i < Clock. Backtracking.\n"),
          [#state{pstates = PStates, backtrack = Backtrack} = Spi|Rest2] = Rest,
          ?debug("      Old backtrack: ~p\n", [Backtrack]),
          NewBacktrack =
            add_from_E(ProcNext, PStates, [StateI|Acc], ClockMap, Backtrack),
          ?debug("      New backtrack: ~p\n", [NewBacktrack]),
          lists:reverse(Acc, [StateI,Spi#state{backtrack = NewBacktrack}|Rest2])
      end;
    #state{i = 0, last = init} ->
      add_old_backtracks_for_p(Next, Rest, [StateI|Acc], ClockMap)
  end.

add_from_E(P, PStates, ForwardTrace, ClockMap, Backtrack) ->
  Enabled = all_enabled(PStates),
  case lists:member(P, Enabled) of
    true ->
      ?debug("        Enabled.\n"),
      ordsets:add_element(P, Backtrack);
    false ->
      ?debug("        Not Enabled.\n"),
      ClockVector = lookup_clock(P, ClockMap),
      case find_one_from_E(P, ClockVector, Enabled, ForwardTrace) of
        {true, Q} ->
          ?debug("        Q needs to happen: ~p\n", [Q]),
          ordsets:add_element(Q, Backtrack);
        false ->
          ?debug("        Adding all enabled: ~p\n", [Enabled]),
          ordsets:union(Backtrack, ordsets:from_list(Enabled))
      end
  end.

find_one_from_E(_P, _ClockVector, _Enabled, []) -> false;
find_one_from_E(P, ClockVector, Enabled, [Sj|Rest]) ->
  #state{i = J, last = _Sj = {ProcSj, _}} = Sj,
  ?debug("          ~p: ~p\n", [J, ProcSj]),
  Satisfies =
    case lists:member(ProcSj, Enabled) of
      false ->
        ?debug("          Was not enabled\n"),
        false;
      true -> 
        ClockValue = lookup_clock_value(ProcSj, ClockVector),
        ?debug("          Clock is: ~p\n", [ClockValue]),
        J =< ClockValue
    end,
  case Satisfies of
    true ->
      ?debug("            Found ~p\n", [ProcSj]),
      {true, ProcSj};
    false -> find_one_from_E(P, ClockVector, Enabled, Rest)
  end.

lookup_clock(PorS, ClockMap) ->
  case dict:find(PorS, ClockMap) of
    {ok, Clock} -> Clock;
    error -> dict:new()
  end.

lookup_clock_value(P, CV) ->
  case dict:find(P, CV) of
    {ok, Value} -> Value;
    error -> 0
  end.

pick_random_enabled([#state{pstates = PStates}|_]) ->
  %% TODO: This is not really efficient
  case all_enabled(PStates) of
    [] -> none;
    [P|_] -> {ok, P}
  end.

all_enabled(PStates) ->
  Fun =
    fun(P, PState, Acc) ->
        case is_p_enabled(PState) of
          false -> Acc;
          {true, _C} -> [P|Acc]
        end
    end,
  dict:fold(Fun, [], PStates).

remove_last([_Last|Trace]) ->
  %% TODO: Replay trace till previous step.
  Trace.

add_new_backtrack(P, [#state{} = State|Trace]) ->
  [State#state{backtrack = [P]}|Trace].

explore_backtracks(Trace, ClockMap) ->
  case pick_unexplored(Trace) of
    none ->
      ?debug("All backtracks explored.\n"),
      Trace;
    {ok, P, NewTrace} ->
      ?debug("Picking unexplored: ~p\n", [P]),
      case let_run(P, NewTrace) of
        {error, _Command, _Info} ->
          %% TODO: Report Something crashed
          %% TODO: Replay trace till previous step
          explore_backtracks(NewTrace, ClockMap);
        {ok, NewTrace2} ->
          NewClockMap = update_clock_map(NewTrace2, ClockMap),
          NewTrace3 = explore(NewTrace2, NewClockMap),
          explore_backtracks(NewTrace3, ClockMap)
      end
  end.

pick_unexplored([State|Rest]) ->
  #state{backtrack = Backtrack, done = Done} = State,
  ?debug("Back:~p\nDone:~p\n",[Backtrack, Done]),
  case find_unique(Backtrack, Done) of
    {ok, P} -> {ok, P, [State#state{done = ordsets:add_element(P, Done)}|Rest]};
    none -> none
  end.

find_unique([], _Set2) -> none;
find_unique([P|Set1], Set2) ->
  case ordsets:is_element(P, Set2) of
    true -> find_unique(Set1, Set2);
    false -> {ok, P}
  end.

let_run(P, [#state{i = N, pstates = PStates}|_] = Trace) ->
  {Command, Result} = run(P, PStates),
  case Result of
    {ok, NewPStates} ->
      NewState = #state{i = N+1, last = {P, Command}, pstates = NewPStates},
      NewTrace = [NewState|Trace],
      {ok, NewTrace};
    {error, Info} ->
      {error, Command, Info}
  end.

update_clock_map([#state{i = N, last = {P, _C} = Command}|Trace], ClockMap) ->
  CV = max_dependent(Command, Trace, ClockMap),
  CV2 = dict:store(P, N, CV),
  Ca = dict:store(P, CV2, ClockMap),
  dict:store(N, CV2, Ca).

max_dependent(Command, Trace, ClockMap) ->
  max_dependent(Command, Trace, ClockMap, dict:new()).

max_dependent(_Cmd, [], _ClockMap, Acc) -> Acc;
max_dependent(Cmd1, [#state{i = N, last = Cmd2}|Trace], ClockMap, Acc) ->
  case dependent(Cmd1, Cmd2) of
    true ->
      CI = lookup_clock(N, ClockMap),
      Merger = fun(_Key, V1, V2) -> max(V1, V2) end,
      NewAcc = dict:merge(Merger, CI, Acc),
      max_dependent(Cmd1, Trace, ClockMap, NewAcc);
    false ->
      max_dependent(Cmd1, Trace, ClockMap, Acc)
  end.

-ifdef(STACK).

get_stack(Trace) ->
  get_stack(Trace, []).

get_stack([], Acc) -> Acc;
get_stack([#state{last = P}|Rest], Acc) -> get_stack(Rest, [P|Acc]).

-endif.
