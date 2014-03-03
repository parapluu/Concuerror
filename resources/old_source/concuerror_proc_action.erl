%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Author      : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Process action interface
%%%----------------------------------------------------------------------

-module(concuerror_proc_action).

-export([to_string/1]).

-export_type([proc_action/0]).

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Printing depth of terms like messages or exit reasons.
-define(PRINT_DEPTH, 4).
-define(PRINT_DEPTH_EXIT, 10).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type spawn_opt_opts() :: ['link' | 'monitor'].

%% Tuples providing information about a process' action.
-type proc_action() :: {'after', concuerror_lid:lid()} |
                       {'block', concuerror_lid:lid()} |
                       {'demonitor', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid()} |
                       {'exit', concuerror_lid:lid(), term()} |
                       {'exit_2', concuerror_lid:lid(),
                                  concuerror_lid:lid(), term()} |
                       {'fun_exit', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid(), term()} |
                       {'halt', concuerror_lid:lid()} |
                       {'halt', concuerror_lid:lid(),
                                    non_neg_integer() | string()} |
                       {'is_process_alive', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid()} |
                       {'link', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid()} |
                       {'monitor', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid()} |
                       {'process_flag', concuerror_lid:lid(),
                                    'trap_exit', boolean()} |
                       {'receive', concuerror_lid:lid(),
                                    concuerror_lid:lid(), term()} |
                       {'receive_no_instr', concuerror_lid:lid(), term()} |
                       {'register', concuerror_lid:lid(),
                                    atom(), concuerror_lid:lid()} |
                       {'send', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid(), term()} |
                       {'send_after', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid(), term()} |
                       {'start_timer', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid(), term()} |
                       {'spawn', concuerror_lid:maybe_lid(),
                                    concuerror_lid:lid()} |
                       {'spawn_link', concuerror_lid:maybe_lid(),
                                    concuerror_lid:lid()} |
                       {'spawn_monitor', concuerror_lid:maybe_lid(),
                                    concuerror_lid:lid()} |
                       {'spawn_opt', concuerror_lid:maybe_lid(),
                                    concuerror_lid:lid(), spawn_opt_opts()} |
                       {'unlink', concuerror_lid:lid(),
                                    concuerror_lid:maybe_lid()} |
                       {'unregister', concuerror_lid:lid(), atom()} |
                       {'port_command', concuerror_lid:lid(), port()} |
                       {'port_control', concuerror_lid:lid(), port()} |
                       {'whereis', concuerror_lid:lid(), atom(),
                                    concuerror_lid:maybe_lid()}.

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

-spec to_string(proc_action()) -> string().

to_string({'after', Proc}) ->
    io_lib:format("Process ~s receives no matching messages",
                  [concuerror_lid:to_string(Proc)]);
to_string({block, Proc}) ->
    io_lib:format("Process ~s blocks", [concuerror_lid:to_string(Proc)]);
to_string({demonitor, Proc, not_found}) ->
    io_lib:format("Process ~s demonitors nonexisting process",
                  [concuerror_lid:to_string(Proc)]);
to_string({demonitor, Proc1, Proc2}) ->
    io_lib:format("Process ~s demonitors process ~s",
                  [concuerror_lid:to_string(Proc1),
                   concuerror_lid:to_string(Proc2)]);
to_string({exit, Proc, Reason}) ->
    io_lib:format("Process ~s exits (~P)",
                  [concuerror_lid:to_string(Proc),
                   Reason, ?PRINT_DEPTH_EXIT]);
to_string({exit_2, From, To, Reason}) ->
    io_lib:format("Process ~s sends an exit signal to ~p (~P)",
                  [concuerror_lid:to_string(From),
                   concuerror_lid:to_string(To),
                   Reason, ?PRINT_DEPTH_EXIT]);
to_string({fun_exit, Proc, not_found, Reason}) ->
    io_lib:format("Process ~s sends exit signal (~W) to nonexisting process",
                  [concuerror_lid:to_string(Proc),
                   Reason, ?PRINT_DEPTH]);
to_string({fun_exit, Proc, Target, Reason}) ->
    io_lib:format("Process ~s sends exit signal (~p) to process ~s",
                  [concuerror_lid:to_string(Proc),
                   Reason, concuerror_lid:to_string(Target)]);
to_string({halt, Proc}) ->
    io_lib:format("Process ~s halts the system",
                  [concuerror_lid:to_string(Proc)]);
to_string({halt, Proc, Status}) ->
    io_lib:format("Process ~s halts the system with status ~p",
                  [concuerror_lid:to_string(Proc), Status]);
to_string({is_process_alive, Proc, not_found}) ->
    io_lib:format("Process ~s checks if nonexisting process is alive",
                  [concuerror_lid:to_string(Proc)]);
to_string({is_process_alive, Proc1, Proc2}) ->
    io_lib:format("Process ~s checks if process ~s is alive",
                  [concuerror_lid:to_string(Proc1),
                   concuerror_lid:to_string(Proc2)]);
to_string({link, Proc, not_found}) ->
    io_lib:format("Process ~s links to nonexisting process",
                  [concuerror_lid:to_string(Proc)]);
to_string({link, Proc1, Proc2}) ->
    io_lib:format("Process ~s links to process ~s",
                  [concuerror_lid:to_string(Proc1),
                   concuerror_lid:to_string(Proc2)]);
to_string({monitor, Proc, not_found}) ->
    io_lib:format("Process ~s monitors nonexisting process",
                  [concuerror_lid:to_string(Proc)]);
