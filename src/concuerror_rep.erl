%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Replacement BIFs
%%%----------------------------------------------------------------------

-module(concuerror_rep).

-export([spawn_fun_wrapper/1]).

-export([rep_var/3, rep_send/2, rep_send/3]).

-export([rep_spawn/1, rep_spawn/3,
         rep_spawn_link/1, rep_spawn_link/3,
         rep_spawn_opt/2, rep_spawn_opt/4]).

-export([rep_link/1, rep_unlink/1,
         rep_spawn_monitor/1, rep_spawn_monitor/3,
         rep_process_flag/2]).

-export([rep_receive/2, rep_receive_block/0,
         rep_after_notify/0, rep_receive_notify/3,
         rep_receive_notify/1]).

-export([rep_ets_insert/2, rep_ets_new/2, rep_ets_lookup/2,
         rep_ets_insert_new/2, rep_ets_delete/1]).

-export([rep_register/2,
         rep_is_process_alive/1,
         rep_unregister/1,
         rep_whereis/1]).

-export([rep_monitor/2, rep_demonitor/1, rep_demonitor/2]).

-export([rep_halt/0, rep_halt/1]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions and Types
%%%----------------------------------------------------------------------

%% Return the calling process' LID.
-define(LID_FROM_PID(Pid), concuerror_lid:from_pid(Pid)).

%% The destination of a `send' operation.
-type dest() :: pid() | port() | atom() | {atom(), node()}.

%% Callback function mapping.
-define(INSTR_MOD_FUN,
        [{{erlang, demonitor, 1}, fun rep_demonitor/1},
         {{erlang, demonitor, 2}, fun rep_demonitor/2},
         {{erlang, halt, 0}, fun rep_halt/0},
         {{erlang, halt, 1}, fun rep_halt/1},
         {{erlang, is_process_alive, 1}, fun rep_is_process_alive/1},
         {{erlang, link, 1}, fun rep_link/1},
         {{erlang, monitor, 2}, fun rep_monitor/2},
         {{erlang, process_flag, 2}, fun rep_process_flag/2},
         {{erlang, register, 2}, fun rep_register/2},
         {{erlang, spawn, 1}, fun rep_spawn/1},
         {{erlang, spawn, 3}, fun rep_spawn/3},
         {{erlang, spawn_link, 1}, fun rep_spawn_link/1},
         {{erlang, spawn_link, 3}, fun rep_spawn_link/3},
         {{erlang, spawn_monitor, 1}, fun rep_spawn_monitor/1},
         {{erlang, spawn_monitor, 3}, fun rep_spawn_monitor/3},
         {{erlang, spawn_opt, 2}, fun rep_spawn_opt/2},
         {{erlang, spawn_opt, 4}, fun rep_spawn_opt/4},
         {{erlang, unlink, 1}, fun rep_unlink/1},
         {{erlang, unregister, 1}, fun rep_unregister/1},
         {{erlang, whereis, 1}, fun rep_whereis/1},
         {{ets, insert_new, 2}, fun rep_ets_insert_new/2},
         {{ets, lookup, 2}, fun rep_ets_lookup/2},
         {{ets, select_delete, 2}, fun rep_ets_select_delete/2},
         {{ets, insert, 2}, fun rep_ets_insert/2},
         {{ets, delete, 1}, fun rep_ets_delete/1},
         {{ets, delete, 2}, fun rep_ets_delete/2},
         {{ets, match_object, 1}, fun rep_ets_match_object/1},
         {{ets, match_object, 3}, fun rep_ets_match_object/3},
         {{ets, match_delete, 2}, fun rep_ets_match_delete/2},
         {{ets, new, 2}, fun rep_ets_new/2},
         {{ets, foldl, 3}, fun rep_ets_foldl/3}]).

%%%----------------------------------------------------------------------
%%% Callbacks
%%%----------------------------------------------------------------------

%% Handle Mod:Fun(Args) calls.
-spec rep_var(module(), atom(), [term()]) -> term().
rep_var(Mod, Fun, Args) ->
    Key = {Mod, Fun, length(Args)},
    case lists:keyfind(Key, 1, ?INSTR_MOD_FUN) of
        {Key, Callback} -> apply(Callback, Args);
        false -> apply(Mod, Fun, Args)
    end.

%% @spec: rep_demonitor(reference()) -> 'true'
%% @doc: Replacement for `demonitor/1'.
%%
%% Just yield before demonitoring.
-spec rep_demonitor(reference()) -> 'true'.
rep_demonitor(Ref) ->
    concuerror_sched:notify(demonitor, concuerror_lid:lookup_ref_lid(Ref)),
    demonitor(Ref).

%% @spec: rep_demonitor(reference(), ['flush' | 'info']) -> 'true'
%% @doc: Replacement for `demonitor/2'.
%%
%% Just yield before demonitoring.
-spec rep_demonitor(reference(), ['flush' | 'info']) -> 'true'.
rep_demonitor(Ref, Opts) ->
    concuerror_sched:notify(demonitor, concuerror_lid:lookup_ref_lid(Ref)),
    case lists:member(flush, Opts) of
        true ->
            receive
                {?INSTR_MSG, _, _, {_, Ref, _, _, _}} ->
                    true
            after 0 ->
                    true
            end;
        false ->
            true
    end,
    demonitor(Ref, Opts).

%% @spec: rep_halt() -> no_return()
%% @doc: Replacement for `halt/0'.
%%
%% Just send halt message and yield.
-spec rep_halt() -> no_return().
rep_halt() ->
    concuerror_sched:notify(halt, empty).

%% @spec: rep_halt() -> no_return()
%% @doc: Replacement for `halt/1'.
%%
%% Just send halt message and yield.
-spec rep_halt(non_neg_integer() | string()) -> no_return().
rep_halt(Status) ->
    concuerror_sched:notify(halt, Status).

%% @spec: rep_is_process_alive(pid()) -> boolean()
%% @doc: Replacement for `is_process_alive/1'.
-spec rep_is_process_alive(pid()) -> boolean().
rep_is_process_alive(Pid) ->
    case ?LID_FROM_PID(Pid) of
        not_found -> ok;
        PLid -> concuerror_sched:notify(is_process_alive, PLid)
    end,
    is_process_alive(Pid).

%% @spec: rep_link(pid() | port()) -> 'true'
%% @doc: Replacement for `link/1'.
%%
%% Just yield before linking.
-spec rep_link(pid() | port()) -> 'true'.
rep_link(Pid) ->
    case ?LID_FROM_PID(Pid) of
        not_found -> ok;
        PLid -> concuerror_sched:notify(link, PLid)
    end,
    link(Pid).

%% @spec: rep_monitor('process', pid() | {atom(), node()} | atom()) ->
%%                           reference()
%% @doc: Replacement for `monitor/2'.
%%
%% Just yield before monitoring.
-spec rep_monitor('process', pid() | {atom(), node()} | atom()) ->
            reference().
rep_monitor(Type, Item) ->
    case ?LID_FROM_PID(find_pid(Item)) of
        not_found -> monitor(Type, Item);
        Lid ->
            concuerror_sched:notify(monitor, {Lid, unknown}),
            Ref = monitor(Type, Item),
            concuerror_sched:notify(monitor, {Lid, Ref}, prev),
            concuerror_sched:wait(),
            Ref
    end.

%% @spec: rep_process_flag('trap_exit', boolean()) -> boolean();
%%                        ('error_handler', atom()) -> atom();
%%                        ('min_heap_size', non_neg_integer()) ->
%%                                non_neg_integer();
%%                        ('min_bin_vheap_size', non_neg_integer()) ->
%%                                non_neg_integer();
%%                        ('priority', process_priority_level()) ->
%%                                process_priority_level();
%%                        ('save_calls', non_neg_integer()) ->
%%                                non_neg_integer();
%%                        ('sensitive', boolean()) -> boolean()
%% @doc: Replacement for `process_flag/2'.
%%
%% Just yield before altering the process flag.
-type process_priority_level() :: 'max' | 'high' | 'normal' | 'low'.
-spec rep_process_flag('trap_exit', boolean()) -> boolean();
                      ('error_handler', atom()) -> atom();
                      ('min_heap_size', non_neg_integer()) -> non_neg_integer();
                      ('min_bin_vheap_size', non_neg_integer()) ->
                              non_neg_integer();
                      ('priority', process_priority_level()) ->
                              process_priority_level();
                      ('save_calls', non_neg_integer()) -> non_neg_integer();
                      ('sensitive', boolean()) -> boolean().
rep_process_flag(trap_exit = Flag, Value) ->
    {trap_exit, OldValue} = process_info(self(), trap_exit),
    case Value =:= OldValue of
        true -> ok;
        false ->
            PlannedLinks = find_my_links(),
            concuerror_sched:notify(process_flag, {Flag, Value, PlannedLinks}),
            Links = find_my_links(),
            concuerror_sched:notify(process_flag, {Flag, Value, Links}, prev)
    end,
    process_flag(Flag, Value);
rep_process_flag(Flag, Value) ->
    process_flag(Flag, Value).

find_my_links() ->
    {links, AllPids} = process_info(self(), links),
    AllLids = [?LID_FROM_PID(Pid) || Pid <- AllPids],
    [KnownLid || KnownLid <- AllLids, KnownLid =/= not_found].                  

%% @spec rep_receive(fun((function()) -> term())) -> term()
%% @doc: Function called right before a receive statement.
%%
%% If a matching message is found in the process' message queue, continue
%% to actual receive statement, else block and when unblocked do the same.
-spec rep_receive(fun((term()) -> 'block' | 'continue'), boolean()) -> 'ok'.
rep_receive(Fun, HasTimeout) ->
    case ?LID_FROM_PID(self()) of
        not_found ->
            %% XXX: Uninstrumented process enters instrumented receive
            ok; 
        _Lid ->
            rep_receive_loop(poll, Fun, HasTimeout)
    end.

rep_receive_loop(Act, Fun, HasTimeout) ->
    case Act of
        Resume when Resume =:= ok;
                    Resume =:= continue -> ok;
        poll ->
            {messages, Mailbox} = process_info(self(), messages),
            case rep_receive_match(Fun, Mailbox) of
                block ->
                    NewAct =
                        case HasTimeout of
                            infinity -> concuerror_sched:notify('receive', blocked);
                            _ ->
                                NewFun =
                                    fun(Msg) ->
                                        case rep_receive_match(Fun, [Msg]) of
                                            block -> false;
                                            continue -> true
                                        end
                                    end,
                                concuerror_sched:notify('after', NewFun)
                        end,
                    rep_receive_loop(NewAct, Fun, HasTimeout);
                continue ->
                    Tag =
                        case HasTimeout of
                            infinity -> unblocked;
                            _ -> had_after
                        end,
                    continue = concuerror_sched:notify('receive', Tag),
                    ok
            end
    end.

rep_receive_match(_Fun, []) ->
    block;
rep_receive_match(Fun, [H|T]) ->
    case Fun(H) of
        block -> rep_receive_match(Fun, T);
        continue -> continue
    end.

%% Blocks forever (used for 'receive after infinity -> ...' expressions).
-spec rep_receive_block() -> no_return().
rep_receive_block() ->
    Fun = fun(_Message) -> block end,
    rep_receive(Fun, infinity).

%% @spec rep_after_notify() -> 'ok'
%% @doc: Auxiliary function used in the `receive..after' statement
%% instrumentation.
%%
%% Called first thing after an `after' clause has been entered.
-spec rep_after_notify() -> 'ok'.
rep_after_notify() ->
    ok.

%% @spec rep_receive_notify(pid(), term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statement instrumentation.
%%
%% Called first thing after a message has been received, to inform the scheduler
%% about the message received and the sender.
-spec rep_receive_notify(pid(), dict(), term()) -> 'ok'.
rep_receive_notify(From, CV, Msg) ->
    concuerror_sched:notify('receive', {From, CV, Msg}, prev),
    ok.

%% @spec rep_receive_notify(term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statement instrumentation.
%%
%% Similar to rep_receive/2, but used to handle 'EXIT' and 'DOWN' messages.
-spec rep_receive_notify(term()) -> no_return().
rep_receive_notify(Msg) ->
    %% XXX: Received uninstrumented message
    ok.

%% @spec rep_register(atom(), pid() | port()) -> 'true'
%% @doc: Replacement for `register/2'.
%%
%% Just yield after registering.
-spec rep_register(atom(), pid() | port()) -> 'true'.
rep_register(RegName, P) ->
    case ?LID_FROM_PID(P) of
        not_found -> ok;
        PLid ->
            concuerror_sched:notify(register, {RegName, PLid})
    end,
    register(RegName, P).

%% @spec rep_send(dest(), term()) -> term()
%% @doc: Replacement for `send/2' (and the equivalent `!' operator).
%%
%% If the target has a registered LID then instrument the message
%% and yield after sending. Otherwise, send the original message
%% and continue without yielding.
-spec rep_send(dest(), term()) -> term().
rep_send(Dest, Msg) ->
    case ?LID_FROM_PID(self()) of
        not_found ->
            %% Unknown process sends using instrumented code. Allow it.
            %% It will be reported at the receive point.
            Dest ! Msg;
        _SelfLid ->
            PlanLid = ?LID_FROM_PID(find_pid(Dest)),
            concuerror_sched:notify(send, {Dest, PlanLid, Msg}),
            SendLid = ?LID_FROM_PID(find_pid(Dest)),
            concuerror_sched:notify(send, {Dest, SendLid, Msg}, prev),
            Dest ! Msg
    end.

%% @spec rep_send(dest(), term(), ['nosuspend' | 'noconnect']) ->
%%                      'ok' | 'nosuspend' | 'noconnect'
%% @doc: Replacement for `send/3'.
%%
%% For now, call erlang:send/3, but ignore options in internal handling.
-spec rep_send(dest(), term(), ['nosuspend' | 'noconnect']) ->
                      'ok' | 'nosuspend' | 'noconnect'.
rep_send(Dest, Msg, Opt) ->
    case ?LID_FROM_PID(self()) of
        not_found ->
            %% Unknown process sends using instrumented code. Allow it.
            %% It will be reported at the receive point.
            erlang:send(Dest, Msg, Opt);
        _SelfLid ->
            PlanLid = ?LID_FROM_PID(find_pid(Dest)),
            concuerror_sched:notify(send, {Dest, PlanLid, Msg}),
            SendLid = ?LID_FROM_PID(find_pid(Dest)),
            concuerror_sched:notify(send, {Dest, SendLid, Msg}, prev),
            erlang:send(Dest, Msg, Opt)
    end.

%% @spec rep_spawn(function()) -> pid()
%% @doc: Replacement for `spawn/1'.
%%
%% The argument provided is the argument of the original spawn call.
%% Before spawned, the new process has to yield.
-spec rep_spawn(function()) -> pid().
rep_spawn(Fun) ->
    spawn_center(spawn, Fun).

spawn_center(Kind, Fun) ->
    Spawner =
        case Kind of
            spawn -> fun spawn/1;
            spawn_link -> fun spawn_link/1;
            spawn_monitor -> fun spawn_monitor/1
        end,
    case ?LID_FROM_PID(self()) of
        not_found -> Spawner(Fun);
        _Lid ->
            concuerror_sched:notify(Kind, unknown),
            Result = Spawner(fun() -> spawn_fun_wrapper(Fun) end),
            concuerror_sched:notify(Kind, Result, prev),
            %% Wait before using the PID to be sure that an LID is assigned
            concuerror_sched:wait(),
            Result
    end.

-spec spawn_fun_wrapper(function()) -> term().
spawn_fun_wrapper(Fun) ->
    try
        concuerror_sched:wait(),
        Fun(),
        exit(normal)
    catch
        exit:normal ->
            MyInfo = find_my_info(),
            concuerror_sched:notify(exit, {normal, MyInfo}),
            MyRealInfo = find_my_info(),
            concuerror_sched:notify(exit, {normal, MyRealInfo}, prev);
        Class:Type ->
            concuerror_sched:notify(error,[Class,Type,erlang:get_stacktrace()]),
            case Class of
                error -> error(Type);
                throw -> throw(Type);
                exit  -> exit(Type)
            end
    end.                    

find_my_info() ->
    MyEts = find_my_ets_tables(),
    MyName = find_my_registered_name(),
    MyLinks = find_my_links(),
    {MyEts, MyName, MyLinks}.

find_my_ets_tables() ->
    Self = self(),
    MyTIDs = [TID || TID <- ets:all(), Self =:= ets:info(TID, owner)],
    Fold =
        fun(TID, {HeirsAcc, TablesAcc}) ->
            Survives =
                case ets:info(TID, heir) of
                    none -> false;
                    Self -> false;
                    Pid ->
                        case is_process_alive(Pid) of
                            false -> false;
                            true ->
                                case ?LID_FROM_PID(Pid) of
                                    not_found -> false;
                                    HeirLid0 -> {true, HeirLid0}
                                end
                        end
                end,
            case Survives of
                false ->
                    T =
                        {?LID_FROM_PID(TID),
                         case ets:info(TID, named_table) of
                             true -> {ok, ets:info(TID, name)};
                             false -> none
                         end},
                    {HeirsAcc, [T|TablesAcc]};
                {true, HeirLid} ->
                    {[HeirLid|HeirsAcc], TablesAcc}
            end
        end,
    lists:foldl(Fold, {[], []}, MyTIDs).

find_my_registered_name() ->
    case process_info(self(), registered_name) of
        [] -> none;
        {registered_name, Name} -> {ok, Name}
    end.

%% @spec rep_spawn(atom(), atom(), [term()]) -> pid()
%% @doc: Replacement for `spawn/3'.
%%
%% See `rep_spawn/1'.
-spec rep_spawn(atom(), atom(), [term()]) -> pid().
rep_spawn(Module, Function, Args) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn(Fun).

%% @spec rep_spawn_link(function()) -> pid()
%% @doc: Replacement for `spawn_link/1'.
%%
%% Before spawned, the new process has to yield.
-spec rep_spawn_link(function()) -> pid().

rep_spawn_link(Fun) ->
    spawn_center(spawn_link, Fun).

%% @spec rep_spawn_link(atom(), atom(), [term()]) -> pid()
%% @doc: Replacement for `spawn_link/3'.
%%
%% See `rep_spawn_link/1'.
-spec rep_spawn_link(atom(), atom(), [term()]) -> pid().
rep_spawn_link(Module, Function, Args) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_link(Fun).

%% @spec rep_spawn_monitor(function()) -> {pid(), reference()}
%% @doc: Replacement for `spawn_monitor/1'.
%%
%% Before spawned, the new process has to yield.
-spec rep_spawn_monitor(function()) -> {pid(), reference()}.
rep_spawn_monitor(Fun) ->
    spawn_center(spawn_monitor, Fun).

%% @spec rep_spawn_monitor(atom(), atom(), [term()]) -> {pid(), reference()}
%% @doc: Replacement for `spawn_monitor/3'.
%%
%% See rep_spawn_monitor/1.
-spec rep_spawn_monitor(atom(), atom(), [term()]) -> {pid(), reference()}.
rep_spawn_monitor(Module, Function, Args) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_monitor(Fun).

%% @spec rep_spawn_opt(function(),
%%       ['link' | 'monitor' |
%%                   {'priority', process_priority_level()} |
%%        {'fullsweep_after', integer()} |
%%        {'min_heap_size', integer()} |
%%        {'min_bin_vheap_size', integer()}]) ->
%%       pid() | {pid(), reference()}
%% @doc: Replacement for `spawn_opt/2'.
%%
%% Before spawned, the new process has to yield.
-spec rep_spawn_opt(function(),
                    ['link' | 'monitor' |
                     {'priority', process_priority_level()} |
                     {'fullsweep_after', integer()} |
                     {'min_heap_size', integer()} |
                     {'min_bin_vheap_size', integer()}]) ->
                           pid() | {pid(), reference()}.
rep_spawn_opt(Fun, Opt) ->
    case ?LID_FROM_PID(self()) of
        not_found -> spawn_opt(Fun, Opt);
        _Lid ->
            concuerror_sched:notify(spawn_opt, unknown),
            Result = spawn_opt(fun() -> spawn_fun_wrapper(Fun) end, Opt),
            concuerror_sched:notify(spawn_opt, Result, prev),
            %% Wait before using the PID to be sure that an LID is assigned
            concuerror_sched:wait(),
            Result
    end.

%% @spec rep_spawn_opt(atom(), atom(), [term()],
%%       ['link' | 'monitor' |
%%                   {'priority', process_priority_level()} |
%%        {'fullsweep_after', integer()} |
%%        {'min_heap_size', integer()} |
%%        {'min_bin_vheap_size', integer()}]) ->
%%       pid() | {pid(), reference()}
%% @doc: Replacement for `spawn_opt/4'.
%%
%% Before spawned, the new process has to yield.
-spec rep_spawn_opt(atom(), atom(), [term()],
                    ['link' | 'monitor' |
                     {'priority', process_priority_level()} |
                     {'fullsweep_after', integer()} |
                     {'min_heap_size', integer()} |
                     {'min_bin_vheap_size', integer()}]) ->
                           pid() | {pid(), reference()}.

rep_spawn_opt(Module, Function, Args, Opt) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_opt(Fun, Opt).

%% @spec: rep_unlink(pid() | port()) -> 'true'
%% @doc: Replacement for `unlink/1'.
%%
%% Just yield before unlinking.
-spec rep_unlink(pid() | port()) -> 'true'.
rep_unlink(Pid) ->
    case ?LID_FROM_PID(Pid) of
        not_found -> ok;
        PLid -> concuerror_sched:notify(unlink, PLid)
    end,
    unlink(Pid).

%% @spec rep_unregister(atom()) -> 'true'
%% @doc: Replacement for `unregister/1'.
%%
%% Just yield before unregistering.
-spec rep_unregister(atom()) -> 'true'.
rep_unregister(RegName) ->
    concuerror_sched:notify(unregister, RegName),
    unregister(RegName).

%% @spec rep_whereis(atom()) -> pid() | port() | 'undefined'
%% @doc: Replacement for `whereis/1'.
%%
%% Just yield before calling whereis/1.
-spec rep_whereis(atom()) -> pid() | port() | 'undefined'.
rep_whereis(RegName) ->
    concuerror_sched:notify(whereis, {RegName, unknown}),
    R = whereis(RegName),
    Value =
        case R =:= undefined of
            true -> not_found;
            false -> ?LID_FROM_PID(R)
        end,
    concuerror_sched:notify(whereis, {RegName, Value}, prev),
    R.

%%%----------------------------------------------------------------------
%%% ETS replacements
%%%----------------------------------------------------------------------
rep_ets_new(Name, Options) ->
    concuerror_sched:notify(ets, {new, [unknown, Name, Options]}),
    try
        Tid = ets:new(Name, Options),
        concuerror_sched:notify(ets, {new, [Tid, Name, Options]}, prev),
        concuerror_sched:wait(),
        Tid
    catch
        _:_ ->
	        %% Report a fake tid...
            concuerror_sched:notify(ets, {new, [-1, Name, Options]}, prev),
            concuerror_sched:wait(),
            %% And throw the error again...
            ets:new(Name, Options)
    end.

rep_ets_insert(Tab, Obj) ->
    ets_insert_center(insert, Tab, Obj).

rep_ets_insert_new(Tab, Obj) ->
    ets_insert_center(insert_new, Tab, Obj).

ets_insert_center(Type, Tab, Obj) ->
    KeyPos = ets:info(Tab, keypos),
    Lid = ?LID_FROM_PID(Tab),
    ConvObj =
        case is_tuple(Obj) of
            true -> [Obj];
            false -> Obj
        end,
    Keys = ordsets:from_list([element(KeyPos, O) || O <- ConvObj]),
    concuerror_sched:notify(ets, {Type, [Lid, Tab, Keys, KeyPos, ConvObj, true]}),
    case Type of
        insert -> ets:insert(Tab, Obj);
        insert_new ->
            Ret = ets:insert_new(Tab, Obj),
            Info = {Type, [Lid, Tab, Keys, KeyPos, ConvObj, Ret]},
            concuerror_sched:notify(ets, Info, prev),
            Ret
    end.

rep_ets_lookup(Tab, Key) ->
    Lid = ?LID_FROM_PID(Tab),
    concuerror_sched:notify(ets, {lookup, [Lid, Tab, Key]}),
    ets:lookup(Tab, Key).

rep_ets_delete(Tab) ->
    concuerror_sched:notify(ets, {delete, [?LID_FROM_PID(Tab), Tab]}),
    ets:delete(Tab).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

find_pid(Pid) when is_pid(Pid) ->
    Pid;
find_pid(Atom) when is_atom(Atom) ->
    whereis(Atom);
find_pid(Other) ->
    Other.


%%%-------------------------------------------------------------------
%%% Missing
%%%-------------------------------------------------------------------
rep_ets_delete(_, _) ->
    concuerror_log:interlan("Missing function: ~p\n", [rep_ets_delete]).

rep_ets_foldl(_, _, _) ->
    concuerror_log:interlan("Missing function: ~p\n", [rep_ets_foldl]).

rep_ets_match_delete(_, _) ->
    concuerror_log:interlan("Missing function: ~p\n", [rep_ets_match_delete]).

rep_ets_match_object(_) ->
    concuerror_log:interlan("Missing function: ~p\n", [rep_ets_match_object]).

rep_ets_match_object(_, _, _) ->
    concuerror_log:interlan("Missing function: ~p\n", [rep_ets_match_object]).

rep_ets_select_delete(_, _) ->
    concuerror_log:interlan("Missing function: ~p\n", [rep_ets_select_delete]).
