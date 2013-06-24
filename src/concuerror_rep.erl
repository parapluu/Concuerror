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

-export([spawn_fun_wrapper/1,
         start_target/3,
         find_my_links/0]).

-export([rep_var/3, rep_apply/3, rep_send/2, rep_send/3]).

-export([rep_port_command/2, rep_port_command/3, rep_port_control/3]).

-export([rep_spawn/1, rep_spawn/3,
         rep_spawn_link/1, rep_spawn_link/3,
         rep_spawn_opt/2, rep_spawn_opt/4]).

-export([rep_link/1, rep_unlink/1,
         rep_spawn_monitor/1, rep_spawn_monitor/3,
         rep_process_flag/2]).

-export([rep_receive/3, rep_receive_block/0,
         rep_after_notify/0, rep_receive_notify/3,
         rep_receive_notify/1]).

-export([rep_ets_insert_new/2, rep_ets_lookup/2, rep_ets_select_delete/2,
         rep_ets_insert/2, rep_ets_delete/1, rep_ets_delete/2,
         rep_ets_match/2, rep_ets_match/3,
         rep_ets_match_object/2, rep_ets_match_object/3,
         rep_ets_info/1, rep_ets_info/2, rep_ets_filter/3,
         rep_ets_match_delete/2, rep_ets_new/2, rep_ets_foldl/3]).

-export([rep_register/2,
         rep_is_process_alive/1,
         rep_unregister/1,
         rep_whereis/1]).

-export([rep_monitor/2, rep_demonitor/1, rep_demonitor/2]).

-export([rep_halt/0, rep_halt/1]).

-export([rep_start_timer/3, rep_send_after/3]).

-export([rep_exit/2]).

-export([rep_eunit/1]).

-export([debug_print/1, debug_print/2, debug_apply/3]).

