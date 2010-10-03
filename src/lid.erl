%%%----------------------------------------------------------------------
%%% File        : lid.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : LID interface
%%% Created     : 25 Sep 2010
%%%----------------------------------------------------------------------

-module(lid).

-export([from_pid/1, new/2, start/0, stop/0, to_pid/1, update_flags/2]).

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
	[{Pid, Lid, _Flags}] -> Lid;
	[] -> not_found
    end.

%% "Register" a new process spawned by the process with LID `ParentLid`.
%% Pid is the new process' erlang pid.
%% If called without a `noparent' argument, it "registers" the first process.
%% Returns the LID of the newly "registered" process.
-spec new(pid(), lid() | 'noparent') -> lid().

new(Pid, noparent) ->
    %% The first process has LID = "P1", has no children spawned at init
    %% and its default list of flags.
    Lid = "P1",
    ets:insert(?NT_LID, {Lid, Pid, 0}),
    ets:insert(?NT_PID, {Pid, Lid, default_flags()}),
    Lid;
new(Pid, ParentLid) ->
    [{ParentLid, _ParentPid, Children}] = ets:lookup(?NT_LID, ParentLid),
    %% Create new process' Lid
    Lid = lists:concat([ParentLid, ".", Children + 1]),
    %% Update parent info (increment children counter).
    ets:update_element(?NT_LID, ParentLid, {3, Children + 1}),
    %% Insert child and flag info.
    ets:insert(?NT_LID, {Lid, Pid, 0}),
    ets:insert(?NT_PID, {Pid, Lid, default_flags()}),
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
    %% Its elements are of the form {Pid, Lid, Flags}.
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
    [{Pid, _Lid, Flags}] = ets:lookup(?NT_PID, Pid),
    ets:update_element(?NT_PID, Pid,
                       {3, lists:keyreplace(Key, 1, Flags, Flag)}).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

default_flags() ->
    [{trap_exit, false}].
