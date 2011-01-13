%%%----------------------------------------------------------------------
%%% File        : rep.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Replacement BIFs
%%% Created     : 11 Jan 2010
%%%----------------------------------------------------------------------

-module(rep).

-export([rep_after_notify/0, rep_demonitor/1, rep_demonitor/2,
	 rep_exit/2, rep_halt/0, rep_halt/1, rep_link/1,
	 rep_monitor/2, rep_process_flag/2, rep_receive/1,
         rep_receive_block/0, rep_receive_notify/1,
         rep_receive_notify/2, rep_register/2, rep_send/2,
	 rep_send/3, rep_spawn/1, rep_spawn/3, rep_spawn_link/1,
	 rep_spawn_link/3, rep_spawn_monitor/1, rep_spawn_monitor/3,
	 rep_spawn_opt/2, rep_spawn_opt/4, rep_unlink/1,
	 rep_unregister/1, rep_whereis/1]).

-include("gen.hrl").

%%-define(NOBLOCK, true).

%% The destination of a `send' operation.
-type dest() :: pid() | port() | atom() | {atom(), node()}.

%% @spec: rep_demonitor(reference()) -> 'true'
%% @doc: Replacement for `demonitor/1'.
%%
%% Just yield after demonitoring.
-spec rep_demonitor(reference()) -> 'true'.

rep_demonitor(Ref) ->
    Result = demonitor(Ref),
    sched:notify(demonitor, Ref),
    Result.

%% @spec: rep_demonitor(reference(), ['flush' | 'info']) -> 'true'
%% @doc: Replacement for `demonitor/2'.
%%
%% Just yield after demonitoring.
-spec rep_demonitor(reference(), ['flush' | 'info']) -> 'true'.

rep_demonitor(Ref, Opts) ->
    Result = demonitor(Ref, Opts),
    sched:notify(demonitor, Ref),
    Result.

%% @spec: rep_exit(pid(), term()) -> true
%% @doc: Replacement for `exit/2'.
%%
%% Just send exit signal and yield.
-spec rep_exit(pid(), term()) -> 'true'.

rep_exit(Pid, Reason) ->
    Result = exit(Pid, Reason),
    sched:notify(fun_exit, {Pid, Reason}),
    Result.

%% @spec: rep_halt() -> no_return()
%% @doc: Replacement for `halt/0'.
%%
%% Just send halt message and yield.
-spec rep_halt() -> no_return().

rep_halt() ->
    sched:notify(halt, empty).

%% @spec: rep_halt() -> no_return()
%% @doc: Replacement for `halt/1'.
%%
%% Just send halt message and yield.
-spec rep_halt(non_neg_integer() | string()) -> no_return().

rep_halt(Status) ->
    sched:notify(halt, Status).

%% @spec: rep_link(pid() | port()) -> 'true'
%% @doc: Replacement for `link/1'.
%%
%% Just yield after linking.
-spec rep_link(pid() | port()) -> 'true'.

rep_link(Pid) ->
    Result = link(Pid),
    sched:notify(link, Pid),
    Result.

%% @spec: rep_monitor('process', pid() | {atom(), node()} | atom()) ->
%%                           reference()
%% @doc: Replacement for `monitor/2'.
%%
%% Just yield after monitoring.
-spec rep_monitor('process', pid() | {atom(), node()} | atom()) ->
                         reference().

rep_monitor(Type, Item) ->
    Ref = monitor(Type, Item),
    NewItem = find_pid(Item),
    sched:notify(monitor, {NewItem, Ref}),
    Ref.

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
%% Just yield after altering the process flag.
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
    Result = process_flag(Flag, Value),
    sched:notify(process_flag, {Flag, Value}),
    Result;
rep_process_flag(Flag, Value) ->
    process_flag(Flag, Value).

%% @spec rep_receive(fun((function()) -> term())) -> term()
%% @doc: Function called right before a receive statement.
%%
%% If a matching message is found in the process' message queue, continue
%% to actual receive statement, else block and when unblocked do the same.
-spec rep_receive(fun((term()) -> 'block' | 'continue')) -> 'ok'.

