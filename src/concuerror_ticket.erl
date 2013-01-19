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
%%% Description : Error ticket interface
%%%----------------------------------------------------------------------

-module(concuerror_ticket).

-export([new/2, get_error/1, get_details/1, details_to_strings/1, sort/1]).

-export_type([ticket/0]).

-include("gen.hrl").

%% An error ticket containing all the informations about an error
%% and the interleaving that caused it.
-type ticket() :: {concuerror_error:error(),
                   [concuerror_proc_action:proc_action()]}.

%% @doc: Create a new error ticket.
-spec new(concuerror_error:error(), [concuerror_proc_action:proc_action()])
            -> ticket().

new(Error, ErrorDetails) ->
    NewError =
        case Error of
            {exception, {Type, Stacktrace}} ->
                {exception, {Type, clean_stacktrace(Stacktrace)}};
            Error -> Error
        end,
    {NewError, ErrorDetails}.

%% ---------------------------
clean_stacktrace(Stacktrace) ->
    clean_stacktrace(Stacktrace, []).

clean_stacktrace([], Acc) ->
    lists:reverse(Acc);
clean_stacktrace([{?REP_MOD, _, _, _} | Ts], Acc) ->
    %% Ignore concuerror's rep module
    clean_stacktrace(Ts, Acc);
clean_stacktrace([{Mod, Fun, Args, Pos} | Ts], Acc) ->
    %% Rename modules back to their original names
    OldMod = concuerror_instr:old_module_name(Mod),
    %% Rename files after their modules (for now).
    %% TODO: Rename files back to their original names.
    OldFile = atom_to_list(OldMod) ++ ".erl",
    OldPos = lists:keyreplace(file, 1, Pos, {file, OldFile}),
    clean_stacktrace(Ts, [{OldMod, Fun, Args, OldPos} | Acc]).

%% ---------------------------
-spec get_error(ticket()) -> concuerror_error:error().

get_error({Error, _ErrorDetails}) ->
    Error.

-spec get_details(ticket()) -> [concuerror_proc_action:proc_action()].

get_details({_Error, ErrorDetails}) ->
    ErrorDetails.

-spec details_to_strings(ticket()) -> [string()].

details_to_strings({_Error, ErrorDetails}) ->
    [concuerror_proc_action:to_string(Detail) || Detail <- ErrorDetails].

%% Sort a list of tickets according to state.
-spec sort([ticket()]) -> [ticket()].

sort(Tickets) ->
    Compare = fun(T1, T2) -> get_details(T1) =< get_details(T2) end,
    lists:sort(Compare, Tickets).
