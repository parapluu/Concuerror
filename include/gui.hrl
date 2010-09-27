%%%----------------------------------------------------------------------
%%% File    : gui.hrl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : GUI Header File
%%%
%%% Created : 31 Mar 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Initial frame size.
-define(FRAME_SIZE_INIT, {1042, 768}).

%% Menu specification:
%%    [{MenuName1, [MenuItem11, MenuItem12, ...]}, ...]
-define(MENU_SPEC,
	[{"&File",
	  [[{id, ?EXIT}, {help, "Quit CED."}]]},
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
	    {help, "Analyze selected function."}]]},
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
                                    CED
A tool for finding concurrency bugs in Erlang programs.
                                Version 0.1
").

%% File paths
-define(ICON_PATH, "img/icon.png").

%% Local ID definitions
-define(ABOUT, ?wxID_ABOUT).
-define(ADD, ?wxID_ADD).
-define(CLEAR, ?wxID_CLEAR).
-define(OPEN, ?wxID_OPEN).
-define(REMOVE, ?wxID_REMOVE).
-define(SEPARATOR, ?wxID_SEPARATOR).
-define(EXIT, ?wxID_EXIT).
-define(ANALYZE, 500).
-define(FRAME, 501).
-define(FUNCTION_LIST, 502).
-define(GRAPH_PANEL, 503).
-define(LOG_TEXT, 504).
-define(MODULE_LIST, 505).
-define(NOTEBOOK, 506).
-define(SCR_GRAPH, 507).
-define(SOURCE_TEXT, 508).
-define(STATIC_BMP, 509).
-define(STATUS_BAR, 510).
-define(THEME_LIGHT, 511).
-define(THEME_DARK, 512).
-define(REFRESH, 513).
-define(FILE_PATH, 514).
-define(PROC_TEXT, 515).
-define(LOG_NOTEBOOK, 516).
-define(ERROR_LIST, 517).
-define(ILEAVE_LIST, 518).
-define(ERROR_TEXT, 519).

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
