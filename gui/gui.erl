%%%----------------------------------------------------------------------
%%% File    : gui.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : 
%%%
%%% Created : 31 Mar 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(gui).

-export([start/0]).

-include_lib("wx/include/wx.hrl").
-include("../include/gui.hrl").

%%%----------------------------------------------------------------------
%%% Exported functions
%%%----------------------------------------------------------------------

-spec start() -> 'ok'.

start() ->
    wx:new(),
    register(loop, self()),
    refServer:start(true),
    %% Load PULSE modules
    code:load_file(?SCHEDULER),
    Frame = setupFrame(),
    wxFrame:show(Frame),
    loop(),
    %% purge PULSE modules
    code:purge(?SCHEDULER),
    refServer:stop(),
    unregister(loop),
    os:cmd("rm -f *.dot *.png"),
    wx:destroy().

%%%----------------------------------------------------------------------
%%% Setup functions
%%%----------------------------------------------------------------------

setupFrame() ->
    Frame = wxFrame:new(wx:null(), ?FRAME, "PULSE"),
    refServer:add({?FRAME, Frame}),
    MenuBar = wxMenuBar:new(),
    setupMenu(MenuBar, ?MENU_SPEC),
    wxFrame:setIcon(Frame, wxIcon:new(?ICON_PATH)),
    wxFrame:setMenuBar(Frame, MenuBar),
    wxFrame:createStatusBar(Frame, [{id, ?STATUS_BAR}]),
    wxEvtHandler:connect(Frame, close_window),
    wxEvtHandler:connect(Frame, command_menu_selected),
    wxEvtHandler:connect(Frame, command_button_clicked),
    wxEvtHandler:connect(Frame, command_listbox_selected),
    wxEvtHandler:connect(Frame, command_listbox_doubleclicked),
    setupPanel(Frame),
    wxWindow:setSize(Frame, {1024, 768}),
    %% wxWindow:fit(Frame),
    wxFrame:center(Frame),
    Frame.

setupPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    %% -------------------- Left Column -------------------- %%
    ModuleBox = wxStaticBox:new(Panel, ?wxID_ANY, "Modules"),
    FunctionBox = wxStaticBox:new(Panel, ?wxID_ANY, "Functions"),
    ModuleList = wxListBox:new(Panel, ?MODULE_LIST),
    refServer:add({?MODULE_LIST, ModuleList}),
    FunctionList = wxListBox:new(Panel, ?FUNCTION_LIST, [{style, ?wxLB_SORT}]),
    refServer:add({?FUNCTION_LIST, FunctionList}),
    AddButton = wxButton:new(Panel, ?ADD, [{label, "&Add..."}]),
    RemButton = wxButton:new(Panel, ?REMOVE),
    ClearButton = wxButton:new(Panel, ?CLEAR),
    AnalyzeButton = wxButton:new(Panel, ?ANALYZE, [{label, "Ana&lyze"}]),
    AddRemSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(AddRemSizer, AddButton,
		[{proportion, 0}, {flag, ?wxRIGHT}, {border, 5}]),
    wxSizer:add(AddRemSizer, RemButton,
		[{proportion, 0}, {flag, ?wxRIGHT bor ?wxLEFT},
		 {border, 5}]),
    wxSizer:add(AddRemSizer, ClearButton,
		[{proportion, 0}, {flag, ?wxLEFT}, {border, 5}]),
    ModuleSizer = wxStaticBoxSizer:new(ModuleBox, ?wxVERTICAL),
    wxSizer:add(ModuleSizer, ModuleList,
		[{proportion, 1},
		 {flag, ?wxEXPAND bor ?wxTOP bor ?wxLEFT bor ?wxRIGHT},
		 {border, 10}]),
    wxSizer:add(ModuleSizer, AddRemSizer,
		[{proportion, 0},
		 {flag, ?wxALIGN_CENTER bor ?wxALL},
                 {border, 10}]),
    FunctionSizer = wxStaticBoxSizer:new(FunctionBox, ?wxVERTICAL),
    wxSizer:add(FunctionSizer, FunctionList,
		[{proportion, 1},
		 {flag, ?wxEXPAND bor ?wxTOP bor ?wxLEFT bor ?wxRIGHT},
		 {border, 10}]),
    wxSizer:add(FunctionSizer, AnalyzeButton,
		[{proportion, 0},
		 {flag, ?wxALIGN_CENTER bor ?wxALL},
                 {border, 10}]),
    LeftColumnSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(LeftColumnSizer, ModuleSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxBOTTOM},
		 {border, 10}]),
    wxSizer:add(LeftColumnSizer, FunctionSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxTOP},
		 {border, 10}]),
    %% -------------------- Right Column -------------------- %%
    Notebook = wxNotebook:new(Panel, ?NOTEBOOK, [{style, ?wxNB_NOPAGETHEME}]),
    refServer:add({?NOTEBOOK, Notebook}),
    LogPanel = wxPanel:new(Notebook),
    GraphPanel = wxPanel:new(Notebook),
    SourcePanel = wxPanel:new(Notebook),
    LogText = wxTextCtrl:new(LogPanel, ?LOG_TEXT,
			     [{style, ?wxTE_MULTILINE bor ?wxTE_READONLY}]),
    refServer:add({?LOG_TEXT, LogText}),
    ScrGraph = wxScrolledWindow:new(GraphPanel),
    wxWindow:setOwnBackgroundColour(ScrGraph, {255, 255, 255}),
    wxWindow:clearBackground(ScrGraph),
    refServer:add({?SCR_GRAPH, ScrGraph}),
    SourceText = wxStyledTextCtrl:new(SourcePanel),
    refServer:add({?SOURCE_TEXT, SourceText}),
    setupSourceText(SourceText, light),

    LogPanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(LogPanelSizer, LogText,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxWindow:setSizer(LogPanel, LogPanelSizer),
    GraphPanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(GraphPanelSizer, ScrGraph,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxWindow:setSizer(GraphPanel, GraphPanelSizer),
    SourcePanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(SourcePanelSizer, SourceText,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxWindow:setSizer(SourcePanel, SourcePanelSizer),

    wxNotebook:addPage(Notebook, LogPanel, "Log", [{bSelect, true}]),
    wxNotebook:addPage(Notebook, GraphPanel, "Graph", [{bSelect, false}]),
    wxNotebook:addPage(Notebook, SourcePanel, "Source", [{bSelect, false}]),
    RightColumnSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(RightColumnSizer, Notebook,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 0}]),
    %% -------------------- Two-column top level layout -------------------- %%
    TopSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(TopSizer, LeftColumnSizer,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxSizer:add(TopSizer, RightColumnSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxWindow:setSizer(Panel, TopSizer),
    wxSizer:fit(TopSizer, Panel),
    %% wxSizer:setSizeHints(TopSizer, Parent),
    Panel.

%% Menu constructor according to specification (gui.hrl)
setupMenu(MenuBar, [{Title, Items}|Rest]) ->
    setupMenu(MenuBar, [{Title, Items, []}|Rest]);
setupMenu(_MenuBar, []) ->
    ok;
setupMenu(MenuBar, [{Title, Items, Options}|Rest]) ->
    Menu = wxMenu:new(Options),
    setupMenuItems(Menu, Items),
    wxMenuBar:append(MenuBar, Menu, Title),
    setupMenu(MenuBar, Rest).

setupMenuItems(_Menu, []) ->
    ok;
setupMenuItems(Menu, [Options|Rest]) ->
    case lists:keytake(sub, 1, Options) of
	{value, {_, SubItems}, NewOptions} ->
	    Submenu = wxMenu:new(),
	    setupMenuItems(Submenu, SubItems),
	    Item = wxMenuItem:new(NewOptions),
	    wxMenuItem:setSubMenu(Item, Submenu),
	    wxMenu:append(Menu, Item),
	    setupMenuItems(Menu, Rest);
	false ->
	    Item = wxMenuItem:new(Options),
	    wxMenu:append(Menu, Item),
	    setupMenuItems(Menu, Rest)
    end.

%% Setup source viewer
setupSourceText(Ref, Theme) ->
    NormalFont = wxFont:new(10, ?wxFONTFAMILY_TELETYPE, ?wxNORMAL,
                            ?wxNORMAL, []),
    BoldFont = wxFont:new(10, ?wxFONTFAMILY_TELETYPE, ?wxNORMAL,
                          ?wxBOLD, []),
    ItalicFont = wxFont:new(10, ?wxFONTFAMILY_TELETYPE, ?wxITALIC,
                            ?wxBOLD, []),
    case Theme of
	dark ->
	    Styles = ?SOURCE_STYLES_DARK,
	    BgColor = ?SOURCE_BG_DARK;
	light ->
	    Styles = ?SOURCE_STYLES_LIGHT,
	    BgColor = ?SOURCE_BG_LIGHT
    end,
    wxStyledTextCtrl:styleClearAll(Ref),
    wxStyledTextCtrl:styleSetFont(Ref, ?wxSTC_STYLE_DEFAULT, NormalFont),
    wxStyledTextCtrl:styleSetBackground(Ref, ?wxSTC_STYLE_DEFAULT, BgColor),
    wxStyledTextCtrl:setLexer(Ref, ?wxSTC_LEX_ERLANG),
    wxStyledTextCtrl:setMarginType(Ref, 0, ?wxSTC_MARGIN_NUMBER),
    Width = wxStyledTextCtrl:textWidth(Ref, ?wxSTC_STYLE_LINENUMBER, "99999"),
    wxStyledTextCtrl:setMarginWidth(Ref, 0, Width),
    wxStyledTextCtrl:setMarginWidth(Ref, 1, 0),
    %% wxStyledTextCtrl:setScrollWidth(Ref, 1000),
    %% wxStyledTextCtrl:setSelectionMode(Ref, ?wxSTC_SEL_LINES),
    wxStyledTextCtrl:setReadOnly(Ref, true),
    wxStyledTextCtrl:setWrapMode(Ref, ?wxSTC_WRAP_WORD),
    SetStyles =
        fun({Style, Color, Option}) ->
                case Option of
                    bold ->
                        wxStyledTextCtrl:styleSetFont(Ref, Style, BoldFont);
                    italic ->
                        wxStyledTextCtrl:styleSetFont(Ref, Style, ItalicFont);
                    _Other ->
                        wxStyledTextCtrl:styleSetFont(Ref, Style, NormalFont)
                end,
                wxStyledTextCtrl:styleSetForeground(Ref, Style, Color),
                wxStyledTextCtrl:styleSetBackground(Ref, Style, BgColor)
        end,
    [SetStyles(Style) || Style <- Styles],
    wxStyledTextCtrl:setKeyWords(Ref, 0, ?KEYWORDS).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

addArgs(_Parent, _Sizer, Max, Max, Refs) ->
    lists:reverse(Refs);
addArgs(Parent, Sizer, I, Max, Refs) ->
    %% XXX: semi-hack, custom width, default heightq
    Ref =  wxTextCtrl:new(Parent, ?wxID_ANY, [{size, {130, -1}}]),
    HorizSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(HorizSizer,
                wxStaticText:new(Parent, ?wxID_ANY,
                                 io_lib:format("Arg~p: ", [I + 1])),
		[{proportion, 0}, {flag, ?wxALIGN_CENTER bor ?wxRIGHT},
                 {border, 5}]),
    wxSizer:add(HorizSizer, Ref, [{proportion, 1},
                                  {flag, ?wxALIGN_CENTER bor ?wxALL},
                                  {border, 0}]),
    wxSizer:add(Sizer, HorizSizer, [{proportion, 0},
                                    {flag, ?wxEXPAND bor ?wxALL},
                                    {border, 10}]),
    addArgs(Parent, Sizer, I + 1, Max, [Ref|Refs]).

%% Module-adding dialog
addDialog(Parent) ->
    Caption = "Open erlang module",
    Wildcard = "Erlang source|*.erl;*.hrl| All files|*",
    DefaultDir = ".",
    DefaultFile = "",
    Dialog = wxFileDialog:new(Parent, [{message, Caption},
                                       {defaultDir, DefaultDir},
                                       {defaultFile, DefaultFile},
                                       {wildCard, Wildcard},
                                       {style, ?wxFD_OPEN bor
                                               ?wxFD_FILE_MUST_EXIST bor
                                               ?wxFD_MULTIPLE}]),
    case wxDialog:showModal(Dialog) of
	?wxID_OK -> addListItems(?MODULE_LIST, wxFileDialog:getPaths(Dialog));
	_Other -> continue
    end,
    wxDialog:destroy(Dialog).

%% Add items to ListBox (Id) and select first of newly added modules
addListItems(Id, Items) ->
    List = refServer:lookup(Id),
    Count = wxControlWithItems:getCount(List),
    wxListBox:insertItems(List, Items, Count),
    case Count of
	0 -> wxControlWithItems:setSelection(List, 0);
	_Other -> wxControlWithItems:setSelection(List, Count)
    end,
    %% XXX: hack (send event message to self)
    self() ! #wx{id = Id,
		 event = #wxCommand{type = command_listbox_selected}}.

%% Analyze selected function
analyze() ->
    Module = getModule(),
    {Function, Arity} = getFunction(),
    Self = self(),
    if
	Module =/= '', Function =/= '' ->
	    case Arity of
		0 ->
		    instrumentAll(?MODULE_LIST),
		    LogText = refServer:lookup(?LOG_TEXT),
		    wxTextCtrl:clear(LogText),
		    spawn(fun() ->
				  driver:drive(
				    fun() -> Module:Function() end,
				    Self)
			  end);
		Count ->
		    Frame = refServer:lookup(?FRAME),
		    case argDialog(Frame, Count) of
			{ok, Args} ->
			    instrumentAll(?MODULE_LIST),
			    LogText = refServer:lookup(?LOG_TEXT),
			    wxTextCtrl:clear(LogText),
			    spawn(fun() ->
					  driver:drive(
					    fun() ->
						    apply(Module,
							  Function,
							  Args)
					    end,
					    Self)
				  end);
			_Other -> continue
		    end
	    end;
	true -> continue
    end.

%% Dialog for inserting function arguments (terms)
argDialog(Parent, Argnum) ->
    Dialog = wxDialog:new(Parent, ?wxID_ANY, "Enter arguments"),
    TopSizer = wxBoxSizer:new(?wxVERTICAL),
    Box = wxStaticBox:new(Dialog, ?wxID_ANY, "Arguments"),
    InSizer = wxStaticBoxSizer:new(Box, ?wxVERTICAL),
    Refs = addArgs(Dialog, InSizer, 0, Argnum, []),
    ButtonSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(ButtonSizer, wxButton:new(Dialog, ?wxID_OK),
		[{proportion, 0}, {flag, ?wxRIGHT}, {border, 5}]),
    wxSizer:add(ButtonSizer, wxButton:new(Dialog, ?wxID_CANCEL),
		[{proportion, 0}, {flag, ?wxLEFT}, {border, 5}]),
    wxSizer:add(TopSizer, InSizer,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxSizer:add(TopSizer, ButtonSizer,
                [{proportion, 0},
		 {flag, ?wxALIGN_CENTER bor
		        ?wxRIGHT bor ?wxLEFT bor ?wxBOTTOM},
		 {border, 10}]),
    wxWindow:setSizer(Dialog, TopSizer),
    wxSizer:fit(TopSizer, Dialog),
    case wxDialog:showModal(Dialog) of
	?wxID_OK ->
	    LogText = refServer:lookup(?LOG_TEXT),
	    wxTextCtrl:clear(LogText),
	    ValResult = validateArgs(0, Refs, [], LogText),
	    wxDialog:destroy(Dialog),
	    case ValResult of
		{ok, Args} -> {ok, Args};
		_Other -> continue
	    end;
	_Other ->
	    wxDialog:destroy(Dialog),
	    continue
    end.

%% Clear module list
clear() ->
    ModuleList = refServer:lookup(?MODULE_LIST),
    FunctionList = refServer:lookup(?FUNCTION_LIST),
    SourceText = refServer:lookup(?SOURCE_TEXT),
    wxControlWithItems:clear(ModuleList),
    wxControlWithItems:clear(FunctionList),
    wxStyledTextCtrl:setReadOnly(SourceText, false),
    wxStyledTextCtrl:clearAll(SourceText),
    wxStyledTextCtrl:setReadOnly(SourceText, true).

getFunction() ->
    FunctionList = refServer:lookup(?FUNCTION_LIST),
    Expr = wxControlWithItems:getStringSelection(FunctionList),
    Match = re:run(Expr, "(?<FUN>.*)/(?<ARITY>.*)\$",
                   [dotall, {capture, ['FUN', 'ARITY'], list}]),
    case Match of
	{match, [Fun, Arity]} ->
	    {list_to_atom(Fun), list_to_integer(Arity)};
	nomatch -> {'', 0}
    end.

getModule() ->
    ModuleList = refServer:lookup(?MODULE_LIST),
    Path = wxControlWithItems:getStringSelection(ModuleList),
    Match =  re:run(Path, ".*/(?<MODULE>.*?)\.erl\$",
                    [dotall, {capture, ['MODULE'], list}]),
    case Match of
	{match, [Module]} -> list_to_atom(Module);
	nomatch -> ''
    end.

%% wxControlWithItems:getStrings (function missing from wxErlang lib)
getStrings(Ref) ->
    Count = wxControlWithItems:getCount(Ref),
    if
	Count > 0 ->
	    getStrings(Ref, 0, Count, []);
	true ->
	    []
    end.

getStrings(_Ref, Count, Count, Strings) ->
    Strings;
getStrings(Ref, N, Count, Strings) ->
    String = wxControlWithItems:getString(Ref, N),
    getStrings(Ref, N + 1, Count, [String|Strings]).

%% Instrument all modules in ModuleList
instrumentAll(Id) ->
    ModuleList = refServer:lookup(Id),
    instrumentList(getStrings(ModuleList)).

instrumentList([]) ->
    ok;
instrumentList([String|Strings]) ->
    instrument:c(String),
    instrumentList(Strings).

%% Remove selected module from module list
remove() ->
    ModuleList = refServer:lookup(?MODULE_LIST),
    Selection = wxListBox:getSelection(ModuleList),
    FunctionList = refServer:lookup(?FUNCTION_LIST),
    SourceText = refServer:lookup(?SOURCE_TEXT),
    if
	Selection =:= ?wxNOT_FOUND ->
	    continue;
	true ->
	    wxControlWithItems:delete(ModuleList, Selection),
	    Count = wxControlWithItems:getCount(ModuleList),
	    if
		Count =:= 0 ->
		    wxControlWithItems:clear(FunctionList),
		    wxStyledTextCtrl:setReadOnly(SourceText, false),
		    wxStyledTextCtrl:clearAll(SourceText),
		    wxStyledTextCtrl:setReadOnly(SourceText, true);
		Selection =:= Count ->
		    wxControlWithItems:setSelection(ModuleList,
						    Selection - 1);
		true ->
		    wxControlWithItems:setSelection(ModuleList,
						    Selection)
	    end
    end.

%% Set ListBox (Id) items (remove existing)
setListItems(Id, Items) ->
    if
	Items =/= [], Items =/= [[]] ->
	    List = refServer:lookup(Id),
	    wxListBox:set(List, Items),
	    wxControlWithItems:setSelection(List, 0),
	    %% XXX: hack (send event message to self)
	    self() ! #wx{id = Id,
                         event = #wxCommand{type = command_listbox_selected}};
	true ->
	    continue
    end.

validateArgs(_I, [], Args, _RefError) ->
    {ok, lists:reverse(Args)};
validateArgs(I, [Ref|Refs], Args, RefError) ->
    String = wxTextCtrl:getValue(Ref) ++ ".",
    case erl_scan:string(String) of
	{ok, T, _} ->
	    case erl_parse:parse_term(T) of
		{ok, Arg} -> validateArgs(I + 1, Refs, [Arg|Args], RefError);
		{error, {_, _, Info}} ->
		    wxTextCtrl:appendText(RefError,
					  io_lib:format("Arg ~p - ~s~n",
							[I + 1, Info])),
		    error
	    end;
	{error, {_, _, Info}, _} ->
	    wxTextCtrl:appendText(RefError, Info ++ "\n"),
	    error
    end.

%%%----------------------------------------------------------------------
%%% Main event loop
%%%----------------------------------------------------------------------

loop() ->
    receive
	%% -------------------- Button handlers -------------------- %%
	#wx{id = ?ADD, event = #wxCommand{type = command_button_clicked}} ->
	    Frame = refServer:lookup(?FRAME),
	    addDialog(Frame),
	    loop();
	#wx{id = ?ANALYZE, event = #wxCommand{type = command_button_clicked}} ->
	    analyze(),
	    loop();
	#wx{id = ?CLEAR, event = #wxCommand{type = command_button_clicked}} ->
	    clear(),
	    loop();
	#wx{id = ?REMOVE, event = #wxCommand{type = command_button_clicked}} ->
	    remove(),
	    loop();
	%% -------------------- Listbox handlers --------------------- %%
	#wx{id = ?FUNCTION_LIST,
	    event = #wxCommand{type = command_listbox_doubleclicked}} ->
	    analyze(),
	    loop();
	#wx{id = ?FUNCTION_LIST,
	    event = #wxCommand{type = command_listbox_selected}} ->
	    %% do nothing
	    loop();
	#wx{id = ?MODULE_LIST,
	    event = #wxCommand{type = command_listbox_doubleclicked}} ->
	    %% do nothing
	    loop();
	#wx{id = ?MODULE_LIST,
            event = #wxCommand{type = command_listbox_selected}} ->
	    ModuleList = refServer:lookup(?MODULE_LIST),
	    case wxListBox:getSelection(ModuleList) of
		?wxNOT_FOUND -> continue;
		_Other ->
		    Module = wxListBox:getStringSelection(ModuleList),
		    %% Update module functions
		    Funs = funs:stringList(Module),
		    setListItems(?FUNCTION_LIST, Funs),
		    %% Update module source
		    SourceText = refServer:lookup(?SOURCE_TEXT),
		    wxStyledTextCtrl:setReadOnly(SourceText, false),
		    wxStyledTextCtrl:loadFile(SourceText, Module),
		    wxStyledTextCtrl:setReadOnly(SourceText, true)
	    end,
	    loop();
	%% -------------------- Menu handlers -------------------- %%
	#wx{id = ?ABOUT, event = #wxCommand{type = command_menu_selected}} ->
	    Caption = "About PULSE",
	    Frame = refServer:lookup(?FRAME),
	    Dialog = wxMessageDialog:new(Frame, ?INFO_MSG,
                                         [{style, ?wxOK}, {caption, Caption}]),
	    wxDialog:showModal(Dialog),
	    wxWindow:destroy(Dialog),
	    loop();
	#wx{id = ?ADD, event = #wxCommand{type = command_menu_selected}} ->
	    Frame = refServer:lookup(?FRAME),
	    addDialog(Frame),
	    loop();
	#wx{id = ?ANALYZE, event = #wxCommand{type = command_menu_selected}} ->
	    analyze(),
	    loop();
	#wx{id = ?CLEAR, event = #wxCommand{type = command_menu_selected}} ->
	    clear(),
	    loop();
	#wx{id = ?THEME_LIGHT,
            event = #wxCommand{type = command_menu_selected}} ->
	    SourceText = refServer:lookup(?SOURCE_TEXT),
	    setupSourceText(SourceText, light),
	    loop();
	#wx{id = ?THEME_DARK,
            event = #wxCommand{type = command_menu_selected}} ->
	    SourceText = refServer:lookup(?SOURCE_TEXT),
	    setupSourceText(SourceText, dark),
	    loop();
	#wx{id = ?REMOVE, event = #wxCommand{type = command_menu_selected}} ->
	    remove(),
	    loop();
	#wx{id = ?EXIT, event = #wxCommand{type = command_menu_selected}} ->
	    ok;
	%% -------------------- Misc handlers -------------------- %%
	#gui{type = dot, msg = ok} ->
	    os:cmd("dot -Tpng < schedule.dot > schedule.png"),
	    Image= wxBitmap:new("schedule.png", [{type, ?wxBITMAP_TYPE_PNG}]),
	    {W, H} = {wxBitmap:getWidth(Image), wxBitmap:getHeight(Image)},
%%             wxScrolledWindow:doPrepareDC(ScrGraph, Dc),
%%             wxDC:drawBitmap(Dc, Image, {0, 0}, [{useMask, false}]),
%%             wxClientDC:destroy(Dc),
	    ScrGraph = refServer:lookup(?SCR_GRAPH),
	    wxScrolledWindow:setScrollbars(ScrGraph, 20, 20,
                                           W div 20, H div 20),
	    %% NOTE: Static bitmap for large pics ok?
	    case refServer:lookup(?STATIC_BMP) of
		not_found ->
		    StaticBmp = wxStaticBitmap:new(ScrGraph, ?wxID_ANY, Image),
		    refServer:add({?STATIC_BMP, StaticBmp});
		Result ->
		    wxStaticBitmap:setBitmap(Result, Image)
	    end,
	    loop();
	#gui{type = log, msg = String} ->
	    LogText = refServer:lookup(?LOG_TEXT),
	    wxTextCtrl:appendText(LogText, String),
	    loop();
	#wx{event = #wxClose{type = close_window}} ->
	    ok;
	%% -------------------- Catchall -------------------- %%
	Other ->
	    io:format("main loop unimplemented: ~p~n", [Other]),
	    loop()
    end.
