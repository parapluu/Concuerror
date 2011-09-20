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
%%% Description : GUI header file
%%%----------------------------------------------------------------------

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Initial frame size.
-define(FRAME_SIZE_INIT, {1024, 768}).

%% Menu specification:
%%    [{MenuName1, [MenuItem11, MenuItem12, ...]}, ...]
-define(MENU_SPEC,
	[{"&File",
          [[{id, ?IMPORT}, {text, "&Import...\tCtrl-I"},
            {help, "Import analysis information from file."},
            {label, ?IMPORT_MENU_ITEM}],
           [{id, ?EXPORT}, {text, "&Export...\tCtrl-E"},
            {help, "Export analysis information to file."},
            {label, ?EXPORT_MENU_ITEM}],
	   [{id, ?wxID_SEPARATOR}, {kind, ?wxITEM_SEPARATOR}],
           [{id, ?EXIT}, {help, "Quit Concuerror."}]]},
	 {"&Edit",
	  [[{id, ?PREFS}, {text, "&Preferences...\tCtrl-P"},
	    {help, "Edit Concuerror preferences."}]]},
        {"&Module",
	  [[{id, ?ADD}, {text, "&Add...\tCtrl-A"},
	    {help, "Add an existing erlang module."}],
	   [{id, ?REMOVE}, {text, "&Remove\tCtrl-R"},
	    {help, "Remove selected module."}],
	   [{id, ?wxID_SEPARATOR}, {kind, ?wxITEM_SEPARATOR}],
	   [{id, ?CLEAR}, {text, "&Clear\tCtrl-C"},
	    {help, "Clear module list."}],
	   [{id, ?REFRESH}, {text, "Re&fresh\tF5"},
	    {help, "Refresh selected module (reload file from disk)."}]]},
	 {"&Run",
	  [[{id, ?ANALYZE}, {text, "Ana&lyze\tCtrl-L"},
	    {help, "Analyze selected function."},
            {label, ?ANALYZE_MENU_ITEM}],
           [{id, ?STOP}, {text, "&Stop\tCtrl-S"},
            {help, "Stop analysis of selected function."},
            {label, ?STOP_MENU_ITEM}]]},
	 {"&View",
	  [[{id, ?wxID_ANY}, {text, "Source viewer color theme"},
	    {help, "Select a color theme for the source viewer."},
	    {sub,
	     [[{id, ?THEME_LIGHT}, {text, "Light theme"},
	       {kind, ?wxITEM_RADIO}],
	      [{id, ?THEME_DARK}, {text, "Dark theme"},
	       {kind, ?wxITEM_RADIO}]]}
	   ]]},
	 {"&Help",
	  [[{id, ?ABOUT}, {text, "&About"},
	    {help, "Show project info."}]]}
	]).

