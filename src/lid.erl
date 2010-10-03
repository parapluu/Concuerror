%%%----------------------------------------------------------------------
%%% File        : lid.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : LID interface
%%% Created     : 25 Sep 2010
%%%----------------------------------------------------------------------

-module(lid).

-export([from_pid/1, get_linked/1, get_trapping_exits/1, link/2,
         new/2, start/0, stop/0, to_pid/1, update_flags/2]).

-export_type([lid/0]).

-include("gen.hrl").

%% The logical id (LID) for each process reflects the process' logical
%% position in the program's "process creation tree" and doesn't change
%% between different runs of the same program (as opposed to erlang pids).
-type lid() :: string().

-type flag() :: {'trap_exit', boolean()}.

%% Return the LID of process Pid or 'not_found' if mapping not in table.
-spec from_pid(pid()) -> lid() | 'not_found'.

from_pid(Pid) ->
    case ets:lookup(?NT_PID, Pid) of
	[{Pid, Lid, _Flags, _LinkedTo}] -> Lid;
	[] -> not_found
    end.

%% Return the pids of all processes linked to process Pid.
-spec get_linked(pid()) -> [pid()].

get_linked(Pid) ->
    ets:lookup_element(?NT_PID, Pid, 4).

%% Return the pids of processes Pids that have their 'trap_exit' flag
%% set to true.
-spec get_trapping_exits([pid()]) -> [pid()].

get_trapping_exits(Pids) ->
    get_trapping_exits_aux(Pids, []).

get_trapping_exits_aux([], Acc) ->
    Acc;
get_trapping_exits_aux([Pid|Pids], Acc) ->
    Flags = ets:lookup_element(?NT_PID, Pid, 3),
    {trap_exit, Value} = lists:keyfind(trap_exit, 1, Flags),
    NewAcc =
        case Value of
            true -> [Pid|Acc];
            false -> Acc
        end,
    get_trapping_exits_aux(Pids, NewAcc).

%% Update the linking information of the two pids.
-spec link(pid(), pid()) -> 'true'.

link(Pid1, Pid2) ->
    LinkedTo1 = ets:lookup_element(?NT_PID, Pid1, 4),
    ets:update_element(?NT_PID, Pid1, {4, [Pid2|LinkedTo1]}),
    LinkedTo2 = ets:lookup_element(?NT_PID, Pid2, 4),
    ets:update_element(?NT_PID, Pid2, {4, [Pid1|LinkedTo2]}).

%% "Register" a new process spawned by the process with LID `ParentLid`.
%% Pid is the new process' erlang pid.
%% If called without a `noparent' argument, it "registers" the first process.
%% Return the LID of the newly "registered" process.
-spec new(pid(), lid() | 'noparent') -> lid().

new(Pid, noparent) ->
    %% The first process has LID = "P1", has no children spawned at init,
    %% has the default list of flags and is not linked to any processes.
    Lid = "P1",
    ets:insert(?NT_LID, {Lid, Pid, 0}),
    ets:insert(?NT_PID, {Pid, Lid, default_flags(), []}),
    Lid;
new(Pid, ParentLid) ->
    [{ParentLid, _ParentPid, Children}] = ets:lookup(?NT_LID, ParentLid),
    %% Create new process' Lid
    Lid = lists:concat([ParentLid, ".", Children + 1]),
    %% Update parent info (increment children counter).
    ets:update_element(?NT_LID, ParentLid, {3, Children + 1}),
    %% Insert child, flag and linking info.
    ets:insert(?NT_LID, {Lid, Pid, 0}),
    ets:insert(?NT_PID, {Pid, Lid, default_flags(), []}),
    Lid.

%% Initialize LID tables.
%% Must be called before any other call to lid_* functions.
-spec start() -> ets:tid() | atom().

start() ->
    %% Table for storing process info.
    %% Its elements are of the form {Lid, Pid, Children}, where Children
    %% is the number of processes spawned by it so far.
    ets:new(?NT_LID, [named_table]),
    %% Table for reverse lookup (Lid -> Pid) purposes.
    %% Its elements are of the form {Pid, Lid, Flags, LinkedTo}.
    ets:new(?NT_PID, [named_table]).

%% Clean up LID tables.
-spec stop() -> 'true'.

stop() ->
    ets:delete(?NT_LID),
    ets:delete(?NT_PID).

%% Return the erlang pid of the process Lid.
-spec to_pid(lid()) -> pid().

to_pid(Lid) ->
    ets:lookup_element(?NT_LID, Lid, 2).

%% Update the process flags.
-spec update_flags(pid(), flag()) -> 'true'.

update_flags(Pid, {Key, _Value} = Flag) ->
    Flags = ets:lookup_element(?NT_PID, Pid, 3),
    ets:update_element(?NT_PID, Pid,
                       {3, lists:keyreplace(Key, 1, Flags, Flag)}).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

default_flags() ->
    [{trap_exit, false}].