-export_type([dest/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions and Types
%%%----------------------------------------------------------------------

%% Return the calling process' LID.
-define(LID_FROM_PID(Pid), concuerror_lid:from_pid(Pid)).

%% The destination of a `send' operation.
-type dest() :: pid() | port() | atom() | {atom(), node()}.

%% Callback function mapping.
%% TODO: Automatically generate this?
-define(INSTR_MOD_FUN,
        [{{erlang, demonitor, 1}, fun rep_demonitor/1},
         {{erlang, demonitor, 2}, fun rep_demonitor/2},
         {{erlang, exit, 2}, fun rep_exit/2},
         {{erlang, halt, 0}, fun rep_halt/0},
         {{erlang, halt, 1}, fun rep_halt/1},
         {{erlang, is_process_alive, 1}, fun rep_is_process_alive/1},
         {{erlang, link, 1}, fun rep_link/1},
         {{erlang, monitor, 2}, fun rep_monitor/2},
         {{erlang, process_flag, 2}, fun rep_process_flag/2},
         {{erlang, register, 2}, fun rep_register/2},
         {{erlang, send, 2}, fun rep_send/2},
         {{erlang, send, 3}, fun rep_send/3},
         {{erlang, send_after, 3}, fun rep_send_after/3},
         {{erlang, spawn, 1}, fun rep_spawn/1},
         {{erlang, spawn, 3}, fun rep_spawn/3},
         {{erlang, spawn_link, 1}, fun rep_spawn_link/1},
         {{erlang, spawn_link, 3}, fun rep_spawn_link/3},
         {{erlang, spawn_monitor, 1}, fun rep_spawn_monitor/1},
         {{erlang, spawn_monitor, 3}, fun rep_spawn_monitor/3},
         {{erlang, spawn_opt, 2}, fun rep_spawn_opt/2},
         {{erlang, spawn_opt, 4}, fun rep_spawn_opt/4},
         {{erlang, start_timer, 3}, fun rep_start_timer/3},
         {{erlang, unlink, 1}, fun rep_unlink/1},
         {{erlang, unregister, 1}, fun rep_unregister/1},
         {{erlang, whereis, 1}, fun rep_whereis/1},
         {{erlang, apply, 3}, fun rep_apply/3},
         {{ets, insert_new, 2}, fun rep_ets_insert_new/2},
         {{ets, lookup, 2}, fun rep_ets_lookup/2},
         {{ets, select_delete, 2}, fun rep_ets_select_delete/2},
         {{ets, insert, 2}, fun rep_ets_insert/2},
         {{ets, delete, 1}, fun rep_ets_delete/1},
         {{ets, delete, 2}, fun rep_ets_delete/2},
         {{ets, match, 2}, fun rep_ets_match/2},
         {{ets, match, 3}, fun rep_ets_match/3},
         {{ets, match_object, 2}, fun rep_ets_match_object/2},
         {{ets, match_object, 3}, fun rep_ets_match_object/3},
         {{ets, match_delete, 2}, fun rep_ets_match_delete/2},
         {{ets, new, 2}, fun rep_ets_new/2},
         {{ets, filter, 3}, fun rep_ets_filter/3},
         {{ets, info, 1}, fun rep_ets_info/1},
         {{ets, info, 2}, fun rep_ets_info/2},
         {{ets, foldl, 3}, fun rep_ets_foldl/3}]).


%%%----------------------------------------------------------------------
%%% Start analysis target module/function
%%%----------------------------------------------------------------------
-spec start_target(module(), term(), [term()]) -> ok.
start_target(Mod, Fun, Args) ->
    InstrAppController = ets:member(?NT_OPTIONS, 'app_controller'),
    AppConModule =
        concuerror_instr:check_module_name(application_controller, none, 0),
    AppModule = concuerror_instr:check_module_name(application, none, 0),
    case InstrAppController of
        true ->
            AppConModule:start({application, kernel, []}),
            AppModule:start(kernel),
            AppModule:start(stdlib),
            ok;
        false ->
            ok
    end,
    apply(Mod, Fun, Args),
    case InstrAppController of
        true ->
            _ = [AppModule:stop(App) ||
                {App, _, _} <- AppModule:loaded_applications()],
            ok;
        false ->
            ok
    end.


%%%----------------------------------------------------------------------
%%% Callbacks
%%%----------------------------------------------------------------------

%% Handle Mod:Fun(Args) calls.
-spec rep_var(module(), atom(), [term()]) -> term().
rep_var(Mod, Fun, Args) ->
    check_unknown_process(),
    LenArgs = length(Args),
    Key = {Mod, Fun, LenArgs},
    case lists:keyfind(Key, 1, ?INSTR_MOD_FUN) of
        {Key, Callback} ->
            apply(Callback, Args);
        false ->
            %% Rename module
            RenameMod = concuerror_instr:check_module_name(Mod, Fun, LenArgs),
            apply(RenameMod, Fun, Args)
    end.

%% Handle apply/3
-spec rep_apply(module(), atom(), [term()]) -> term().
rep_apply(Mod, Fun, Args) ->
    rep_var(Mod, Fun, Args).

%% @spec: rep_demonitor(reference()) -> 'true'
%% @doc: Replacement for `demonitor/1'.
%%
%% Just yield before demonitoring.
-spec rep_demonitor(reference()) -> 'true'.
rep_demonitor(Ref) ->
    check_unknown_process(),
    concuerror_sched:notify(demonitor, concuerror_lid:lookup_ref_lid(Ref)),
    demonitor(Ref).

%% @spec: rep_demonitor(reference(), ['flush' | 'info']) -> 'true'
%% @doc: Replacement for `demonitor/2'.
%%
%% Just yield before demonitoring.
-spec rep_demonitor(reference(), ['flush' | 'info']) -> 'true'.
rep_demonitor(Ref, Opts) ->
    check_unknown_process(),
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
    check_unknown_process(),
    concuerror_sched:notify(halt, empty).

%% @spec: rep_halt() -> no_return()
%% @doc: Replacement for `halt/1'.
%%
%% Just send halt message and yield.
-spec rep_halt(non_neg_integer() | string()) -> no_return().
rep_halt(Status) ->
    check_unknown_process(),
    concuerror_sched:notify(halt, Status).

%% @spec: rep_is_process_alive(pid()) -> boolean()
%% @doc: Replacement for `is_process_alive/1'.
-spec rep_is_process_alive(pid()) -> boolean().
rep_is_process_alive(Pid) ->
    check_unknown_process(),
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
    check_unknown_process(),
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
    check_unknown_process(),
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
    check_unknown_process(),
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
    check_unknown_process(),
    process_flag(Flag, Value).

-spec find_my_links() -> [concuerror_lid:lid()].

find_my_links() ->
    PPid = self(),
    {links, AllPids} = process_info(PPid, links),
    AllLids = [?LID_FROM_PID(Pid) || Pid <- AllPids],
    [KnownLid || KnownLid <- AllLids, KnownLid =/= not_found].

%% @spec rep_receive(
%%          fun((term()) -> 'block' | 'continue'),
%%          integer() | 'infinity',
%%          integer() | 'infinity') -> 'ok'.
%% @doc: Function called right before a receive statement.
%%
%% If a matching message is found in the process' message queue, continue
%% to actual receive statement, else block and when unblocked do the same.
-spec rep_receive(
            fun((term()) -> 'block' | 'continue'),
            integer() | 'infinity',
            integer() | 'infinity') -> 'ok'.
rep_receive(Fun, HasTimeout, IgnoreTimeout) ->
    check_unknown_process(),
    rep_receive_loop(poll, Fun, HasTimeout, IgnoreTimeout).

-define(IGNORE_TIMEOUT(T, B), B =/= 'infinity' andalso T >= B).

rep_receive_loop(Act, Fun, HasTimeout, Bound) ->
    case Act of
        ok -> ok;
        poll ->
            {messages, Mailbox} = process_info(self(), messages),
            case rep_receive_match(Fun, Mailbox) of
                block ->
                    NewAct =
                        case HasTimeout of
                            infinity ->
                                concuerror_sched:notify('receive', blocked);
                            Timeout when ?IGNORE_TIMEOUT(Timeout, Bound) ->
                                concuerror_sched:notify('receive', blocked);
                            _ ->
                                NewFun =
                                    fun(Msg) ->
                                        case rep_receive_match(Fun, [Msg]) of
                                            block -> false;
                                            continue -> true
                                        end
                                    end,
                                Links = find_trappable_links(self()),
                                concuerror_sched:notify('after', {NewFun, Links})
                        end,
                    rep_receive_loop(NewAct, Fun, HasTimeout, Bound);
                continue ->
                    Tag =
                        case HasTimeout of
                            infinity ->
                                unblocked;
                            Timeout when ?IGNORE_TIMEOUT(Timeout, Bound) ->
                                unblocked;
                            _ -> had_after
                        end,
                    ok = concuerror_sched:notify('receive', Tag)
            end
    end.

find_trappable_links(Pid) ->
    try {trap_exit, true} = erlang:process_info(find_pid(Pid), trap_exit) of
        _ -> find_my_links()
    catch
        _:_ -> []
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
    rep_receive(Fun, infinity, infinity).

%% @spec rep_after_notify() -> 'ok'
%% @doc: Auxiliary function used in the `receive..after' statement
%% instrumentation.
%%
%% Called first thing after an `after' clause has been entered.
-spec rep_after_notify() -> 'ok'.
rep_after_notify() ->
    check_unknown_process(),
    concuerror_sched:notify('after', find_trappable_links(self()), prev),
    ok.

%% @spec rep_receive_notify(pid(), term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statement instrumentation.
%%
%% Called first thing after a message has been received, to inform the scheduler
%% about the message received and the sender.
-spec rep_receive_notify(pid(), dict(), term()) -> 'ok'.
rep_receive_notify(From, CV, Msg) ->
    check_unknown_process(),
    concuerror_sched:notify('receive', {From, CV, Msg}, prev),
    ok.

%% @spec rep_receive_notify(term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statement instrumentation.
%%
%% Similar to rep_receive/2, but used to handle 'EXIT' and 'DOWN' messages.
-spec rep_receive_notify(term()) -> no_return().
rep_receive_notify(_Msg) ->
    check_unknown_process(),
    %% XXX: Received uninstrumented message
    ok.

%% @spec rep_register(atom(), pid() | port()) -> 'true'
%% @doc: Replacement for `register/2'.
%%
%% Just yield after registering.
-spec rep_register(atom(), pid() | port()) -> 'true'.
rep_register(RegName, P) ->
    check_unknown_process(),
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
    check_unknown_process(),
    send_center(Dest, Msg),
    Result = Dest ! Msg,
    concuerror_util:wait_messages(find_pid(Dest)),
    Result.

%% @spec rep_send(dest(), term(), ['nosuspend' | 'noconnect']) ->
%%                      'ok' | 'nosuspend' | 'noconnect'
%% @doc: Replacement for `send/3'.
%%
%% For now, call erlang:send/3, but ignore options in internal handling.
-spec rep_send(dest(), term(), ['nosuspend' | 'noconnect']) ->
                      'ok' | 'nosuspend' | 'noconnect'.
rep_send(Dest, Msg, Opt) ->
    check_unknown_process(),
    send_center(Dest, Msg),
    Result = erlang:send(Dest, Msg, Opt),
    concuerror_util:wait_messages(find_pid(Dest)),
    Result.

send_center(Dest, Msg) ->
    PlanLid = ?LID_FROM_PID(find_pid(Dest)),
    concuerror_sched:notify(send, {Dest, PlanLid, Msg}),
    SendLid = ?LID_FROM_PID(find_pid(Dest)),
    concuerror_sched:notify(send, {Dest, SendLid, Msg}, prev),
    ok.

%% @spec rep_spawn(function()) -> pid()
%% @doc: Replacement for `spawn/1'.
%%
%% The argument provided is the argument of the original spawn call.
%% Before spawned, the new process has to yield.
-spec rep_spawn(function()) -> pid().
rep_spawn(Fun) ->
    spawn_center(spawn, Fun).

spawn_center(Kind, Fun) ->
    check_unknown_process(),
    Spawner =
        case Kind of
            {spawn_opt, Opt} -> fun(F) -> spawn_opt(F, Opt) end;
            spawn -> fun spawn/1;
            spawn_link -> fun spawn_link/1;
            spawn_monitor -> fun spawn_monitor/1
        end,
    {Tag, Info} =
        case Kind of
            {spawn_opt, _} = S -> S;
            _ -> {Kind, unknown}
        end,
    concuerror_sched:notify(Tag, Info),
    Result = Spawner(fun() -> spawn_fun_wrapper(Fun) end),
    concuerror_sched:notify(Tag, Result, prev),
    %% Wait before using the PID to be sure that an LID is assigned
    concuerror_sched:wait(),
    Result.

-spec spawn_fun_wrapper(function()) -> term().
spawn_fun_wrapper(Fun) ->
    try
        ok = concuerror_sched:wait(),
        Fun(),
        exit(normal)
    catch
        exit:Normal when
          (Normal=:=normal orelse
           Normal=:=shutdown orelse
           Normal=:={shutdown, peer_close}) ->
            MyInfo = find_my_info(),
            concuerror_sched:notify(exit, {normal, MyInfo}),
            MyRealInfo = find_my_info(),
            concuerror_sched:notify(exit, {normal, MyRealInfo}, prev);
        Class:Type ->
            concuerror_sched:notify(error,[Class,Type,erlang:get_stacktrace()])
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
    %% Rename module
    LenArgs = length(Args),
    NewModule = concuerror_instr:check_module_name(Module, Function, LenArgs),
    Fun = fun() -> apply(NewModule, Function, Args) end,
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
    %% Rename module
    LenArgs = length(Args),
    NewModule = concuerror_instr:check_module_name(Module, Function, LenArgs),
    Fun = fun() -> apply(NewModule, Function, Args) end,
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
    %% Rename module
    LenArgs = length(Args),
    NewModule = concuerror_instr:check_module_name(Module, Function, LenArgs),
    Fun = fun() -> apply(NewModule, Function, Args) end,
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
    spawn_center({spawn_opt, Opt}, Fun).

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
    %% Rename module
    LenArgs = length(Args),
    NewModule = concuerror_instr:check_module_name(Module, Function, LenArgs),
    Fun = fun() -> apply(NewModule, Function, Args) end,
    rep_spawn_opt(Fun, Opt).

%% @spec: rep_start_timer(non_neg_integer(), pid() | atom(), term()) ->
%%                                                                  reference().
%% @doc: Replacement for `start_timer/3'.
%%
%% TODO: Currently it sends the message immediately and returns a random ref.
-spec rep_start_timer(non_neg_integer(), pid() | atom(), term()) -> reference().
rep_start_timer(Time, Dest, Msg) ->
    check_unknown_process(),
    Ref = make_ref(),
    case ets:lookup(?NT_OPTIONS, 'ignore_timeout') of
        [{'ignore_timeout', ITValue}] when ITValue =< Time ->
            %% Ignore this start_timer operation
            ok;
        _ ->
            concuerror_sched:notify(start_timer, {?LID_FROM_PID(Dest), Msg}),
            Dest ! {timeout, Ref, Msg},
            ok
    end,
    Ref.

%% @spec: rep_send_after(non_neg_integer(), pid() | atom(), term()) ->
%%                                                                 reference().
%% @doc: Replacement for `send_after/3'.
%%
%% TODO: Currently it sends the message immediately and returns a random ref.
-spec rep_send_after(non_neg_integer(), pid() | atom(), term()) -> reference().
rep_send_after(Time, Dest, Msg) ->
    check_unknown_process(),
    case ets:lookup(?NT_OPTIONS, 'ignore_timeout') of
        [{'ignore_timeout', ITValue}] when ITValue =< Time ->
            %% Ignore this send_after operation
            ok;
        _ ->
            concuerror_sched:notify(send_after, {?LID_FROM_PID(Dest), Msg}),
            Dest ! Msg,
            ok
    end,
    make_ref().

%% @spec: rep_exit(pid() | port(), term()) -> 'true'.
%% @doc: Replacement for `exit/2'.
-spec rep_exit(pid() | port(), term()) -> 'true'.
rep_exit(Pid, Reason) ->
    check_unknown_process(),
    concuerror_sched:notify(exit_2, {?LID_FROM_PID(Pid), Reason}),
    exit(Pid, Reason),
    concuerror_util:wait_messages(find_pid(Pid)),
    true.

%% @spec: rep_unlink(pid() | port()) -> 'true'
%% @doc: Replacement for `unlink/1'.
%%
%% Just yield before unlinking.
-spec rep_unlink(pid() | port()) -> 'true'.
rep_unlink(Pid) ->
    check_unknown_process(),
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
    check_unknown_process(),
    concuerror_sched:notify(unregister, RegName),
    unregister(RegName).

%% @spec rep_whereis(atom()) -> pid() | port() | 'undefined'
%% @doc: Replacement for `whereis/1'.
%%
%% Just yield before calling whereis/1.
-spec rep_whereis(atom()) -> pid() | port() | 'undefined'.
rep_whereis(RegName) ->
    check_unknown_process(),
    concuerror_sched:notify(whereis, {RegName, unknown}),
    R = whereis(RegName),
    Value =
        case R =:= undefined of
            true -> not_found;
            false -> ?LID_FROM_PID(R)
        end,
    concuerror_sched:notify(whereis, {RegName, Value}, prev),
    R.

%% @spec rep_port_command(port(), term()) -> true
%% @doc: Replacement for `port_command/2'.
%%
%% Just yield before calling port_command/2.
-spec rep_port_command(port, term()) -> true.
rep_port_command(Port, Data) ->
    check_unknown_process(),
    %concuerror_sched:notify(port_command, Port),
    port_command(Port, Data),
    concuerror_util:wait_messages(not_found),
    true.

%% @spec rep_port_command(port(), term(), [force | nosuspend]) -> boolean()
%% @doc: Replacement for `port_command/3'.
%%
%% Just yield before calling port_command/3.
-spec rep_port_command(port, term(), [force | nosuspend]) -> boolean().
rep_port_command(Port, Data, OptionList) ->
    check_unknown_process(),
    %concuerror_sched:notify(port_command, Port),
    Result = port_command(Port, Data, OptionList),
    concuerror_util:wait_messages(not_found),
    Result.

%% @spec rep_port_control(port(), integer(), term()) -> term()
%% @doc: Replacement for `port_control/3'.
%%
%% Just yield before calling port_control/3.
-spec rep_port_control(port, integer(), term()) -> term().
rep_port_control(Port, Operation, Data) ->
    check_unknown_process(),
    %concuerror_sched:notify(port_control, Port),
    Result = port_control(Port, Operation, Data),
    concuerror_util:wait_messages(not_found),
    Result.


%%%----------------------------------------------------------------------
%%% ETS replacements
%%%----------------------------------------------------------------------
-type ets_new_option() :: ets_new_type() | ets_new_access() | named_table
                        | {keypos,integer()} | {heir,pid(),term()} | {heir,none}
                        | ets_new_tweaks().
-type ets_new_type()   :: set | ordered_set | bag | duplicate_bag.
-type ets_new_access() :: public | protected | private.
-type ets_new_tweaks() :: {write_concurrency,boolean()}
                        | {read_concurrency,boolean()} | compressed.

-spec rep_ets_new(atom(), [ets_new_option()]) -> ets:tab().
rep_ets_new(Name, Options) ->
    check_unknown_process(),
    NewName = rename_ets_table(Name),
    concuerror_sched:notify(ets, {new, [unknown, NewName, Options]}),
    try
        Tid = ets:new(NewName, Options),
        concuerror_sched:notify(ets, {new, [Tid, NewName, Options]}, prev),
        concuerror_sched:wait(),
        Tid
    catch
        _:_ ->
            %% Report a fake tid...
            concuerror_sched:notify(ets, {new, [-1, NewName, Options]}, prev),
            concuerror_sched:wait(),
            %% And throw the error again...
            ets:new(NewName, Options)
    end.

-spec rep_ets_insert(ets:tab(), tuple() | [tuple()]) -> true.
rep_ets_insert(Tab, Obj) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    ets_insert_center(insert, NewTab, Obj).

-spec rep_ets_insert_new(ets:tab(), tuple()|[tuple()]) -> boolean().
rep_ets_insert_new(Tab, Obj) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    ets_insert_center(insert_new, NewTab, Obj).

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
    Fun =
        case Type of
            insert -> fun ets:insert/2;
            insert_new -> fun ets:insert_new/2
        end,
    try
        Ret = Fun(Tab, Obj),
        %% XXX: Hardcoded true to avoid sleep set blocking.
        Info = {Type, [Lid, Tab, Keys, KeyPos, ConvObj, true]}, %Ret]},
        concuerror_sched:notify(ets, Info, prev),
        Ret
    catch
        _:_ ->
            %% Report a fake result...
            FailInfo = {Type, [Lid, Tab, Keys, KeyPos, ConvObj, false]},
            concuerror_sched:notify(ets, FailInfo, prev),
            %% And throw the error again...
            Fun(Tab, Obj)
    end.