to_string({monitor, Proc1, Proc2}) ->
    io_lib:format("Process ~s monitors process ~s",
                  [concuerror_lid:to_string(Proc1),
                   concuerror_lid:to_string(Proc2)]);
to_string({'process_flag', Proc, Flag, Value}) ->
    io_lib:format("Process ~s sets flag `~p` to `~p`",
                  [concuerror_lid:to_string(Proc), Flag, Value]);
to_string({'receive', Receiver, Sender, Msg}) ->
    io_lib:format("Process ~s receives message `~W` from process ~s",
                  [concuerror_lid:to_string(Receiver), Msg, ?PRINT_DEPTH,
                   concuerror_lid:to_string(Sender)]);
to_string({'receive_no_instr', Receiver, Msg}) ->
    io_lib:format("Process ~s receives message `~W` from unknown process",
                  [concuerror_lid:to_string(Receiver), Msg, ?PRINT_DEPTH]);
to_string({register, Proc, RegName, RegLid}) ->
    io_lib:format("Process ~s registers process ~s as `~p`",
                  [concuerror_lid:to_string(Proc),
                   concuerror_lid:to_string(RegLid), RegName]);
to_string({send, Sender, not_found, Msg}) ->
    io_lib:format("Process ~s sends message `~W` to nonexisting process",
                  [concuerror_lid:to_string(Sender), Msg, ?PRINT_DEPTH]);
to_string({send, Sender, Receiver, Msg}) ->
    io_lib:format("Process ~s sends message `~W` to process ~s",
                  [concuerror_lid:to_string(Sender), Msg, ?PRINT_DEPTH,
                   concuerror_lid:to_string(Receiver)]);
to_string({send_after, Sender, Receiver, Msg}) ->
    io_lib:format("Process ~s sends message `~W` to process ~s (send_after emulated as send)",
                  [concuerror_lid:to_string(Sender), Msg, ?PRINT_DEPTH,
                   concuerror_lid:to_string(Receiver)]);
to_string({start_timer, Sender, Receiver, Msg}) ->
    io_lib:format("Process ~s sets a timer, with message `~W` to process ~s (expires immediately)",
                  [concuerror_lid:to_string(Sender), Msg, ?PRINT_DEPTH,
                   concuerror_lid:to_string(Receiver)]);
to_string({spawn, not_found, Child}) ->
    io_lib:format("Unknown process spawns process ~s",
                  [concuerror_lid:to_string(Child)]);
to_string({spawn, Parent, Child}) ->
    io_lib:format("Process ~s spawns process ~s",
                  [concuerror_lid:to_string(Parent),
                   concuerror_lid:to_string(Child)]);
to_string({spawn_link, not_found, Child}) ->
    io_lib:format("Unknown process spawns and links to process ~s",
                  [concuerror_lid:to_string(Child)]);
to_string({spawn_link, Parent, Child}) ->
    io_lib:format("Process ~s spawns and links to process ~s",
                  [concuerror_lid:to_string(Parent),
                   concuerror_lid:to_string(Child)]);
to_string({spawn_monitor, not_found, Child}) ->
    io_lib:format("Unknown process spawns and monitors process ~s",
                  [concuerror_lid:to_string(Child)]);
to_string({spawn_monitor, Parent, Child}) ->
    io_lib:format("Process ~s spawns and monitors process ~s",
                  [concuerror_lid:to_string(Parent),
                   concuerror_lid:to_string(Child)]);
to_string({spawn_opt, not_found, Child}) ->
    io_lib:format("Unknown process spawns process ~s with opts",
                  [concuerror_lid:to_string(Child)]);
to_string({spawn_opt, Parent, {Child, _Ref}}) ->
    io_lib:format("Process ~s spawns process ~s with opts (and monitors)",
                  [concuerror_lid:to_string(Parent),
                   concuerror_lid:to_string(Child)]);
to_string({spawn_opt, Parent, Child}) ->
    io_lib:format("Process ~s spawns process ~s with opts",
                  [concuerror_lid:to_string(Parent),
                   concuerror_lid:to_string(Child)]);
to_string({unlink, Proc, not_found}) ->
    io_lib:format("Process ~s unlinks from nonexisting process",
                  [concuerror_lid:to_string(Proc)]);
to_string({unlink, Proc1, Proc2}) ->
    io_lib:format("Process ~s unlinks from process ~s",
                  [concuerror_lid:to_string(Proc1),
                   concuerror_lid:to_string(Proc2)]);
to_string({unregister, Proc, RegName}) ->
    io_lib:format("Process ~s unregisters process `~p`",
                  [concuerror_lid:to_string(Proc), RegName]);
to_string({port_command, Proc, Port}) ->
    io_lib:format("Process ~s sends data to port ~w",
                  [concuerror_lid:to_string(Proc), Port]);
to_string({port_control, Proc, Port}) ->
    io_lib:format("Process ~s performs control operation on port ~w",
                  [concuerror_lid:to_string(Proc), Port]);
to_string({whereis, Proc, RegName, not_found}) ->
    io_lib:format("Process ~s requests the pid of unregistered "
                  "process `~p` (undefined)",
                  [concuerror_lid:to_string(Proc), RegName]);
to_string({whereis, Proc, RegName, RegLid}) ->
    io_lib:format("Process ~s requests the pid of process `~p` (~s)",
                  [concuerror_lid:to_string(Proc), RegName,
                   concuerror_lid:to_string(RegLid)]);
to_string({CallMsg, Proc, Args}) ->
    io_lib:format("Process ~s: ~p ~p", [concuerror_lid:to_string(Proc), CallMsg, Args]).