-ifdef(NOBLOCK).
rep_receive(_Fun) ->
    ok.
-else.
rep_receive(Fun) ->
    {messages, Mailbox} = process_info(self(), messages),
    case rep_receive_match(Fun, Mailbox) of
	block -> sched:block(), rep_receive(Fun);
	continue -> ok
    end.
-endif.

%% Blocks forever (used for 'receive after infinity -> ...' expressions).
-spec rep_receive_block() -> no_return().

rep_receive_block() ->
    sched:block(),
    rep_receive_block().

rep_receive_match(_Fun, []) ->
    block;
rep_receive_match(Fun, [H|T]) ->
    case Fun(H) of
	block -> rep_receive_match(Fun, T);
	continue -> continue
    end.

%% @spec rep_after_notify() -> 'ok'
%% @doc: Auxiliary function used in the `receive..after' statement
%% instrumentation.
%%
%% Called first thing after an `after' clause has been entered.
-spec rep_after_notify() -> 'ok'.

rep_after_notify() ->
    sched:notify('after', empty),
    ok.

%% @spec rep_receive_notify(pid(), term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statement instrumentation.
%%
%% Called first thing after a message has been received, to inform the scheduler
%% about the message received and the sender.
-spec rep_receive_notify(pid(), term()) -> 'ok'.

rep_receive_notify(From, Msg) ->
    sched:notify('receive', {From, Msg}),
    ok.

%% @spec rep_receive_notify(term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statement instrumentation.
%%
%% Similar to rep_receive/2, but used to handle 'EXIT' and 'DOWN' messages.
-spec rep_receive_notify(term()) -> 'ok'.

rep_receive_notify(Msg) ->
    sched:notify('receive', Msg).

%% @spec rep_register(atom(), pid() | port()) -> 'true'
%% @doc: Replacement for `register/2'.
%%
%% Just yield after registering.
-spec rep_register(atom(), pid() | port()) -> 'true'.

rep_register(RegName, P) ->
    Ret = register(RegName, P),
    sched:notify(register, {RegName, lid:from_pid(P)}),
    Ret.

%% @spec rep_send(dest(), term()) -> term()
%% @doc: Replacement for `send/2' (and the equivalent `!' operator).
%%
%% If the target has a registered LID then instrument the message
%% and yield after sending. Otherwise, send the original message
%% and continue without yielding.
-spec rep_send(dest(), term()) -> term().

rep_send(Dest, Msg) ->
    Self = self(),
    case lid:from_pid(Self) of
	not_found -> Dest ! Msg;
	_SelfLid ->
	    NewDest = find_pid(Dest),
	    case lid:from_pid(NewDest) of
		not_found -> Dest ! Msg;
		_DestLid ->
		    Dest ! {?INSTR_MSG, lid:from_pid(self()), Msg}
	    end,
	    sched:notify(send, {NewDest, Msg}),
	    Msg
    end.

%% @spec rep_send(dest(), term(), ['nosuspend' | 'noconnect']) ->
%%                      'ok' | 'nosuspend' | 'noconnect'
%% @doc: Replacement for `send/3'.
%%
%% For now, call erlang:send/3, but ignore options in internal handling.
-spec rep_send(dest(), term(), ['nosuspend' | 'noconnect']) ->
                      'ok' | 'nosuspend' | 'noconnect'.

rep_send(Dest, Msg, Opt) ->
    Self = self(),
    case lid:from_pid(Self) of
	not_found -> erlang:send(Dest, Msg, Opt);
	_SelfLid ->
	    NewDest = find_pid(Dest),
	    case lid:from_pid(NewDest) of
		not_found -> erlang:send(Dest, Msg, Opt);
		_Lid ->
		    Ret = erlang:send(Dest, {lid:from_pid(self()), Msg}, Opt),
		    sched:notify(send, {NewDest, Msg}),
		    Ret
	    end
    end.

%% @spec rep_spawn(function()) -> pid()
%% @doc: Replacement for `spawn/1'.
%%
%% The argument provided is the argument of the original spawn call.
%% When spawned, the new process has to yield.
-spec rep_spawn(function()) -> pid().

rep_spawn(Fun) ->
    Pid = spawn(fun() -> sched:wait(), Fun() end),
    sched:notify(spawn, Pid),
    Pid.

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
%% When spawned, the new process has to yield.
-spec rep_spawn_link(function()) -> pid().

rep_spawn_link(Fun) ->
    Pid = spawn_link(fun() -> sched:wait(), Fun() end),
    sched:notify(spawn_link, Pid),
    Pid.

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
%% When spawned, the new process has to yield.
-spec rep_spawn_monitor(function()) -> {pid(), reference()}.

rep_spawn_monitor(Fun) ->
    Ret = spawn_monitor(fun() -> sched:wait(), Fun() end),
    sched:notify(spawn_monitor, Ret),
    Ret.

%% @spec rep_spawn_monitor(atom(), atom(), [term()]) -> {pid(), reference()}
%% @doc: Replacement for `spawn_monitor/3'.
%%
%% See rep_spawn_monitor/1.
-spec rep_spawn_monitor(atom(), atom(), [term()]) -> {pid(), reference()}.

rep_spawn_monitor(Module, Function, Args) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_monitor(Fun).

%% @spec rep_spawn_opt(function(),
%% 		    ['link' | 'monitor' |
%%                   {'priority', process_priority_level()} |
%% 		     {'fullsweep_after', integer()} |
%% 		     {'min_heap_size', integer()} |
%% 		     {'min_bin_vheap_size', integer()}]) ->
%% 			   pid() | {pid(), reference()}
%% @doc: Replacement for `spawn_opt/2'.
%%
%% When spawned, the new process has to yield.
-spec rep_spawn_opt(function(),
		    ['link' | 'monitor' |
                     {'priority', process_priority_level()} |
		     {'fullsweep_after', integer()} |
		     {'min_heap_size', integer()} |
		     {'min_bin_vheap_size', integer()}]) ->
			   pid() | {pid(), reference()}.

rep_spawn_opt(Fun, Opt) ->
    Ret = spawn_opt(fun() -> sched:wait(), Fun() end, Opt),
    sched:notify(spawn_opt, {Ret, Opt}),
    Ret.

%% @spec rep_spawn_opt(atom(), atom(), [term()],
%% 		    ['link' | 'monitor' |
%%                   {'priority', process_priority_level()} |
%% 		     {'fullsweep_after', integer()} |
%% 		     {'min_heap_size', integer()} |
%% 		     {'min_bin_vheap_size', integer()}]) ->
%% 			   pid() | {pid(), reference()}
%% @doc: Replacement for `spawn_opt/4'.
%%
%% When spawned, the new process has to yield.
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
%% Just yield after unlinking.
-spec rep_unlink(pid() | port()) -> 'true'.

rep_unlink(Pid) ->
    Result = unlink(Pid),
    sched:notify(unlink, Pid),
    Result.

%% @spec rep_unregister(atom()) -> 'true'
%% @doc: Replacement for `unregister/1'.
%%
%% Just yield after unregistering.
-spec rep_unregister(atom()) -> 'true'.

rep_unregister(RegName) ->
    Ret = unregister(RegName),
    sched:notify(unregister, RegName),
    Ret.

%% @spec rep_whereis(atom()) -> pid() | port() | 'undefined'
%% @doc: Replacement for `whereis/1'.
%%
%% Just yield after calling whereis/1.
-spec rep_whereis(atom()) -> pid() | port() | 'undefined'.

rep_whereis(RegName) ->
    Ret = whereis(RegName),
    sched:notify(whereis, {RegName, Ret}),
    Ret.

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

find_pid(Pid) when is_pid(Pid) ->
    Pid;
find_pid(Port) when is_port(Port) ->
    erlang:port_info(Port, connected);
find_pid(Atom) when is_atom(Atom) ->
    whereis(Atom);
find_pid({Atom, Node}) when is_atom(Atom) andalso is_atom(Node) ->
    rpc:call(Node, erlang, whereis, [Atom]).