-spec rep_ets_lookup(ets:tab(), term()) -> [tuple()].
rep_ets_lookup(Tab, Key) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    Lid = ?LID_FROM_PID(NewTab),
    concuerror_sched:notify(ets, {lookup, [Lid, NewTab, Key]}),
    ets:lookup(NewTab, Key).

-spec rep_ets_delete(ets:tab()) -> true.
rep_ets_delete(Tab) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets, {delete, [?LID_FROM_PID(NewTab), NewTab]}),
    ets:delete(NewTab).

-spec rep_ets_delete(ets:tab(), term()) -> true.
rep_ets_delete(Tab, Key) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets,
        {delete, [?LID_FROM_PID(NewTab), NewTab, Key]}),
    ets:delete(NewTab, Key).

-type match_spec()    :: [{match_pattern(), [term()], [term()]}].
-type match_pattern() :: atom() | tuple().
-spec rep_ets_select_delete(ets:tab(), match_spec()) -> non_neg_integer().
rep_ets_select_delete(Tab, MatchSpec) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets,
        {select_delete, [?LID_FROM_PID(NewTab), NewTab, MatchSpec]}),
    ets:select_delete(NewTab, MatchSpec).

-spec rep_ets_match_delete(ets:tab(), match_pattern()) -> true.
rep_ets_match_delete(Tab, Pattern) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets,
        {match_delete, [?LID_FROM_PID(NewTab), NewTab, Pattern]}),
    ets:match_delete(NewTab, Pattern).

