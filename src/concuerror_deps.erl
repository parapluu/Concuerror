%%%----------------------------------------------------------------------
%%% Copyright (c) 2013, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Stavros Aronis <aronisstav@gmail.com>
%%% Description : Dependency relation for Erlang
%%%----------------------------------------------------------------------

-module(concuerror_deps).

-export([may_have_dependencies/1,
         dependent/2,
         lock_release_atom/0]).

-spec may_have_dependencies(concuerror_sched:transition()) -> boolean().

may_have_dependencies({_Lid, {error, _}, []}) -> false;
may_have_dependencies({_Lid, {Spawn, _}, []})
  when Spawn =:= spawn; Spawn =:= spawn_link; Spawn =:= spawn_monitor;
       Spawn =:= spawn_opt -> false;
may_have_dependencies({_Lid, {'receive', {unblocked, _, _}}, []}) -> false;
may_have_dependencies({_Lid, exited, []}) -> false;
may_have_dependencies(_Else) -> true.

-spec lock_release_atom() -> '_._concuerror_lock_release'.

lock_release_atom() -> '_._concuerror_lock_release'.

-define( ONLY_INITIALLY, true).
-define(      SYMMETRIC, true).
-define(      CHECK_MSG, true).
-define(     ALLOW_SWAP, true).
-define(DONT_ALLOW_SWAP, false).
-define(ONLY_AFTER_SWAP, false).
-define( DONT_CHECK_MSG, false).

-spec dependent(concuerror_sched:transition(),
                concuerror_sched:transition()) -> boolean().

dependent(A, B) ->
    dependent(A, B, ?CHECK_MSG, ?ALLOW_SWAP).

%%==============================================================================

%% Instructions from the same process are always dependent
dependent({Lid, _Instr1, _Msgs1},
          {Lid, _Instr2, _Msgs2}, ?ONLY_INITIALLY, ?ONLY_INITIALLY) ->
    true;

%%==============================================================================

%% XXX: This should be fixed in sched:recent_dependency_cv and removed
dependent({_Lid1, _Instr1, _Msgs1},
          {_Lid2, Special, _Msgs2}, ?ONLY_INITIALLY, ?ONLY_INITIALLY)
  when Special =:= 'block'; Special =:= 'init' ->
    false;

%%==============================================================================

%% Decisions depending on send and receive statements:

%%==============================================================================

%% Sending to the same process:
dependent({ Lid1,  Instr1, PreMsgs1} = Trans1,
          {_Lid2, _Instr2, PreMsgs2} = Trans2,
          ?CHECK_MSG, AllowSwap) ->
    ProcEvidence = [{P, L} || {P, {_M, L}} <- PreMsgs2],
    Msgs2 = [{P, M} || {P, {M, _L}} <- PreMsgs2],
    Msgs1 = add_missing_messages(Lid1, Instr1, PreMsgs1, ProcEvidence),
    case Msgs1 =:= [] orelse Msgs2 =:= [] of
        true -> dependent(Trans1, Trans2, ?DONT_CHECK_MSG, AllowSwap);
        false ->
            Lids1 = ordsets:from_list(orddict:fetch_keys(Msgs1)),
            Lids2 = ordsets:from_list(orddict:fetch_keys(Msgs2)),
            case ordsets:intersection(Lids1, Lids2) of
                [] ->
                    dependent(Trans1, Trans2, ?DONT_CHECK_MSG, AllowSwap);
                [Key] ->
                    %% XXX: Can be refined
                    case {orddict:fetch(Key, Msgs1), orddict:fetch(Key, Msgs2)} of
                        {[V1], [V2]} ->
                            LockReleaseAtom = lock_release_atom(),
                            V1 =/= LockReleaseAtom andalso V2 =/= LockReleaseAtom;
                        _Else -> true
                    end;
                _ -> true %% XXX: Can be refined
            end
    end;

%%==============================================================================

%% Sending to an activated after clause depends on that receive's patterns OR
%% Sending the message that triggered a receive's 'had_after'
dependent({Lid1,          Instr1, PreMsgs1} = Trans1,
          {Lid2, {Receive, Info},   _Msgs2} = Trans2,
          _CheckMsg, AllowSwap) when
      Receive =:= 'after';
      (Receive =:= 'receive' andalso
       element(1, Info) =:= had_after) ->
    ProcEvidence =
        case Receive =:= 'after' of
            true  -> [{Lid2, element(2, Info)}];
            false -> []
        end,
    Msgs1 = add_missing_messages(Lid1, Instr1, PreMsgs1, ProcEvidence),
    Dependent =
        case orddict:find(Lid2, Msgs1) of
            {ok, MsgsToLid2} ->
                Fun =
                    case Receive of
                        'after' -> element(1, Info);
                        'receive' ->
                            Target = element(3, Info),
                            fun(X) -> X =:= Target end
                    end,
                lists:any(Fun, MsgsToLid2);
            error -> false
        end,
    Dependent orelse (AllowSwap andalso
		      dependent(Trans2, Trans1, ?CHECK_MSG, ?DONT_ALLOW_SWAP));
