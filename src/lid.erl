%%%----------------------------------------------------------------------
%%% File        : lid.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : LID interface
%%% Created     : 25 Sep 2010
%%%----------------------------------------------------------------------

-module(lid).

-export([cleanup/1, from_pid/1, fold_pids/2, get_pid/1, mock/1,
	 new/2, start/0, stop/0, to_string/1]).

-export_type([lid/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Information kept in the NT_LID table
%%
%% lid      : The process' LID.
%% pid      : The process' pid.
%% nch      : The number of processes spawned by this process.
-record(info, {lid :: lid(),
	       pid :: pid(),
	       nch :: non_neg_integer()}).

%% Record element positions, only to be used by ets:update_element.
-define(POS_LID, 2).
-define(POS_PID, 3).
-define(POS_NCH, 4).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

%% The logical id (LID) for each process reflects the process' logical
%% position in the program's "process creation tree" and doesn't change
%% between different runs of the same program (as opposed to erlang pids).
-type lid() :: integer().

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

%% Cleanup all information of a process.
-spec cleanup(lid()) -> 'ok'.

cleanup(Lid) ->
    [#info{pid = Pid}] = ets:lookup(?NT_LID, Lid),
    %% Delete LID table entry of Lid.
    ets:delete(?NT_LID, Lid),
    %% Delete pid table entry.
    ets:delete(?NT_PID, Pid),
    ok.

%% Return the LID of process Pid or 'not_found' if mapping not in table.
-spec from_pid(term()) -> lid() | 'not_found'.

from_pid(Pid) when is_pid(Pid) ->
    case ets:lookup(?NT_PID, Pid) of
	[{Pid, Lid}] -> Lid;
	[] -> not_found
    end;
from_pid(_Other) -> not_found.

%% Fold function Fun over all know processes (by Pid).
-spec fold_pids(fun(), term()) -> term().

fold_pids(Fun, InitAcc) ->
    NewFun = fun({P, _L}, Acc) -> Fun(P, Acc) end,
    ets:foldl(NewFun, InitAcc, ?NT_PID).

%% Return a mock LID (only to be used with to_string for now).
-spec mock(integer()) -> lid().
mock(Seed) ->
    Seed.

%% "Register" a new process using its pid (Pid) and its parent's LID (Parent).
%% If called without a `noparent' argument, "register" the first process.
%% Return the LID of the newly "registered" process.
-spec new(pid(), lid() | 'noparent') -> lid().
new(Pid, Parent) ->
    Lid =
	case Parent of
	    noparent -> root_lid();
	    _Other ->
		Children = get_children(Parent),
		set_children(Parent, Children + 1),
		next_lid(Parent, Children)
	end,
    ets:insert(?NT_LID, #info{lid = Lid, pid = Pid, nch = 0}),
    ets:insert(?NT_PID, {Pid, Lid}),
    Lid.

%% Initialize LID tables.
%% Must be called before any other call to lid interface functions.
-spec start() -> 'ok'.

start() ->
    %% Table for storing process info.
    ets:new(?NT_LID, [named_table, {keypos, 2}]),
    %% Table for reverse lookup (Pid -> Lid) purposes.
    %% Its elements are of the form {Pid, Lid}.
    ets:new(?NT_PID, [named_table]),
    start_root(),
    ok.

%% Clean up LID tables.
-spec stop() -> 'true'.

stop() ->
    stop_root(),
    ets:delete(?NT_LID),
    ets:delete(?NT_PID).

%%%----------------------------------------------------------------------
%%% Getter and setter functions
%%%----------------------------------------------------------------------

%% Return the erlang pid of the process Lid.
-spec get_pid(lid()) -> pid() | 'not_found'.

get_pid(Lid) ->
    case ets:lookup(?NT_LID, Lid) of
	[] -> not_found;
	[#info{pid = Pid}] -> Pid
    end.

get_children(Lid) ->
    [#info{nch = Children}] = ets:lookup(?NT_LID, Lid),
    Children.

set_children(Lid, Children) ->
    ets:update_element(?NT_LID, Lid, {?POS_NCH, Children}).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

root_lid() ->
    ?RP_ROOT_LID ! {request, self()},
    receive
	{response, Lid} -> Lid
    end.

start_root() ->
    Pid = spawn(fun() -> root(1) end),
    register(?RP_ROOT_LID, Pid).

stop_root() ->
    ?RP_ROOT_LID ! {stop, self()},
    receive
	{response, ok} -> ok
    end.

root(N) ->
    receive
	{request, Pid} ->
	    Pid ! {response, N},
	    root(N + 1);
	{stop, Pid} -> Pid ! {response, ok}
    end.


%% Create new lid from parent and its number of children.
next_lid(ParentLid, Children) ->
    100 * ParentLid + Children + 1.

-spec to_string(lid()) -> string().

to_string(Lid) ->
    LidString = lists:flatten(io_lib:format("P~p", [Lid])),
    NewLidString = re:replace(LidString, "0", ".", [global]),
    lists:flatten(io_lib:format("~s", [NewLidString])).