-spec rep_ets_match_object(ets:tab(), tuple()) -> [tuple()].
rep_ets_match_object(Tab, Pattern) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets,
        {match_object, [?LID_FROM_PID(NewTab), NewTab, Pattern]}),
    ets:match_object(NewTab, Pattern).

-spec rep_ets_match_object(ets:tab(), tuple(), integer()) ->
    {[[term()]],term()} | '$end_of_table'.
rep_ets_match_object(Tab, Pattern, Limit) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets,
        {match_object, [?LID_FROM_PID(NewTab), NewTab, Pattern, Limit]}),
    ets:match_object(NewTab, Pattern, Limit).

-spec rep_ets_foldl(fun((term(), term()) -> term()), term(), ets:tab()) -> term().
rep_ets_foldl(Function, Acc, Tab) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets,
        {foldl, [?LID_FROM_PID(NewTab), Function, Acc, NewTab]}),
    ets:foldl(Function, Acc, NewTab).

-spec rep_ets_info(ets:tab()) -> [{atom(), term()}] | undefined.
rep_ets_info(Tab) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets,
        {info, [?LID_FROM_PID(NewTab), NewTab]}),
    ets:info(NewTab).

-spec rep_ets_info(ets:tab(), atom()) -> term() | undefined.
rep_ets_info(Tab, Item) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    concuerror_sched:notify(ets,
        {info, [?LID_FROM_PID(NewTab), NewTab, Item]}),
    ets:info(NewTab, Item).

