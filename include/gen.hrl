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

%% Module containing replacement functions.
-define(REP_MOD, concuerror_rep).

%% Instrumented message atom.
-define(INSTR_MSG, '_._instr_msg').

%% Set-like data structure used in sched, lid and error modules.
-define(SETS, ordsets).
-define(SET_TYPE(X), [X]). %% XXX: bad -- ordsets does not export the type!

%% Default options
-define(DEFAULT_PREB, 2).
-define(DEFAULT_INCLUDE, []).
-define(DEFAULT_DEFINE, []).

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
-ifdef(DEBUG_LEVEL_1).
-define(debug_1(S_, L_), io:format("(D-1) " ++ S_, L_)).
-define(debug_1(S_), io:format("(D-1) " ++ S_)).
-else.
-define(debug_1(S_, L_), ok).
-define(debug_1(S_), ok).
-endif.

-ifdef(DEBUG_LEVEL_2).
-define(debug_2(S_, L_), io:format("|--(D-2) " ++ S_, L_)).
-define(debug_2(S_), io:format("|--(D-2) " ++ S_)).
-else.
-define(debug_2(S_, L_), ok).
-define(debug_2(S_), ok).
-endif.
