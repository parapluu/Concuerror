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
%%% Description : General header file
%%%----------------------------------------------------------------------

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Application name (atom and string).
-define(APP_ATOM, list_to_atom(?APP_STRING)).

%% Registered process names.
-define(RP_GUI, '_._gui').
-define(RP_GUI_ANALYSIS, '_._gui_analysis').
-define(RP_SCHED, '_._sched').
-define(RP_SCHED_SEND, ?RP_SCHED).
-define(RP_LID, '_._lid').
-define(RP_LID_SEND, ?RP_LID).

%% Named ets table names.
-define(NT_BLOCKED, '_._blocked').
-define(NT_ERROR, '_._error').
-define(NT_LID, '_._lid').
-define(NT_PID, '_._pid').
-define(NT_REF, '_._ref').
-define(NT_STATE1, '_._state1').
-define(NT_STATE2, '_._state2').
-define(NT_STATELEN, '_._state_len').
-define(NT_USED, '_._used').
-define(NT_TIMER, '_._timer').
-define(NT_INSTR_MODS, '_._instr_mods').
-define(NT_INSTR_BIFS, '_._instr_bifs').
-define(NT_INSTR_IGNORED, '_._instr_ignored').
-define(NT_INSTR, '_._instr_table').
-define(NT_OPTIONS, '_._conc_options').

%% Module containing replacement functions.
-define(REP_MOD, concuerror_rep).

%% Instrumented message atom.
-define(INSTR_MSG, '_._instr_msg').
%% Instrumented modules prefix.
-define(INSTR_PREFIX, "conc__").

%% Set-like data structure used in sched, lid and error modules.
-define(SETS, ordsets).
-define(SET_TYPE(X), [X]). %% XXX: bad -- ordsets does not export the type!

%% Default options
-define(DEFAULT_PREB, 2).
-define(DEFAULT_INCLUDE, []).
-define(DEFAULT_DEFINE, []).
-define(DEFAULT_VERBOSITY, 0).

%% Default export file.
-define(EXPORT_EXT,  ".txt").
-define(EXPORT_FILE, "results" ++ ?EXPORT_EXT).

%% Internal error return code.
-define(RET_INTERNAL_ERROR, 1).

%% Host - Node names.
-define(NODE, atom_to_list(node())).
-define(HOST, lists:dropwhile(fun(E) -> E /= $@ end, ?NODE)).

%% 'About' message
-define(INFO_MSG,
"
                           Concuerror
A systematic testing tool for concurrent Erlang programs.
                           Version " ?VSN "
").

%% Debug macros.
-ifdef(COND_DEBUG).
-define(debug_start, put(debug, true)).
-define(debug_stop, erase(debug)).
-define(debug(S_, L_),
        begin
            case get(debug) of
                true -> io:format(S_, L_);
                _ -> ok
            end
        end).
-else.
-define(debug_start, ok).
-define(debug_stop, ok).
-endif.

-ifndef(COND_DEBUG).
-ifdef(DEBUG).
-define(debug(S_, L_), io:format(S_, L_)).
-else.
-define(debug(S_, L_), ok).
-endif. %DEBUG
-endif. %COND_DEBUG


-define(debug(S_), ?debug(S_,[])).
-define(DEBUG_DEPTH, 12).