%%==============================================================================

%% Other instructions are not in race with receive or after, if not caught by
%% the message checking part.
dependent({_Lid1, {   _Any, _Details1}, _Msgs1},
          {_Lid2, {Receive, _Details2}, _Msgs2},
          _CheckMsg, ?ONLY_AFTER_SWAP) when
      Receive =:= 'after';
      Receive =:= 'receive' ->
    false;

%% Swapped version, as the message checking code can force a swap.
dependent({_Lid1, {Receive, _Details1}, _Msgs1},
          {_Lid2, {   _Any, _Details2}, _Msgs2},
          _CheckMsg, ?ONLY_AFTER_SWAP) when
      Receive =:= 'after';
      Receive =:= 'receive' ->
    false;

%%==============================================================================
%% From here onwards, we have taken care of messaging races.
%%==============================================================================

%% ETS operations live in their own small world.
dependent({_Lid1, {ets, Op1}, _Msgs1},
          {_Lid2, {ets, Op2}, _Msgs2},
          _CheckMsg, ?SYMMETRIC) ->
    dependent_ets(Op1, Op2);

%%==============================================================================

%% Registering a table with the same name as an existing one.
dependent({_Lid1, { ets, {   new,           [_Table, Name, Options]}}, _Msgs1},
          {_Lid2, {exit, {normal, {{_Heirs, Tables}, _Name, _Links}}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    NamedTables = [N || {_Lid, {ok, N}} <- Tables],
    lists:member(named_table, Options) andalso
        lists:member(Name, NamedTables);

%% Table owners exits race with any ets operation on the same table.
dependent({_Lid1, { ets, {   _Op,                     [Table|_Rest]}}, _Msgs1},
          {_Lid2, {exit, {normal, {{_Heirs, Tables}, _Name, _Links}}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    lists:keymember(Table, 1, Tables);

%% %% Covered by next
%% dependent({_Lid1, { ets, _Details1}, _Msgs1},
%%           {_Lid2, {exit, _Details2}, _Msgs2},
%%           _CheckMsg, _AllowSwap) ->
%%     false;

%%==============================================================================

%% No other operations race with ets operations.
dependent({_Lid1, { ets, _Details1}, _Msgs1},
          {_Lid2, {_Any, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Heirs exit should also be monitored.
%% XXX: Maybe should be removed
dependent({Lid1, {exit, {normal, {{Heirs1, _Tbls1}, _Name1, _Links1}}}, _Msgs1},
          {Lid2, {exit, {normal, {{Heirs2, _Tbls2}, _Name2, _Links2}}}, _Msgs2},
          _CheckMsg, ?SYMMETRIC) ->
    lists:member(Lid1, Heirs2) orelse lists:member(Lid2, Heirs1);

%%==============================================================================

%% Registered processes:

%% Sending using name to a process that may exit and unregister.
dependent({_Lid1, {send,                     {TName, _TLid, _Msg}}, _Msgs1},
          {_Lid2, {exit, {normal, {_Tables, {ok, TName}, _Links}}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    true;
dependent({_Lid1, {send, _Details1}, _Msgs1},
          {_Lid2, {exit, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Register and unregister have the same dependencies.
%% Use a unique value for the Pid to avoid checks there.
dependent({Lid, {unregister, RegName}, Msgs}, B, CheckMsg, AllowSwap) ->
    dependent({Lid, {register, {RegName, make_ref()}}, Msgs}, B,
              CheckMsg, AllowSwap);
dependent(A, {Lid, {unregister, RegName}, Msgs}, CheckMsg, AllowSwap) ->
    dependent(A, {Lid, {register, {RegName, make_ref()}}, Msgs},
              CheckMsg, AllowSwap);

%%==============================================================================

%% Send using name before process has registered itself (or after ungeristering).
dependent({_Lid1, {register,      {RegName, _TLid}}, _Msgs1},
          {_Lid2, {    send, {RegName, _Lid, _Msg}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    true;

%% No other races between register and send.
dependent({_Lid1, {register, _Details1}, _Msgs1},
          {_Lid2, {    send, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Two registers using the same name or the same process.
dependent({_Lid1, {register, {RegName1, TLid1}}, _Msgs1},
          {_Lid2, {register, {RegName2, TLid2}}, _Msgs2},
          _CheckMsg, ?SYMMETRIC) ->
    RegName1 =:= RegName2 orelse TLid1 =:= TLid2;

%%==============================================================================

%% Register a process that may exit.
dependent({_Lid1, {register, {_RegName, TLid}}, _Msgs1},
          { TLid, {    exit,  {normal, _Info}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    true;

%% Register for a name that might be in use.
dependent({_Lid1, {register,                           {Name, _TLid}}, _Msgs1},
          {_Lid2, {    exit, {normal, {_Tables, {ok, Name}, _Links}}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    true;

%% No other races between register and exit.
dependent({_Lid1, {register, _Details1}, _Msgs1},
          {_Lid2, {    exit, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Whereis using name before process has registered itself.
dependent({_Lid1, {register, {RegName, _TLid1}}, _Msgs1},
          {_Lid2, { whereis, {RegName, _TLid2}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    true;

%% No other races between register and whereis.
dependent({_Lid1, {register, _Details1}, _Msgs1},
          {_Lid2, { whereis, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Process alive and exits.
dependent({_Lid1, {is_process_alive,            TLid}, _Msgs1},
          { TLid, {            exit, {normal, _Info}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    true;

%% No other races between is_process_alive and exit.
dependent({_Lid1, {is_process_alive, _Details1}, _Msgs1},
          {_Lid2, {            exit, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Process registered and exits.
dependent({_Lid1, {whereis,                          {Name, _TLid1}}, _Msgs1},
          {_Lid2, {   exit, {normal, {_Tables, {ok, Name}, _Links}}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    true;

%% No other races between whereis and exit.
dependent({_Lid1, {whereis, _Details1}, _Msgs1},
          {_Lid2, {   exit, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Demonitor/link/unlink and exit.
dependent({_Lid, {Linker,            TLid}, _Msgs1},
          {TLid, {  exit, {normal, _Info}}, _Msgs2},
          _CheckMsg, _AllowSwap)
  when Linker =:= demonitor; Linker =:= link; Linker =:= unlink ->
    true;

%% No other races between demonitor/link/unlink and exit.
dependent({_Lid1, {Linker, _Details1}, _Msgs1},
          {_Lid2, {  exit, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap)
  when Linker =:= demonitor; Linker =:= link; Linker =:= unlink ->
    false;

%%==============================================================================

%% Depending on the order, monitor's Info is different.
dependent({_Lid, {monitor, {TLid, _MonRef}}, _Msgs1},
          {TLid, {   exit, {normal, _Info}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    true;

dependent({_Lid1, {monitor, _Details1}, _Msgs1},
          {_Lid2, {   exit, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Trap exits flag and linked process exiting.
dependent({Lid1, {process_flag,        {trap_exit, _Value, Links1}}, _Msgs1},
          {Lid2, {        exit, {normal, {_Tables, _Name, Links2}}}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    lists:member(Lid2, Links1) orelse lists:member(Lid1, Links2);

%% No other races between setting a process flag and exiting.
dependent({_Lid1, {process_flag, _Details1}, _Msgs1},
          {_Lid2, {        exit, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap) ->
    false;

%%==============================================================================

%% Setting a process_flag is not in race with linking. Happening together, they
%% can cause other races, however.
dependent({_Lid1, {process_flag, _Details1}, _Msgs1},
          {_Lid2, {LinkOrUnlink, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap)
  when LinkOrUnlink =:= link; LinkOrUnlink =:= unlink ->
    false;

%%==============================================================================

%% Spawning is independent with everything else.
dependent({_Lid1, {Spawn, _Details1}, _Msgs1},
          {_Lid2, { _Any, _Details2}, _Msgs2},
          _CheckMsg, _AllowSwap)
  when Spawn =:= spawn; Spawn =:= spawn_link; Spawn =:= spawn_monitor;
       Spawn =:= spawn_opt ->
    false;

%%==============================================================================

%% Swap the two arguments if the test is not symmetric by itself.
dependent(TransitionA, TransitionB, _CheckMsg, ?ALLOW_SWAP) ->
    dependent(TransitionB, TransitionA, ?CHECK_MSG, ?DONT_ALLOW_SWAP);

dependent(TransitionA, TransitionB, _CheckMsg, ?DONT_ALLOW_SWAP) ->
    case independent(TransitionA, TransitionB) of
        true -> false;
        maybe ->
            concuerror_log:log(3, "Not certainly independent:\n ~p\n ~p\n",
                      [TransitionA, TransitionB]),
            true
    end.

%%==============================================================================
%%==============================================================================

-spec independent(concuerror_sched:transition(),
                  concuerror_sched:transition()) -> 'true' | 'maybe'.

independent({_Lid1, {Op1, _}, _Msgs1}, {_Lid2, {Op2, _}, _Msgs2}) ->
    Independent =
        [
         {     monitor, demonitor},
         {     monitor,      send},
         {   demonitor,      send},
         {     whereis,      send},
         {        link,      send},
         {      unlink,      send},
         {process_flag,      send}
        ],
    case
        %% Assuming that all the races of an instruction with another instance
        %% of itself have already been caught.
        Op1 =:= Op2
        orelse lists:member({Op1, Op2},Independent)
        orelse lists:member({Op2, Op1},Independent)
    of
        true -> true;
        false -> maybe
    end.

add_missing_messages(Lid, Instr, PreMsgs, ProcEvidence) ->
    Msgs = [{P, M} || {P, {M, _L}} <- PreMsgs],
    case Instr of
        {send, {_RegName, Lid2, Msg}} ->
            add_missing_message(Lid2, Msg, Msgs);
        {exit, _} ->
            Msg = {'EXIT', Lid, normal},
            Adder = fun(P, M) -> add_missing_message(P, Msg, M) end,
            Fold =
                fun({P, Links}, Acc) ->
                        case lists:member(Lid, Links) of
                            true -> Adder(P, Acc);
                            false -> Acc
                        end
                end,
            lists:foldl(Fold, Msgs, ProcEvidence);
        _ -> Msgs
    end.

add_missing_message(Lid, Msg, Msgs) ->
    try true = lists:member(Msg, orddict:fetch(Lid, Msgs)) of
        _ -> Msgs
    catch
        _:_ -> orddict:append(Lid, Msg, Msgs)
    end.

%% ETS table dependencies:

dependent_ets(Op1, Op2) ->
    dependent_ets(Op1, Op2, ?ALLOW_SWAP).

%%==============================================================================

dependent_ets({MajorOp, [Tid1, Name1|_]}, {_, [Tid2, Name2|_]}, _AllowSwap)
  when MajorOp =:= info; MajorOp =:= delete ->
    (Tid1 =:= Tid2) orelse (Name1 =:= Name2);

%%==============================================================================

dependent_ets({insert, [T, _, Keys1, KP, Objects1, true]},
              {insert, [T, _, Keys2, KP, Objects2, true]}, ?SYMMETRIC) ->
    case ordsets:intersection(Keys1, Keys2) of
        [] -> false;
        Keys ->
            Fold =
                fun(_K, true) -> true;
                   (K, false) ->
                        lists:keyfind(K, KP, Objects1) =/=
                            lists:keyfind(K, KP, Objects2)
                end,
            lists:foldl(Fold, false, Keys)
    end;

dependent_ets({insert, _Details1},
              {insert, _Details2}, ?SYMMETRIC) ->
    false;

%%==============================================================================

dependent_ets({insert_new, [_, _, _, _, _, false]},
              {insert_new, [_, _, _, _, _, false]}, ?SYMMETRIC) ->
    false;

dependent_ets({insert_new, [T, _, Keys1, KP, _Objects1, _Status1]},
              {insert_new, [T, _, Keys2, KP, _Objects2, _Status2]},
              ?SYMMETRIC) ->
    ordsets:intersection(Keys1, Keys2) =/= [];

dependent_ets({insert_new, _Details1},
              {insert_new, _Details2}, ?SYMMETRIC) ->
    false;

%%==============================================================================

dependent_ets({insert_new, [T, _, Keys1, KP, _Objects1, _Status1]},
              {    insert, [T, _, Keys2, KP, _Objects2,     true]},
              _AllowSwap) ->
    ordsets:intersection(Keys1, Keys2) =/= [];

dependent_ets({insert_new, _Details1},
              {    insert, _Details2},
              _AllowSwap) ->
    false;

%%==============================================================================

dependent_ets({Insert, [T, _, Keys, _KP, _Objects1, true]},
              {lookup, [T, _, K]}, _AllowSwap)
  when Insert =:= insert; Insert =:= insert_new ->
    ordsets:is_element(K, Keys);

dependent_ets({Insert, _Details1},
              {lookup, _Details2}, _AllowSwap)
  when Insert =:= insert; Insert =:= insert_new ->
    false;

%%==============================================================================

dependent_ets({lookup, _Details1}, {lookup, _Details2}, ?SYMMETRIC) ->
    false;

%%==============================================================================

dependent_ets({new, [_Tid1, Name, Options1]},
              {new, [_Tid2, Name, Options2]}, ?SYMMETRIC) ->
    lists:member(named_table, Options1) andalso
        lists:member(named_table, Options2);

%%==============================================================================

dependent_ets({ new, _Details1}, {_Any, _Details2}, ?DONT_ALLOW_SWAP) ->
    false;

dependent_ets({_Any, _Details1}, { new, _Details2}, ?DONT_ALLOW_SWAP) ->
    false;

%%==============================================================================

dependent_ets(Op1, Op2, ?ALLOW_SWAP) ->
    dependent_ets(Op2, Op1, ?DONT_ALLOW_SWAP);
dependent_ets(Op1, Op2, ?DONT_ALLOW_SWAP) ->
    concuerror_log:log(3, "Not certainly independent (ETS):\n ~p\n ~p\n",
                       [Op1, Op2]),
    true.
