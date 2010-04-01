%%%----------------------------------------------------------------------
%%% File    : gui.hrl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : 
%%%
%%% Created : 31 Mar 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Menu specification:
%%    [{MenuName1, [MenuItem11, MenuItem12, ...]}, ...]
-define(MENU_SPEC, [{"&File", [[{id, ?ADD}, {text, "&Add...\tCtrl-A"},
                                {help, "Add an existing erlang module."}],
                               [{id, ?SEPARATOR}, {kind, ?wxITEM_SEPARATOR}],
                               [{id, ?EXIT}, {help, "Quit PULSE."}]]},
                    {"&Run", [[{id, ?ANALYZE}, {text, "Ana&lyze\tCtrl-L"},
                               {help, "Analyze current module."}]]}, 
                    {"&Help", [[{id, ?ABOUT}, {help, "Show project info."}]]}]).

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

%% Scheduler module name
-define(SCHEDULER, scheduler).

%% File paths
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
-define(SOURCE_TEXT, 510).

%% Color definitions
-define(BASE_COLOR, {2, 63, 90}).
-define(COMP_COLOR, {125, 140, 0}).

%% Erlang keywords
-define(KEYWORDS, "after begin case try cond catch andalso orelse end fun if let of query receive when bnot not div rem band and bor bxor bsl bsr or xor").

%% Source viewer theme (dark | light)
-define(SOURCE_THEME, light).

%% Source viewer styles
-define(SOURCE_BG_DARK, {60, 60, 60}).
-define(SOURCE_FG_DARK, {240, 240, 240}).
-define(SOURCE_STYLES_DARK, 
	[{?wxSTC_ERLANG_ATOM,          ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_CHARACTER,     {120, 190, 120},  normal},
	 {?wxSTC_ERLANG_COMMENT,       {170, 170, 170},  normal},
	 {?wxSTC_ERLANG_DEFAULT,       ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_FUNCTION_NAME, ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_KEYWORD,       {210, 140, 80},   bold},
	 {?wxSTC_ERLANG_MACRO,         {220, 80, 80},    normal},
	 {?wxSTC_ERLANG_NODE_NAME,     ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_NUMBER,        ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_OPERATOR,      {210, 210, 210},  normal},
	 {?wxSTC_ERLANG_RECORD,        {100, 180, 180},  normal},
	 {?wxSTC_ERLANG_SEPARATOR,     ?SOURCE_FG_DARK,  normal},
	 {?wxSTC_ERLANG_STRING,        {120, 190, 120},  normal},
	 {?wxSTC_ERLANG_VARIABLE,      {100, 170, 210},  bold},
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

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type id()  :: ?FRAME
             | ?FUNCTION_LIST
             | ?LOG_TEXT
             | ?MODULE_LIST
             | ?NOTEBOOK
             | ?SCR_GRAPH
             | ?STATIC_BMP
             | ?SOURCE_TEXT.

-type ref() :: any(). %% XXX: should be imported from wx
%%                wxFrame:wxFrame()
%%              | wxListBox:wxListBox()
%%              | wxNotebook:wxNotebook()
%%              | wxTextCtrl:wxTextCtrl()
%%              | wxScrolledWindow:wxScrolledWindow()
%%              | wxStaticBitmap:wxStaticBitmap()
%%              | wxHtmlWindow:wxHtmlWindow().

-type gui_type() :: 'ref_add' | 'ref_error' | 'ref_lookup' | 'ref_ok'
                  | 'ref_stop' | 'dot' | 'log'.

-type gui_msg()  :: 'ok' | 'not_found' | string() | id() | ref()
                  | {id(), ref()}.

%%%----------------------------------------------------------------------
%%% Records
%%%----------------------------------------------------------------------

%% Internal message format
-record(gui, {type :: gui_type(),
              msg  :: gui_msg()}).
