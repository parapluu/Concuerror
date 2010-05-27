%%%----------------------------------------------------------------------
%%% File    : gen.hrl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : General Header File
%%%
%%% Created : 16 May 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Application name (atom and string).
-define(APP_ATOM, 'CED').
-define(APP_STRING, "CED").

%% Registered process names.
-define(RP_SCHED, '_._sched').

%% Named ets table names.
-define(NT_REF, '_._ref').
-define(NT_PID, '_._pid').
-define(NT_LID, '_._lid').
-define(NT_STATE, '_._state').
-define(NT_USED, '_._used').


%% Internal error return code.
-define(RET_INTERNAL_ERROR, 1).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type file() :: string().
