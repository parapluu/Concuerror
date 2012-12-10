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
%%% Description : Utilities
%%%----------------------------------------------------------------------

-module(concuerror_util).
-export([doc/1, test/0, flat_format/2, flush_mailbox/0,
         is_erl_source/1, funs/1, funs/2, funLine/3,
         timer_init/0, timer_start/1, timer/1, timer_stop/1, timer_destroy/0]).

-include_lib("kernel/include/file.hrl").
-include("gen.hrl").

%% @spec doc(string()) -> 'ok'
%% @doc: Build documentation using edoc.
-spec doc(string()) -> 'ok'.

doc(AppDir) ->
    AppName = ?APP_ATOM,
    Options = [],
    edoc:application(AppName, AppDir, Options).

%% @spec test() -> 'ok'
%% @doc: Run all EUnit tests for the modules in the `src' directory.
-spec test() -> 'ok'.

test() ->
    Modules = [concuerror_lid,
               concuerror_state,
               concuerror_error,
               concuerror_ticket,
               concuerror_instr],
    Tests = [{module, M} || M <- Modules],
    eunit:test(Tests, [verbose]).

%% @spec flat_format(string(), [term()]) -> string()
%% @doc: Equivalent to lists:flatten(io_lib:format(String, Args)).
-spec flat_format(string(), [term()]) -> string().

flat_format(String, Args) ->
    lists:flatten(io_lib:format(String, Args)).

%% Flush a process' mailbox.
-spec flush_mailbox() -> 'ok'.

flush_mailbox() ->
    receive
        _Any -> flush_mailbox()
    after 0 -> ok
    end.

%% @spec is_erl_source(file:filename()) -> boolean()
%% @doc: Check if file exists and has `.erl' suffix
-spec is_erl_source(file:filename()) -> boolean().

is_erl_source(File) ->
    case filename:extension(File) of
        ".erl" ->
            case file:read_file_info(File) of
                {ok, Info} ->
                    Info#file_info.type == 'regular';
                _Error -> false
            end;
        _Other -> false
    end.

%% @spec funs(string()) -> [{atom(), non_neg_integer()}]
%% @doc: Same as `funs(File, tuple)'.
-spec funs(string()) -> [{atom(), arity()}].

funs(File) ->
    funs(File, tuple).

%% @type: funs_options() = 'tuple' | 'string'.
%% @spec funs(string(), Options::funs_options()) ->
%%              [{atom(), non_neg_integer()}] | [string()]
%% @doc: Scan a file for exported functions.
%%
%% If no `export' attribute is found in the file, all functions of the module
%% are returned.
%% If called with the `tuple' option, a list of {Fun, Arity} tuples is returned,
%% otherwise if called with the `string' option, a list of `"Fun/Arity"' strings
%% is returned.
-spec funs(string(), 'tuple' | 'string') -> [{atom(), arity()}] | [string()].

funs(File, tuple) ->
    {ok, Form} = epp_dodger:quick_parse_file(File),
    getFuns(Form, []);
funs(File, string) ->
    Funs = funs(File, tuple),
    [lists:concat([Name, "/", Arity]) || {Name, Arity} <- Funs].

getFuns([], Funs) ->
    Funs;
getFuns([Node|Rest] = L, Funs) ->
    case erl_syntax:type(Node) of
        attribute ->
            Name = erl_syntax:atom_name(erl_syntax:attribute_name(Node)),
            case Name of
                "export" ->
                    [List] = erl_syntax:attribute_arguments(Node),
                    Args = erl_syntax:list_elements(List),
                    NewFuns = getExports(Args, []),
                    getFuns(Rest, NewFuns ++ Funs);
                _Other -> getFuns(Rest, Funs)
            end;
        function ->
            case Funs of
                [] -> getAllFuns(L, []);
                _Other -> Funs
            end;
        _Other -> getFuns(Rest, Funs)
    end.

getExports([], Exp) ->
    Exp;
getExports([Fun|Rest], Exp) ->
    Name = erl_syntax:atom_name(erl_syntax:arity_qualifier_body(Fun)),
    Arity = erl_syntax:integer_value(erl_syntax:arity_qualifier_argument(Fun)),
    getExports(Rest, [{list_to_atom(Name), Arity}|Exp]).

getAllFuns([], Funs) ->
    Funs;
getAllFuns([Node|Rest], Funs) ->
    case erl_syntax:type(Node) of
        function ->
            Name = erl_syntax:atom_name(erl_syntax:function_name(Node)),
            Arity = erl_syntax:function_arity(Node),
            getAllFuns(Rest, [{list_to_atom(Name), Arity}|Funs]);
        _Other -> getAllFuns(Rest, Funs)
    end.

-spec funLine(string(), atom(), arity()) -> integer().

funLine(File, Function, Arity) ->
    {ok, Form} = epp_dodger:quick_parse_file(File),
    getFunLine(Form, Function, Arity).

getFunLine([], _Function, _Arity) ->
    -1;
getFunLine([Node|Rest], Function, Arity) ->
    case erl_syntax:type(Node) of
        function ->
            F = erl_syntax:atom_name(erl_syntax:function_name(Node)),
            A = erl_syntax:function_arity(Node),
            case (Function =:= list_to_atom(F)) andalso (Arity =:= A) of
                true -> erl_syntax:get_pos(Node);
                false -> getFunLine(Rest, Function, Arity)
            end;
        _Other -> getFunLine(Rest, Function, Arity)
    end.


%% -------------------------------------------------------------------
%% A timer function
%% It returns true only after X msec since the last time.

-spec timer_init() -> ok.
timer_init() ->
    Tweaks = [{write_concurrency,true}, {read_concurrency,true}],
    ?NT_TIMER = ets:new(?NT_TIMER, [set, public, named_table | Tweaks]),
    ok.

-spec timer_start(non_neg_integer()) -> pid().
timer_start(MSec) ->
    %% Create clock
    ClockPid = spawn(fun() -> timer_clock(MSec) end),
    %% Create timer entry
    ets:insert(?NT_TIMER, {ClockPid, false}),
    %% Return the clock pid
    ClockPid.

-spec timer(pid()) -> boolean().
timer(ClockPid) ->
    %% Get Value
    Value = ets:lookup_element(?NT_TIMER, ClockPid, 2),
    %% Reset Value
    case Value of
        true ->
            ets:insert(?NT_TIMER, {ClockPid, false}),
            true;
        false ->
            false
    end.

-spec timer_stop(pid()) -> ok.
timer_stop(ClockPid) ->
    ClockPid ! {self(), stop},
    receive ok -> ok end.

-spec timer_destroy() -> ok.
timer_destroy() ->
    ets:delete(?NT_TIMER).

timer_clock(MSec) ->
    timer_clock(MSec, self()).

timer_clock(MSec, Self) ->
    receive
        {From, stop} ->
            ets:delete(?NT_TIMER, Self),
            From ! ok
    after MSec ->
            %% Set Value
            ets:insert(?NT_TIMER, {Self, true}),
            timer_clock(MSec, Self)
    end.
