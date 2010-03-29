%% Internal message format
-record(gui, {type, msg}).

%% Menu specification:
%%    [{MenuName1, [MenuItem11, MenuItem12, ...]}, ...]
-define(MENU_SPEC,
	[
	 {"&File",
	  [
	   [{id, ?ADD}, {text, "&Add...\tCtrl-A"},  {help, "Add an existing erlang module."}],
	   [{id, ?SEPARATOR}, {kind, ?wxITEM_SEPARATOR}],
	   [{id, ?EXIT}, {help, "Quit PULSE."}]
	  ]
	 },
	 {"&Run",
	  [
	   [{id, ?ANALYZE}, {text, "Ana&lyze\tCtrl-L"}, {help, "Analyze current module."}]
	  ]
	 }, 
	 {"&Help",
	  [
	   [{id, ?ABOUT}, {help, "Show project info."}]
	  ]
	 }
	]).

%% 'About' message
-define(INFO_MSG,
"
                             PULSE
A tool for finding concurrency bugs in Erlang programs.
                          Version 0.1

------------------------------------------------------------------

This is a preliminary version of the PULSE scheduler
described in paper \"Finding Race Conditions in Erlang
with QuickCheck and PULSE\". The work is part of the
Property-based testing project:
http://www.protest-project.eu/

------------------------------------------------------------------
").

%% File paths
-define(SCHEDULER_PATH, "bin/scheduler").
-define(INSTRUMENT_PATH, "bin/instrument").
-define(DRIVER_PATH, "bin/driver").
-define(DOT_PATH, "bin/dot").

-define(ICON_PATH, "img/icon.png").

%% Local ID definitions
-define(ADD, ?wxID_ADD).
-define(REMOVE, ?wxID_REMOVE).
-define(CLEAR, ?wxID_CLEAR).
-define(OPEN, ?wxID_OPEN).
-define(EXIT, ?wxID_EXIT).
-define(ABOUT, ?wxID_ABOUT).
-define(SEPARATOR, ?wxID_SEPARATOR).
-define(FRAME, 500).
-define(ANALYZE, 501).
-define(STATUS_BAR, 502).
-define(MODULE_LIST, 503).
-define(LOG_TEXT, 504).
-define(FUNCTION_LIST, 505).
-define(NOTEBOOK, 506).
-define(GRAPH_PANEL, 507).
-define(SCR_GRAPH, 508).
-define(STATIC_BMP, 509).

%% Color definitions
-define(BASE_COLOR, {2, 63, 90}).
-define(COMP_COLOR, {125, 140, 0}).
