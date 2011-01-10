%%%----------------------------------------------------------------------
%%% File        : proc_action.erl
%%% Author      : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Process action interface
%%% Created     : 5 Oct 2010
%%%----------------------------------------------------------------------

-module(proc_action).

-export([to_string/1]).

-export_type([proc_action/0]).

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Printing depth of terms like messages or exit reasons.
-define(PRINT_DEPTH, 4).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type maybe_lid() :: lid:lid() | 'not_found'.

-type spawn_opt_opts() :: ['link' | 'monitor'].

%% Tuples providing information about a process' action.
-type proc_action() :: {'after', lid:lid()} |
		       {'block', lid:lid()} |
		       {'demonitor', lid:lid(), maybe_lid()} |
                       {'exit', lid:lid(), term()} |
		       {'fun_exit', lid:lid(), maybe_lid(), term()} |
                       {'halt', lid:lid()} |
                       {'halt', lid:lid(), non_neg_integer() | string()} |
                       {'link', lid:lid(), maybe_lid()} |
		       {'monitor', lid:lid(), maybe_lid()} |
		       {'process_flag', lid:lid(), 'trap_exit', boolean()} |
                       {'receive', lid:lid(), lid:lid(), term()} |
                       {'receive', lid:lid(), term()} |
                       {'register', lid:lid(), atom(), lid:lid()} |
                       {'send', lid:lid(), maybe_lid(), term()} |
                       {'spawn', lid:lid(), lid:lid()} |
		       {'spawn_link', lid:lid(), lid:lid()} |
		       {'spawn_monitor', lid:lid(), lid:lid()} |
		       {'spawn_opt', lid:lid(), lid:lid(), spawn_opt_opts()} |
                       {'unlink', lid:lid(), maybe_lid()} |
                       {'unregister', lid:lid(), atom()} |
                       {'whereis', lid:lid(), atom(), maybe_lid()}.

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

-spec to_string(proc_action()) -> string().

to_string({'after', Proc}) ->
    io_lib:format("Process ~s receives no matching messages",
                  [lid:to_string(Proc)]);
to_string({block, Proc}) ->
    io_lib:format("Process ~s blocks", [lid:to_string(Proc)]);
to_string({demonitor, Proc, not_found}) ->
    io_lib:format("Process ~s demonitors nonexisting process",
		  [lid:to_string(Proc)]);
to_string({demonitor, Proc1, Proc2}) ->
    io_lib:format("Process ~s demonitors process ~s",
		  [lid:to_string(Proc1), lid:to_string(Proc2)]);
to_string({exit, Proc, Reason}) ->
    io_lib:format("Process ~s exits (~W)",
		  [lid:to_string(Proc), Reason, ?PRINT_DEPTH]);
to_string({fun_exit, Proc, not_found, Reason}) ->
    io_lib:format("Process ~s sends exit signal (~W) to nonexisting process",
		  [lid:to_string(Proc), Reason, ?PRINT_DEPTH]);
to_string({fun_exit, Proc, Target, Reason}) ->
    io_lib:format("Process ~s sends exit signal (~p) to process ~s",
		  [lid:to_string(Proc), Reason, lid:to_string(Target)]);
to_string({halt, Proc}) ->
    io_lib:format("Process ~s halts the system", [lid:to_string(Proc)]);
to_string({halt, Proc, Status}) ->
    io_lib:format("Process ~s halts the system with status ~p",
		  [lid:to_string(Proc), Status]);
to_string({link, Proc, not_found}) ->
    io_lib:format("Process ~s links to nonexisting process",
		  [lid:to_string(Proc)]);
to_string({link, Proc1, Proc2}) ->
    io_lib:format("Process ~s links to process ~s",
		  [lid:to_string(Proc1), lid:to_string(Proc2)]);
to_string({monitor, Proc, not_found}) ->
    io_lib:format("Process ~s monitors nonexisting process",
		  [lid:to_string(Proc)]);
to_string({monitor, Proc1, Proc2}) ->
    io_lib:format("Process ~s monitors process ~s",
		  [lid:to_string(Proc1), lid:to_string(Proc2)]);
to_string({'process_flag', Proc, Flag, Value}) ->
    io_lib:format("Process ~s sets flag `~p` to `~p`",
		  [lid:to_string(Proc), Flag, Value]);
to_string({'receive', Receiver, Sender, Msg}) ->
    io_lib:format("Process ~s receives message `~W` from process ~s",
		  [lid:to_string(Receiver), Msg, ?PRINT_DEPTH,
		   lid:to_string(Sender)]);
to_string({'receive', Receiver, Msg}) ->
    io_lib:format("Process ~s receives message `~W`",
		  [lid:to_string(Receiver), Msg, ?PRINT_DEPTH]);
to_string({register, Proc, RegName, RegLid}) ->
    io_lib:format("Process ~s registers process ~s as `~p`",
                  [lid:to_string(Proc), lid:to_string(RegLid), RegName]);
to_string({send, Sender, not_found, Msg}) ->
    io_lib:format("Process ~s sends message `~W` to nonexisting process",
		  [lid:to_string(Sender), Msg, ?PRINT_DEPTH]);
to_string({send, Sender, Receiver, Msg}) ->
    io_lib:format("Process ~s sends message `~W` to process ~s",
		  [lid:to_string(Sender), Msg, ?PRINT_DEPTH,
		   lid:to_string(Receiver)]);
to_string({spawn, Parent, Child}) ->
    io_lib:format("Process ~s spawns process ~s",
		  [lid:to_string(Parent), lid:to_string(Child)]);
to_string({spawn_link, Parent, Child}) ->
    io_lib:format("Process ~s spawns and links to process ~s",
		  [lid:to_string(Parent), lid:to_string(Child)]);
to_string({spawn_monitor, Parent, Child}) ->
    io_lib:format("Process ~s spawns and monitors process ~s",
		  [lid:to_string(Parent), lid:to_string(Child)]);
to_string({spawn_opt, Parent, Child, [link]}) ->
    io_lib:format("Process ~s spawns and links to process ~s",
		  [lid:to_string(Parent), lid:to_string(Child)]);
to_string({spawn_opt, Parent, Child, [monitor]}) ->
    io_lib:format("Process ~s spawns and monitors process ~s",
		  [lid:to_string(Parent), lid:to_string(Child)]);
to_string({spawn_opt, Parent, Child, _Opts}) ->
    io_lib:format("Process ~s spawns, monitors and links to process ~s",
		  [lid:to_string(Parent), lid:to_string(Child)]);
to_string({unlink, Proc, not_found}) ->
    io_lib:format("Process ~s unlinks from nonexisting process",
		  [lid:to_string(Proc)]);
to_string({unlink, Proc1, Proc2}) ->
    io_lib:format("Process ~s unlinks from process ~s",
		  [lid:to_string(Proc1), lid:to_string(Proc2)]);
to_string({unregister, Proc, RegName}) ->
    io_lib:format("Process ~s unregisters process `~p`",
                  [lid:to_string(Proc), RegName]);
to_string({whereis, Proc, RegName, not_found}) ->
    io_lib:format("Process ~s requests the pid of unregistered "
		  "process `~p` (undefined)",
                  [lid:to_string(Proc), RegName]);
to_string({whereis, Proc, RegName, RegLid}) ->
    io_lib:format("Process ~s requests the pid of process `~p` (~s)",
                  [lid:to_string(Proc), RegName, lid:to_string(RegLid)]).