-spec rep_ets_filter(ets:tab(), fun((term()) -> term()), term()) -> term().
%% XXX: no preemption point for now.
rep_ets_filter(Tab, Fun, Args) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    ets:filter(NewTab, Fun, Args).

-spec rep_ets_match(ets:tab(), term()) -> term().
%%XXX: no preemption point for now.
rep_ets_match(Tab, Pattern) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    ets:match(NewTab, Pattern).

-spec rep_ets_match(ets:tab(), term(), integer()) -> term().
%%XXX: no preemption point for now.
rep_ets_match(Tab, Pattern, Limit) ->
    check_unknown_process(),
    NewTab = rename_ets_table(Tab),
    ets:match(NewTab, Pattern, Limit).


%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

find_pid(Pid) when is_pid(Pid) ->
    Pid;
find_pid(Atom) when is_atom(Atom) ->
    whereis(Atom);
find_pid(Other) ->
    Other.

check_unknown_process() ->
    %% Check if an unknown (not registered)
    %% process is trying to run instrumented code.
    case ?LID_FROM_PID(self()) of
        not_found ->
            Trace = (catch error('Unregistered')),
            concuerror_log:internal("Unregistered process is trying "
                "to run instrumented code\n~p\n", [Trace]);
        _Else -> ok
    end.

