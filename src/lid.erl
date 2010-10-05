%%%----------------------------------------------------------------------
%%% File        : lid.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : LID interface
%%% Created     : 25 Sep 2010
%%%----------------------------------------------------------------------

-module(lid).

-export([cleanup/2, from_pid/1, get_linked/1, link/2, new/2,
	 start/0, stop/0, to_pid/1, unlink/2]).

-export_type([lid/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% The following definitions refer to the ?NT_LID table.
-define(pid, 2).
-define(children, 3).
-define(linked, 4).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

%% The logical id (LID) for each process reflects the process' logical
%% position in the program's "process creation tree" and doesn't change
%% between different runs of the same program (as opposed to erlang pids).
-type lid() :: string().

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

%% Cleanup all information of a process.
-spec cleanup(lid(), pid()) -> 'ok'.

cleanup(Lid, Pid) ->
    Linked = get_linked(Lid),
    %% Delete LID table entry of Lid.
    ets:delete(?NT_LID, Lid),
    %% Delete pid table entry.
    ets:delete(?NT_PID, Pid),
    %% Delete all occurrences of Lid in other process' link-sets.
    Fun = fun(L, Unused) ->
                  delete_link(L, Lid),
		  Unused
	  end,
    sets:fold(Fun, unused, Linked).

delete_link(Lid1, Lid2) ->
    OldLinked = get_linked(Lid1),
    NewLinked = sets:del_element(Lid2, OldLinked),
    put_linked(Lid1, NewLinked).

%% Return the LID of process Pid or 'not_found' if mapping not in table.
-spec from_pid(pid()) -> lid() | 'not_found'.

from_pid(Pid) ->
    case ets:lookup(?NT_PID, Pid) of
	[{Pid, Lid}] -> Lid;
	[] -> not_found
    end.

%% Return the LIDs of all processes linked to process Lid.
-spec get_linked(lid()) -> set().

get_linked(Lid) ->
    ets:lookup_element(?NT_LID, Lid, ?linked).

%% Link two LIDs.
-spec link(lid(), lid()) -> boolean().

link(Lid1, Lid2) ->
    LinkedTo1 = get_linked(Lid1),
    put_linked(Lid1, sets:add_element(Lid2, LinkedTo1)),
    LinkedTo2 = get_linked(Lid2),
    put_linked(Lid2, sets:add_element(Lid1, LinkedTo2)).

%% "Register" a new process spawned by the process with LID `ParentLid`.
%% Pid is the new process' erlang pid.
%% If called without a `noparent' argument, it "registers" the first process.
%% Return the LID of the newly "registered" process.
-spec new(pid(), lid() | 'noparent') -> lid().

new(Pid, noparent) ->
    %% The first process has LID = "P1", has no children spawned at init,
    %% has the default list of flags and is not linked to any processes.
    Lid = "P1",
    ets:insert(?NT_LID, {Lid, Pid, 0, sets:new()}),
    ets:insert(?NT_PID, {Pid, Lid}),
    Lid;
new(Pid, ParentLid) ->
    Children = ets:lookup_element(?NT_LID, ParentLid, ?children),
    %% Create new process' Lid
    Lid = lists:concat([ParentLid, ".", Children + 1]),
    %% Update parent info (increment children counter).
    ets:update_element(?NT_LID, ParentLid, {?children, Children + 1}),
    %% Insert child, flag and linking info.
    ets:insert(?NT_LID, {Lid, Pid, 0, sets:new()}),
    ets:insert(?NT_PID, {Pid, Lid}),
    Lid.

%% Update the LIDs of all processes linked to process Lid.
put_linked(Lid, Linked) ->
    ets:update_element(?NT_LID, Lid, {?linked, Linked}).

%% Initialize LID tables.
%% Must be called before any other call to lid_* functions.
-spec start() -> ets:tid() | atom().

start() ->
    %% Table for storing process info.
    %% Its elements are of the form {Lid, Pid, Children, LinkedTo},
    %% where Children is the number of processes spawned by it so far,
    %% Flags is a {Key, Value} list of process flags and LinkedTo is a set
    %% of linked processes.
    ets:new(?NT_LID, [named_table]),
    %% Table for reverse lookup (Lid -> Pid) purposes.
    %% Its elements are of the form {Pid, Lid}.
    ets:new(?NT_PID, [named_table]).

%% Clean up LID tables.
-spec stop() -> 'true'.

stop() ->
    ets:delete(?NT_LID),
    ets:delete(?NT_PID).

%% Return the erlang pid of the process Lid.
-spec to_pid(lid()) -> pid() | 'not_found'.

to_pid(Lid) ->
    try
        ets:lookup_element(?NT_LID, Lid, ?pid)
    catch
        error:badarg -> not_found
    end.

%% Unlink two LIDs.
-spec unlink(lid(), lid()) -> boolean() | 'not_found'.

unlink(Lid1, Lid2) ->
    delete_link(Lid1, Lid2),
    try
        delete_link(Lid2, Lid1)
    catch
        error:badarg -> not_found
    end.
