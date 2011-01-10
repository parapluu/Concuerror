%%%----------------------------------------------------------------------
%%% File        : gen.hrl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : General header file
%%% Created     : 16 May 2010
%%%----------------------------------------------------------------------

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Application name (atom and string).
-define(APP_ATOM, 'CED').
-define(APP_STRING, "CED").

%% Application file.
-define(APP_FILE, ".ced").

%% Registered process names.
-define(RP_GUI, '_._gui').
-define(RP_GUI_ANALYSIS, '_._gui_analysis').
-define(RP_REPLAY_LOGGER, '_._replay_logger').
-define(RP_SCHED, '_._sched').

%% Named ets table names.
-define(NT_BLOCKED, '_._blocked').
-define(NT_ERROR, '_._error').
-define(NT_LID, '_._lid').
-define(NT_PID, '_._pid').
-define(NT_REF, '_._ref').
-define(NT_STATE1, '_._state1').
-define(NT_STATE2, '_._state2').
-define(NT_STATE_TEMP, '_._state_temp').
-define(NT_USED, '_._used').

%% Instrumented message atom.
-define(INSTR_MSG, '_._instr_msg').

%% Set-like data structure used in sched, lid and error modules.
-define(SETS, ordsets).
-define(SET_TYPE(X), [X]). %% XXX: bad -- ordsets does not export the type!

%% Default export file.
-define(EXPORT_FILE, "snapshot").

%% Import directory.
-define(IMPORT_DIR, "import").

%% Internal error return code.
-define(RET_INTERNAL_ERROR, 1).

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

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type file() :: file:filename().