%% 'About' message
-define(INFO_MSG,
"
                                Concuerror 
A tool for finding concurrency bugs in Erlang programs.
                                Version 0.1
").

%% File paths
-define(ICON_PATH16, "img/icon16.png").
-define(ICON_PATH32, "img/icon32.png").
-define(ICON_PATH64, "img/icon64.png").

%% GUI component definitions
-define(ABOUT, ?wxID_ABOUT).
-define(ADD, ?wxID_ADD).
-define(CLEAR, ?wxID_CLEAR).
-define(OPEN, ?wxID_OPEN).
-define(REMOVE, ?wxID_REMOVE).
-define(SEPARATOR, ?wxID_SEPARATOR).
-define(EXIT, ?wxID_EXIT).

-define(ANAL_STOP_SIZER, 500).
-define(ANALYZE, 501).
-define(ANALYZE_GAUGE, 502).
-define(ANALYZE_MENU_ITEM, 503).
-define(ERROR_ILEAVE_SPLITTER, 504).
-define(ERROR_LIST, 505).
-define(ERROR_TEXT, 506).
-define(EXPORT, 507).
-define(EXPORT_MENU_ITEM, 508).
-define(FRAME, 509).
-define(FUNCTION_LIST, 510).
-define(GRAPH_PANEL, 511).
-define(ILEAVE_LIST, 512).
-define(IMPORT, 513).
-define(IMPORT_MENU_ITEM, 514).
-define(LOG_NOTEBOOK, 515).
-define(LOG_TEXT, 516).
-define(MOD_FUN_SPLITTER, 517).
-define(MODULE_LIST, 518).
-define(NOTEBOOK, 519).
-define(NOTEBOOK_SPLITTER, 520).
-define(PREB_BOUND_SPIN, 521).
-define(PREB_ENABLED_CBOX, 522).
-define(PREFS, 523).
-define(PROC_TEXT, 524).
-define(REFRESH, 525).
-define(SCR_GRAPH, 526).
-define(SOURCE_TEXT, 527).
-define(STATIC_BMP, 528).
-define(STATUS_BAR, 529).
-define(STOP, 530).
-define(STOP_GAUGE, 531).
-define(STOP_MENU_ITEM, 532).
-define(THEME_DARK, 533).
-define(THEME_LIGHT, 534).
-define(TOP_SPLITTER, 535).

%% Splitter init-sizes
-define(SPLITTER_INIT, [{?TOP_SPLITTER, 300},
			{?MOD_FUN_SPLITTER, 300},
			{?NOTEBOOK_SPLITTER, 530},
			{?ERROR_ILEAVE_SPLITTER, 250}]).

%% Splitter min-sizes
-define(MIN_TOP, 250).
-define(MIN_MOD_FUN, 50).
-define(MIN_NOTEBOOK, 50).
-define(MIN_ERROR_ILEAVE, 50).

%% Splitter gravities
-define(GRAV_TOP, 0.0).
-define(GRAV_MOD_FUN, 0.3).
-define(GRAV_NOTEBOOK, 0.8).
-define(GRAV_ERROR_ILEAVE, 0.2).

%% Preferences related definitions
-define(PREF_PREB_ENABLED, 561).
-define(PREF_PREB_BOUND, 562).

%% Snapshot related definitions
-define(ANALYSIS_RET, 563).
-define(FILES, 564).
-define(SNAPSHOT_PATH, 565).

%% Other definitions
-define(FILE_PATH, 560).

%% Default preferences
-define(DEFAULT_PREFS,
	[{?PREF_PREB_ENABLED, true},
	 {?PREF_PREB_BOUND, 2}]).

%% Erlang keywords
-define(KEYWORDS, "after begin case try cond catch andalso orelse end fun "
                  "if let of query receive when bnot not div rem band and "
                  "bor bxor bsl bsr or xor").

%% Source viewer styles
-define(SOURCE_BG_DARK, {63, 63, 63}).
-define(SOURCE_FG_DARK, {220, 220, 204}).
%% -define(SOURCE_FG_DARK, {204, 220, 220}).
-define(SOURCE_STYLES_DARK,
	[{?wxSTC_ERLANG_ATOM,          ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_CHARACTER,     {204, 147, 147},  normal},
	 {?wxSTC_ERLANG_COMMENT,       {127, 159, 127},  normal},
	 {?wxSTC_ERLANG_DEFAULT,       ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_FUNCTION_NAME, ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_KEYWORD,       {240, 223, 175},  bold},
	 {?wxSTC_ERLANG_MACRO,         {255, 207, 175},  normal},
	 {?wxSTC_ERLANG_NODE_NAME,     ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_NUMBER,        {140, 208, 211},  normal},
	 {?wxSTC_ERLANG_OPERATOR,      ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_RECORD,        {232, 147, 147},  normal},
	 {?wxSTC_ERLANG_SEPARATOR,     ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_STRING,        {204, 147, 147},  normal},
	 {?wxSTC_ERLANG_VARIABLE,      {239, 239, 175},  bold},
	 {?wxSTC_ERLANG_UNKNOWN,       {255, 0, 0},      normal}]).
-define(SOURCE_BG_LIGHT, {255, 255, 255}).
-define(SOURCE_FG_LIGHT, {30, 30, 30}).
-define(SOURCE_STYLES_LIGHT,
	[{?wxSTC_ERLANG_ATOM,          ?SOURCE_FG_LIGHT, normal},
	 {?wxSTC_ERLANG_CHARACTER,     {120, 190, 120},  normal},
	 {?wxSTC_ERLANG_COMMENT,       {20, 140, 20},    normal},
	 {?wxSTC_ERLANG_DEFAULT,       ?SOURCE_FG_LIGHT, normal},
	 {?wxSTC_ERLANG_FUNCTION_NAME, ?SOURCE_FG_LIGHT, normal},
	 {?wxSTC_ERLANG_KEYWORD,       {140, 40, 170},   bold},
	 {?wxSTC_ERLANG_MACRO,         {180, 40, 40},    normal},
	 {?wxSTC_ERLANG_NODE_NAME,     ?SOURCE_FG_LIGHT, normal},
	 {?wxSTC_ERLANG_NUMBER,        ?SOURCE_FG_LIGHT, normal},
	 {?wxSTC_ERLANG_OPERATOR,      {70, 70, 70},     normal},
	 {?wxSTC_ERLANG_RECORD,        {150, 140, 40},   normal},
	 {?wxSTC_ERLANG_SEPARATOR,     ?SOURCE_FG_LIGHT, normal},
	 {?wxSTC_ERLANG_STRING,        {50, 50, 200},    normal},
	 {?wxSTC_ERLANG_VARIABLE,      {20, 120, 140},   bold},
	 {?wxSTC_ERLANG_UNKNOWN,       {255, 0, 0},      normal}]).