%% When instrumenting the application controller rename
%% ac_tab ets table.
rename_ets_table(ac_tab) ->
    InstrAppController = ets:member(?NT_OPTIONS, 'app_controller'),
    case InstrAppController of
        true  -> concuerror_instr:check_module_name(ac_tab, none, 0);
        false -> ac_tab
    end;
rename_ets_table(Tab) -> Tab.

%%%----------------------------------------------------------------------
%%% Run eunit tests using concuerror
%%%----------------------------------------------------------------------

-spec rep_eunit(module()) -> ok.
rep_eunit(Module) ->
    ReModule = concuerror_instr:check_module_name(Module,none,0),
    rep_apply(eunit, start, []),
    rep_apply(eunit, test, [[{module, ReModule}], [no_tty]]),
    rep_apply(eunit, stop, []).


%%%----------------------------------------------------------------------
%%% For debugging purposes
%%% This functions can be executed from inside
%%% instrumented code and will behave as expected
%%% by bypassing Concuerror's instrumenter and scheduler.
%%%----------------------------------------------------------------------

-spec debug_print(io:format()) -> true.
debug_print(Format) ->
    debug_print(Format, []).

-spec debug_print(io:format(), [term()]) -> true.
debug_print(Format, Data) ->
    G = group_leader(),
    InitPid = whereis(init),
    group_leader(InitPid, self()),
    io:format(Format, Data),
    group_leader(G, self()).

-spec debug_apply(module(), atom(), [term()]) -> term().
debug_apply(Mod, Fun, Args) ->
    apply(Mod, Fun, Args).
