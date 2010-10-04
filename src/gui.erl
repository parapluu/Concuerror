%%%----------------------------------------------------------------------
%%% File        : gui.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Graphical User Interface
%%% Created     : 31 Mar 2010
%%%
%%% @doc: Graphical User Interface
%%% @end
%%%----------------------------------------------------------------------

-module(gui).

%% UI exports.
-export([start/0]).
%% Log server callback exports.
-export([init/1, terminate/2, handle_event/2]).

-include_lib("wx/include/wx.hrl").
-include("gen.hrl").
-include("gui.hrl").

%% Log event handler internal state.
-type state() :: [].

%%%----------------------------------------------------------------------
%%% UI functions
%%%----------------------------------------------------------------------

%% @spec start() -> 'true'
%% @doc: Start the CED GUI.
-spec start() -> 'true'.

start() ->
    register(?RP_GUI, self()),
    wx:new(),
    %% Start the object reference mapping service.
    ref_start(),
    %% Set initial file load path (used by the module addition dialog).
    ref_add(?FILE_PATH, ""),
    %% Load preferences from file or if not found, load defaults.
    loadPrefs(),
    snapshot_init(),
    Frame = setupFrame(),
    wxFrame:show(Frame),
    %% Start the log manager and attach the event handler below.
    log:start(),
    log:attach(?MODULE, wx:get_env()),
    %% Start the replay server.
    loop(),
    snapshot_cleanup(),
    log:stop(),
    %% Save possibly edited preferences to file.
    savePrefs(),
    ref_stop(),
    wx:destroy(),
    unregister(?RP_GUI).

%%%----------------------------------------------------------------------
%%% Log event handler callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {'ok', state()}.

%% @doc: Initialize the event handler.
%%
%% Note: The wx environment is set once in this function and is subsequently
%%       used by all callback functions. If any change is to happen to the
%%       environment (e.g. new elements added dynamically), `set_env' will have
%%       to be called again (by manually calling a special update_environment
%%       function for each update?).
init(Env) ->
    wx:set_env(Env),
    {ok, []}.

-spec terminate(term(), state()) -> 'ok'.

terminate(_Reason, _State) ->
    ok.

-spec handle_event(log:event(), state()) -> {'ok', state()}.

handle_event({msg, String}, State) ->
    LogText = ref_lookup(?LOG_TEXT),
    wxTextCtrl:appendText(LogText, String),
    {ok, State}.

%%%----------------------------------------------------------------------
%%% Setup functions
%%%----------------------------------------------------------------------

setupFrame() ->
    Frame = wxFrame:new(wx:null(), ?FRAME, ?APP_STRING),
    ref_add(?FRAME, Frame),
    MenuBar = wxMenuBar:new(),
    setupMenu(MenuBar, ?MENU_SPEC),
    Icons = wxIconBundle:new(),
    wxIconBundle:addIcon(Icons, wxIcon:new(?ICON_PATH16)),
    wxIconBundle:addIcon(Icons, wxIcon:new(?ICON_PATH32)),
    wxIconBundle:addIcon(Icons, wxIcon:new(?ICON_PATH64)),
    wxFrame:setIcons(Frame, Icons),
    wxFrame:setMenuBar(Frame, MenuBar),
    wxFrame:createStatusBar(Frame, [{id, ?STATUS_BAR}]),
    wxEvtHandler:connect(Frame, close_window),
    wxEvtHandler:connect(Frame, command_menu_selected),
    wxEvtHandler:connect(Frame, command_button_clicked),
    wxEvtHandler:connect(Frame, command_listbox_selected),
    wxEvtHandler:connect(Frame, command_listbox_doubleclicked),
    setupPanel(Frame),
    wxWindow:setSize(Frame, ?FRAME_SIZE_INIT),
    %% wxWindow:fit(Frame),
    wxFrame:center(Frame),
    Frame.

%% Setup top-level panel, having a simple two-column horizontal layout.
setupPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    LeftColumnSizer = setupLeftColumn(Panel),
    RightColumnSizer = setupRightColumn(Panel),
    %% Top-level layout
    TopSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(TopSizer, LeftColumnSizer,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxSizer:add(TopSizer, RightColumnSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxWindow:setSizer(Panel, TopSizer),
    wxSizer:fit(TopSizer, Panel),
    %% Uncomment if starting frame size should be the minimum size
    %% (i.e. frame shouldn't be allowed to shrink below it).
    %% wxSizer:setSizeHints(TopSizer, Parent),
    Panel.

%% Setup left column of top-level panel, including module and function
%% listboxes and several buttons.
setupLeftColumn(Panel) ->
    %% Create widgets
    ModuleBox = wxStaticBox:new(Panel, ?wxID_ANY, "Modules"),
    FunctionBox = wxStaticBox:new(Panel, ?wxID_ANY, "Functions"),
    ModuleList = wxListBox:new(Panel, ?MODULE_LIST),
    ref_add(?MODULE_LIST, ModuleList),
    FunctionList = wxListBox:new(Panel, ?FUNCTION_LIST, [{style, ?wxLB_SORT}]),
    ref_add(?FUNCTION_LIST, FunctionList),
    AddButton = wxButton:new(Panel, ?ADD, [{label, "&Add..."}]),
    RemButton = wxButton:new(Panel, ?REMOVE),
    ClearButton = wxButton:new(Panel, ?CLEAR),
    AnalyzeButton = wxButton:new(Panel, ?ANALYZE, [{label, "Ana&lyze"}]),
    ref_add(?ANALYZE, AnalyzeButton),
    %% Setup button sizers
    AddRemSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(AddRemSizer, AddButton,
		[{proportion, 0}, {flag, ?wxRIGHT}, {border, 5}]),
    wxSizer:add(AddRemSizer, RemButton,
		[{proportion, 0}, {flag, ?wxRIGHT bor ?wxLEFT},
		 {border, 5}]),
    wxSizer:add(AddRemSizer, ClearButton,
		[{proportion, 0}, {flag, ?wxLEFT}, {border, 5}]),
    %% Setup module/function sizers
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
		[{proportion, 0}, {flag, ?wxALIGN_CENTER bor ?wxALL},
                 {border, 10}]),
    %% Setup left column sizer
    LeftColumnSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(LeftColumnSizer, ModuleSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxBOTTOM},
		 {border, 10}]),
    wxSizer:add(LeftColumnSizer, FunctionSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxTOP},
		 {border, 10}]),
    LeftColumnSizer.

%% Setup right column of top-level panel, including a notebook for displaying
%% tabbed main, graph and source code panels and another notebook for displaying
%% log messages.
setupRightColumn(Panel) ->
    MainNotebook = setupMainNotebook(Panel),
    LogNotebook = setupLogNotebook(Panel),
    %% Setup right column sizer
    RightColumnSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(RightColumnSizer, MainNotebook,
		[{proportion, 3}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 0}]),
    wxSizer:add(RightColumnSizer, LogNotebook,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxTOP},
		 {border, 10}]),
    RightColumnSizer.

%% Setup main notebook, containing 3 tabs:
%% Main tab: Contains a list showing the errors encountered and another list
%%           showing the selected erroneous interleaving.
%% Graph tab: Displays a process interaction graph of the selected erroneous
%%            interleaving.
%% Source tab: Displays the source code for the selected module.
%% TODO: Temporarily removed graph tab.
setupMainNotebook(Parent) ->
    %% Notebook widgets.
    Notebook = wxNotebook:new(Parent, ?NOTEBOOK, [{style, ?wxNB_NOPAGETHEME}]),
    ref_add(?NOTEBOOK, Notebook),
    %% Setup tab panels.
    MainPanel = setupMainPanel(Notebook),
    _GraphPanel = setupGraphPanel(Notebook),
    SourcePanel = setupSourcePanel(Notebook),
    %% Add tabs to notebook.
    wxNotebook:addPage(Notebook, MainPanel, "Main", [{bSelect, true}]),
    %% TODO: Temporarily removed graph tab.
    %% wxNotebook:addPage(Notebook, GraphPanel, "Graph", [{bSelect, false}]),
    wxNotebook:addPage(Notebook, SourcePanel, "Source", [{bSelect, false}]),
    Notebook.

setupMainPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    ErrorBox = wxStaticBox:new(Panel, ?wxID_ANY, "Errors"),
    IleaveBox = wxStaticBox:new(Panel, ?wxID_ANY, "Process interleaving"),
    ErrorList = wxListBox:new(Panel, ?ERROR_LIST),
    ref_add(?ERROR_LIST, ErrorList),
    IleaveList = wxListBox:new(Panel, ?ILEAVE_LIST),
    ref_add(?ILEAVE_LIST, IleaveList),
    %% Setup sizers.
    ErrorSizer = wxStaticBoxSizer:new(ErrorBox, ?wxVERTICAL),
    wxSizer:add(ErrorSizer, ErrorList,
		[{proportion, 1},
		 {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    IleaveSizer = wxStaticBoxSizer:new(IleaveBox, ?wxVERTICAL),
    wxSizer:add(IleaveSizer, IleaveList,
		[{proportion, 1},
		 {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    PanelSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(PanelSizer, ErrorSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxSizer:add(PanelSizer, IleaveSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxWindow:setSizer(Panel, PanelSizer),
    Panel.

%% Setup the graph panel.
%% A static bitmap combined with a scrolled window is used for
%% displaying the graph image.
setupGraphPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    ScrGraph = wxScrolledWindow:new(Panel),
    ref_add(?SCR_GRAPH, ScrGraph),
    wxWindow:setOwnBackgroundColour(ScrGraph, {255, 255, 255}),
    wxWindow:clearBackground(ScrGraph),
    Bmp = wxBitmap:new(),
    StaticBmp = wxStaticBitmap:new(ScrGraph, ?STATIC_BMP, Bmp),
    ref_add(?STATIC_BMP, StaticBmp),
    %% Setup sizer.
    PanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(PanelSizer, ScrGraph,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxWindow:setSizer(Panel, PanelSizer),
    Panel.

setupSourcePanel(Parent) ->
    Panel = wxPanel:new(Parent),
    SourceText = wxStyledTextCtrl:new(Panel),
    ref_add(?SOURCE_TEXT, SourceText),
    setupSourceText(SourceText, light),
    %% Setup sizer.
    PanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(PanelSizer, SourceText,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxWindow:setSizer(Panel, PanelSizer),
    Panel.

%% Setup source viewer, using a styled text control.
%% Ref is a reference to the wxStyledTextCtrl object and theme is
%% either 'light' or 'dark'.
setupSourceText(Ref, Theme) ->
    NormalFont = wxFont:new(10, ?wxFONTFAMILY_TELETYPE, ?wxNORMAL,
                            ?wxNORMAL, []),
    BoldFont = wxFont:new(10, ?wxFONTFAMILY_TELETYPE, ?wxNORMAL,
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
    SetStyles = fun({Style, Color, Option}) ->
		  case Option of
		      bold ->
			  wxStyledTextCtrl:styleSetFont(Ref, Style, BoldFont);
		      _Other ->
			  wxStyledTextCtrl:styleSetFont(Ref, Style, NormalFont)
		  end,
		  wxStyledTextCtrl:styleSetForeground(Ref, Style, Color),
		  wxStyledTextCtrl:styleSetBackground(Ref, Style, BgColor)
		end,
    [SetStyles(Style) || Style <- Styles],
    wxStyledTextCtrl:setKeyWords(Ref, 0, ?KEYWORDS).

%% Setup a notebook for displaying log messages.
setupLogNotebook(Parent) ->
    %% Log notebook widgets (notebook -> panel -> textcontrol).
    Notebook = wxNotebook:new(Parent, ?LOG_NOTEBOOK,
			      [{style, ?wxNB_NOPAGETHEME}]),
    ref_add(?LOG_NOTEBOOK, Notebook),
    %% Setup tab panels
    LogPanel = setupLogPanel(Notebook),
    ErrorPanel = setupErrorPanel(Notebook),
    %% Add tabs to log notebook.
    wxNotebook:addPage(Notebook, LogPanel, "Log", [{bSelect, true}]),
    wxNotebook:addPage(Notebook, ErrorPanel, "Problems",
                       [{bSelect, false}]),
    Notebook.

setupLogPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    LogText = wxTextCtrl:new(Panel, ?LOG_TEXT,
                             [{style, ?wxTE_MULTILINE bor ?wxTE_READONLY}]),
    ref_add(?LOG_TEXT, LogText),
    PanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(PanelSizer, LogText,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxWindow:setSizer(Panel, PanelSizer),
    Panel.

setupErrorPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    ErrorText = wxTextCtrl:new(Panel, ?ERROR_TEXT,
                               [{style, ?wxTE_MULTILINE bor ?wxTE_READONLY}]),
    ref_add(?ERROR_TEXT, ErrorText),
    PanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(PanelSizer, ErrorText,
        	[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
        	 {border, 10}]),
    wxWindow:setSizer(Panel, PanelSizer),
    Panel.

%% Menu constructor according to specification (see gui.hrl).
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

%%%----------------------------------------------------------------------
%%% GUI element reference store/retrieve interface
%%%----------------------------------------------------------------------

ref_add(Id, Ref) ->
    ets:insert(?NT_REF, {Id, Ref}).

ref_lookup(Id) ->
    ets:lookup_element(?NT_REF, Id, 2).

ref_start() ->
    ets:new(?NT_REF, [set, named_table]).

ref_stop() ->
    ets:delete(?NT_REF).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

addArgs(_Parent, _Sizer, Max, Max, Refs) ->
    lists:reverse(Refs);
addArgs(Parent, Sizer, I, Max, Refs) ->
    %% XXX: semi-hack, custom width, default height (-1)
    Ref =  wxTextCtrl:new(Parent, ?wxID_ANY, [{size, {170, -1}}]),
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
    DefaultDir = ref_lookup(?FILE_PATH),
    DefaultFile = "",
    Dialog = wxFileDialog:new(Parent, [{message, Caption},
                                       {defaultDir, DefaultDir},
                                       {defaultFile, DefaultFile},
                                       {wildCard, Wildcard},
                                       {style, ?wxFD_OPEN bor
                                               ?wxFD_FILE_MUST_EXIST bor
                                               ?wxFD_MULTIPLE}]),
    case wxDialog:showModal(Dialog) of
	?wxID_OK ->
            Files = wxFileDialog:getPaths(Dialog),
	    addListItems(?MODULE_LIST, Files),
            snapshot_add_files(Files),
	    ref_add(?FILE_PATH, getDirectory());
	_Other -> continue
    end,
    wxDialog:destroy(Dialog).

%% Add items to ListBox (Id) and select first of newly added modules
addListItems(Id, Items) ->
    List = ref_lookup(Id),
    Count = wxControlWithItems:getCount(List),
    wxListBox:insertItems(List, Items, Count),
    case Count of
	0 -> wxControlWithItems:setSelection(List, 0);
	_Other -> wxControlWithItems:setSelection(List, Count)
    end.

%% Analyze selected function.
analyze() ->
    Module = getModule(),
    {Function, Arity} = getFunction(),
    ModuleList = ref_lookup(?MODULE_LIST),
    %% Get the list of files to be instrumented.
    Files = getStrings(ModuleList),
    %% Check if a module and function is selected.
    if Module =/= '', Function =/= '' ->
	    case Arity of
		0 -> analyze_aux(Module, Function, [], Files);
		%% If the function to be analyzed is of non-zero arity,
		%% a dialog window is displayed prompting the user to enter
		%% the function's arguments.
		Count ->
		    Frame = ref_lookup(?FRAME),
		    case argDialog(Frame, Count) of
			{ok, Args} ->
                            analyze_aux(Module, Function, Args, Files);
			%% User pressed 'cancel' or closed dialog window.
			_Other -> continue
		    end
	    end;
       true -> continue
    end.

analyze_aux(Module, Function, Args, Files) ->
    analysis_init(),
    Target = {Module, Function, Args},
    Opts = [{files, Files}],
    NewOpts = case ref_lookup(?PREF_PREB_ENABLED) of
		  true -> Opts ++ [{preb, ref_lookup(?PREF_PREB_BOUND)}];
		  false -> Opts
	      end,
    Result = sched:analyze(Target, NewOpts),
    snapshot_add_analysis_ret(Result),
    analysis_cleanup(Result).

%% Initialization actions before starting analysis (clear log, etc.).
analysis_init() ->
    clearLog(),
    clearProbs(),
    clearErrors(),
    clearIleaves(),
    AnalyzeButton = ref_lookup(?ANALYZE),
    wxWindow:disable(AnalyzeButton).

%% Cleanup actions after completing analysis
%% (reactivate `analyze` button, etc.).
analysis_cleanup({error, analysis, _Info, Tickets}) ->
    Errors = [ticket:get_error(Ticket) || Ticket <- Tickets],
    ErrorItems = [io_lib:format("~s~n~s",
                                [error:error_type_to_string(Error),
                                 error:error_reason_to_string(Error, short)])
                  || Error <- Errors],
    setListItems(?ERROR_LIST, ErrorItems),
    ListOfEmpty = lists:duplicate(length(Tickets), []),
    setListData(?ERROR_LIST, lists:zip(Tickets, ListOfEmpty)),
    AnalyzeButton = ref_lookup(?ANALYZE),
    wxWindow:enable(AnalyzeButton);
analysis_cleanup(_Result) ->
    AnalyzeButton = ref_lookup(?ANALYZE),
    wxWindow:enable(AnalyzeButton).

%% Dialog prompting the user to insert function arguments (valid erlang terms
%% without the terminating `.`).
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
            clearProbs(),
	    ValResult = validateArgs(0, Refs, [], ref_lookup(?ERROR_TEXT)),
	    wxDialog:destroy(Dialog),
	    case ValResult of
		{ok, Args} -> {ok, Args};
		_Other -> argDialog(Parent, Argnum)
	    end;
	_Other -> wxDialog:destroy(Dialog), continue
    end.

%% Preferences dialog.
prefsDialog(Parent) ->
    %% Get current preferences.
    PrebEnabled = ref_lookup(?PREF_PREB_ENABLED),
    PrebBound = ref_lookup(?PREF_PREB_BOUND),
    %% Set up sizers and components.
    Dialog = wxDialog:new(Parent, ?wxID_ANY, "Preferences"),
    TopSizer = wxBoxSizer:new(?wxVERTICAL),
    %% Preemption bounding options.
    PrebBox = wxStaticBox:new(Dialog, ?wxID_ANY, "Preemption bounding"),
    PrebBoxSizer = wxStaticBoxSizer:new(PrebBox, ?wxVERTICAL),
    HorizSizer1 = wxBoxSizer:new(?wxHORIZONTAL),
    %% Semi-hack: Custom width, default height.
    PrebEnabledCheckBox = wxCheckBox:new(Dialog, ?PREB_ENABLED_CBOX,
					 "",
					 [{style, ?wxALIGN_RIGHT}]),
    ref_add(?PREB_ENABLED_CBOX, PrebEnabledCheckBox),
    wxCheckBox:setValue(PrebEnabledCheckBox, PrebEnabled),
    wxSizer:add(HorizSizer1,
		wxStaticText:new(Dialog, ?wxID_ANY,
				 "Enable preemption bounding:"),
		[{proportion, 1}, {flag, ?wxALIGN_CENTER bor ?wxALL},
		 {border, 0}]),
    wxSizer:add(HorizSizer1,
		PrebEnabledCheckBox,
		[{proportion, 0}, {flag, ?wxALIGN_CENTER bor ?wxALL},
                 {border, 0}]),
    HorizSizer2 = wxBoxSizer:new(?wxHORIZONTAL),
    PrebBoundSpinCtrl = wxSpinCtrl:new(Dialog, [{id, ?PREB_BOUND_SPIN},
						{size, {50, -1}},
						{min, 0},
						{initial, PrebBound}]),
    wxSizer:add(HorizSizer2,
		wxStaticText:new(Dialog, ?wxID_ANY, "Preemption bound:"),
		[{proportion, 1}, {flag, ?wxALIGN_CENTER bor ?wxALL},
                 {border, 0}]),
    wxSizer:add(HorizSizer2,
		PrebBoundSpinCtrl,
		[{proportion, 0}, {flag, ?wxALIGN_CENTER bor ?wxALL},
                 {border, 0}]),
    wxSizer:add(PrebBoxSizer,
		HorizSizer1,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxSizer:add(PrebBoxSizer,
		HorizSizer2,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    %% Buttons.
    ButtonSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(ButtonSizer, wxButton:new(Dialog, ?wxID_CANCEL),
		[{proportion, 3}, {flag, ?wxLEFT}, {border, 0}]),
    wxSizer:addStretchSpacer(ButtonSizer),
    wxSizer:add(ButtonSizer, wxButton:new(Dialog, ?wxID_OK, [{label, "&Save"}]),
		[{proportion, 4}, {flag, ?wxRIGHT}, {border, 0}]),
    %% Top level sizer.
    wxSizer:add(TopSizer, PrebBoxSizer,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
		 {border, 10}]),
    wxSizer:add(TopSizer, ButtonSizer,
                [{proportion, 0},
		 {flag, ?wxALIGN_CENTER bor ?wxEXPAND bor
		        ?wxRIGHT bor ?wxLEFT bor ?wxBOTTOM},
		 {border, 10}]),
    wxWindow:setSizer(Dialog, TopSizer),
    wxSizer:fit(TopSizer, Dialog),
    %% Show dialog.
    case wxDialog:showModal(Dialog) of
	?wxID_OK ->
	    %% Save preferences.
	    ref_add(?PREF_PREB_ENABLED,
		    wxCheckBox:getValue(PrebEnabledCheckBox)),
	    ref_add(?PREF_PREB_BOUND,
		    wxSpinCtrl:getValue(PrebBoundSpinCtrl));
	_Other ->
	    continue
    end.

%% For now always load default preferences on startup.
loadPrefs() ->
    [ref_add(Id, Value) || {Id, Value} <- ?DEFAULT_PREFS].

%% Do nothing for now.
savePrefs() ->
    ok.
    
clearAll() ->
    clearMods(),
    clearFuns(),
    clearSrc(),
    clearLog(),
    clearProbs(),
    clearErrors(),
    clearIleaves().

clearErrors() ->
    ErrorList = ref_lookup(?ERROR_LIST),
    wxListBox:setSelection(ErrorList, ?wxNOT_FOUND),
    wxControlWithItems:clear(ErrorList).

clearFuns() ->
    FunctionList = ref_lookup(?FUNCTION_LIST),
    wxListBox:setSelection(FunctionList, ?wxNOT_FOUND),
    wxControlWithItems:clear(FunctionList).

clearIleaves() ->
    IleaveList = ref_lookup(?ILEAVE_LIST),
    wxListBox:setSelection(IleaveList, ?wxNOT_FOUND),
    wxControlWithItems:clear(IleaveList).

clearLog() ->
    LogText = ref_lookup(?LOG_TEXT),
    wxTextCtrl:clear(LogText).

clearMods() ->
    ModuleList = ref_lookup(?MODULE_LIST),
    wxListBox:setSelection(ModuleList, ?wxNOT_FOUND),
    wxControlWithItems:clear(ModuleList).

clearProbs() ->
    ErrorText = ref_lookup(?ERROR_TEXT),
    wxTextCtrl:clear(ErrorText).

clearSrc() ->
    SourceText = ref_lookup(?SOURCE_TEXT),
    wxStyledTextCtrl:setReadOnly(SourceText, false),
    wxStyledTextCtrl:clearAll(SourceText),
    wxStyledTextCtrl:setReadOnly(SourceText, true).

%% Export dialog
exportDialog(Parent) ->
    Caption = "Export to " ++ ?APP_STRING ++ " file",
    Wildcard = ?APP_STRING ++ " files |*" ++ ?APP_FILE,
    DefaultDir = ref_lookup(?FILE_PATH),
    DefaultFile = "",
    Dialog = wxFileDialog:new(Parent, [{message, Caption},
                                       {defaultDir, DefaultDir},
                                       {defaultFile, DefaultFile},
                                       {wildCard, Wildcard},
                                       {style, ?wxFD_SAVE bor
                                            ?wxFD_OVERWRITE_PROMPT}]),
    wxFileDialog:setFilename(Dialog, ?EXPORT_FILE ++ ?APP_FILE),
    case wxDialog:showModal(Dialog) of
	?wxID_OK -> snapshot_export(wxFileDialog:getPath(Dialog));
	_Other -> continue
    end,
    wxDialog:destroy(Dialog).

%% Return the directory path of selected module.
getDirectory() ->
    ModuleList = ref_lookup(?MODULE_LIST),
    Path = wxControlWithItems:getStringSelection(ModuleList),
    Match =  re:run(Path, "(?<PATH>.*)/*?\.erl\$",
                    [dotall, {capture, ['PATH'], list}]),
    case Match of
	{match, [Dir]} -> Dir;
	nomatch -> ""
    end.

%% Return the selected function and arity from the function list.
%% The result is returned in the form {Function, Arity}, where Function
%% is an atom and Arity is an integer.
getFunction() ->
    FunctionList = ref_lookup(?FUNCTION_LIST),
    Expr = wxControlWithItems:getStringSelection(FunctionList),
    Match = re:run(Expr, "(?<FUN>.*)/(?<ARITY>.*)\$",
                   [dotall, {capture, ['FUN', 'ARITY'], list}]),
    case Match of
	{match, [Fun, Arity]} ->
	    {list_to_atom(Fun), list_to_integer(Arity)};
	nomatch -> {'', 0}
    end.

%% Return the selected module from the module list.
%% The result is an atom.
getModule() ->
    ModuleList = ref_lookup(?MODULE_LIST),
    Path = wxControlWithItems:getStringSelection(ModuleList),
    Match =  re:run(Path, ".*/(?<MODULE>.*?)\.erl\$",
                    [dotall, {capture, ['MODULE'], list}]),
    case Match of
	{match, [Module]} -> list_to_atom(Module);
	nomatch -> ''
    end.

%% wxControlWithItems:getStrings (function missing from wxErlang lib).
getStrings(Ref) ->
    Count = wxControlWithItems:getCount(Ref),
    if Count > 0 -> getStrings(Ref, 0, Count, []);
       true -> []
    end.

%% Auxiliary function to the above.
getStrings(_Ref, Count, Count, Strings) ->
    Strings;
getStrings(Ref, N, Count, Strings) ->
    String = wxControlWithItems:getString(Ref, N),
    getStrings(Ref, N + 1, Count, [String|Strings]).

%% Import dialog
importDialog(Parent) ->
    Caption = "Import from " ++ ?APP_STRING ++ " file",
    Wildcard = ?APP_STRING ++ " files |*" ++ ?APP_FILE,
    DefaultDir = ref_lookup(?FILE_PATH),
    DefaultFile = "",
    Dialog = wxFileDialog:new(Parent, [{message, Caption},
                                       {defaultDir, DefaultDir},
                                       {defaultFile, DefaultFile},
                                       {wildCard, Wildcard},
                                       {style, ?wxFD_OPEN bor
                                            ?wxFD_FILE_MUST_EXIST}]),
    case wxDialog:showModal(Dialog) of
	?wxID_OK -> snapshot_import(wxFileDialog:getPath(Dialog));
	_Other -> continue
    end,
    wxDialog:destroy(Dialog).

%% Refresh selected module (reload source code from disk).
%% NOTE: When switching selected modules, no explicit refresh
%%       by the user is required, because the `command_listbox_selected`
%%       event for the module-list uses this function.
refresh() ->
    ModuleList = ref_lookup(?MODULE_LIST),
    case wxListBox:getSelection(ModuleList) of
	?wxNOT_FOUND -> continue;
	_Other ->
	    Module = wxListBox:getStringSelection(ModuleList),
	    %% Scan selected module for exported functions.
	    Funs = util:funs(Module, string),
	    setListItems(?FUNCTION_LIST, Funs),
	    %% Update source viewer.
	    SourceText = ref_lookup(?SOURCE_TEXT),
	    wxStyledTextCtrl:setReadOnly(SourceText, false),
	    wxStyledTextCtrl:loadFile(SourceText, Module),
	    wxStyledTextCtrl:setReadOnly(SourceText, true)
    end.

%% Refresh source code (show selected function).
refreshFun() ->
    Module = getModule(),
    {Function, Arity} = getFunction(),
    %% Check if a module and function is selected.
    if Module =/= '', Function =/= '' ->
            ModuleList = ref_lookup(?MODULE_LIST),
            case wxListBox:getSelection(ModuleList) of
                ?wxNOT_FOUND -> continue;
                _Other ->
                    Path = wxListBox:getStringSelection(ModuleList),
                    %% Scan selected module for selected function line number.
                    Line = util:funLine(Path, Function, Arity),
                    %% Update source viewer.
                    SourceText = ref_lookup(?SOURCE_TEXT),
                    wxStyledTextCtrl:gotoLine(SourceText, Line),
                    wxStyledTextCtrl:lineUpExtend(SourceText)
            end;
       true -> continue
    end.

%% Remove selected module from module list.
remove() ->
    ModuleList = ref_lookup(?MODULE_LIST),
    Selection = wxListBox:getSelection(ModuleList),
    SourceText = ref_lookup(?SOURCE_TEXT),
    if Selection =:= ?wxNOT_FOUND ->
	    continue;
       true ->
	    wxControlWithItems:delete(ModuleList, Selection),
	    Count = wxControlWithItems:getCount(ModuleList),
	    if Count =:= 0 ->
                    clearFuns(),
		    wxStyledTextCtrl:setReadOnly(SourceText, false),
		    wxStyledTextCtrl:clearAll(SourceText),
		    wxStyledTextCtrl:setReadOnly(SourceText, true);
	       Selection =:= Count ->
		    wxControlWithItems:setSelection(ModuleList, Selection - 1);
	       true ->
		    wxControlWithItems:setSelection(ModuleList, Selection)
	    end
    end.

%% XXX: hack (send event message to self)
send_event_msg_to_self(Id) ->
    ?RP_GUI ! #wx{id = Id,
                  event = #wxCommand{type = command_listbox_selected}}.

%% Set ListBox (Id) data (remove existing).
setListData(Id, DataList) ->
    setListData_aux(Id, DataList, 0).

setListData_aux(_Id, [], _N) ->
    ok;
setListData_aux(Id, [Data|Rest], N) ->
    List = ref_lookup(Id),
    wxControlWithItems:setClientData(List, N, Data),
    setListData_aux(Id, Rest, N + 1).

%% Set ListBox (Id) items (remove existing).
setListItems(Id, Items) ->
    if Items =/= [], Items =/= [[]] ->
	    List = ref_lookup(Id),
	    wxListBox:set(List, Items),
	    wxControlWithItems:setSelection(List, 0);
       true -> continue
    end.

%% Show detailed interleaving information about the selected error.
show_details() ->
    ErrorList = ref_lookup(?ERROR_LIST),
    IleaveList = ref_lookup(?ILEAVE_LIST),
    case wxControlWithItems:getSelection(ErrorList) of
	?wxNOT_FOUND -> continue;
	Id ->
	    wxControlWithItems:clear(IleaveList),
            Ticket =
                case wxControlWithItems:getClientData(ErrorList, Id) of
                    {T, []} ->
			%% Disable log event handler while replaying.
			log:detach(?MODULE, []),
                        Details = sched:replay(T),
			log:attach(?MODULE, wx:get_env()),
                        NewData = {T, Details},
                        wxControlWithItems:setClientData(ErrorList, Id,
                                                         NewData),
                        setListItems(?ILEAVE_LIST, details_to_strings(Details)),
                        T;
                    {T, Cached} ->
                        setListItems(?ILEAVE_LIST, details_to_strings(Cached)),
                        T
                end,
            Error = ticket:get_error(Ticket),
            ErrorReason = error:error_reason_to_string(Error, long),
            ErrorStack = error: error_stack_to_string(Error),
            clearProbs(),
            Reason = io_lib:format("Reason: ~s~n", [ErrorReason]),
            Stack = io_lib:format("Stack trace: ~s", [ErrorStack]),
            ErrorText = ref_lookup(?ERROR_TEXT),
            wxTextCtrl:appendText(ErrorText, Reason),
            wxTextCtrl:appendText(ErrorText, Stack)
    end.

%% Function to be moved (to sched or util).
details_to_strings(Details) ->
    [detail_to_string(Detail) || Detail <- Details].

detail_to_string({block, Proc}) ->
    io_lib:format("Process ~s blocks", [Proc]);
detail_to_string({exit, Proc, Reason}) ->
    io_lib:format("Process ~s exits (~p)", [Proc, Reason]);
detail_to_string({link, Proc1, Proc2}) ->
    io_lib:format("Process ~s links to process ~s", [Proc1, Proc2]);
detail_to_string({'process_flag', Proc, Flag, Value}) ->
    io_lib:format("Process ~s sets flag '~p' to '~p'", [Proc, Flag, Value]);
detail_to_string({'receive', Receiver, Sender, Msg}) ->
    io_lib:format("Process ~s receives message `~p` from process ~s",
		  [Receiver, Msg, Sender]);
detail_to_string({'receive', Receiver, Msg}) ->
    io_lib:format("Process ~s receives message `~p`", [Receiver, Msg]);
detail_to_string({send, Sender, Receiver, Msg}) ->
    io_lib:format("Process ~s sends message `~p` to process ~s",
		  [Sender, Msg, Receiver]);
detail_to_string({spawn, Parent, Child}) ->
    io_lib:format("Process ~s spawns process ~s", [Parent, Child]);
detail_to_string({spawn_link, Parent, Child}) ->
    io_lib:format("Process ~s spawns and links to process ~s",
		  [Parent, Child]).


%% Validate user provided function arguments.
%% The arguments are first scanned and then parsed to ensure that they
%% represent valid erlang terms.
%% Returns {ok, ListOfArgs} if everything is valid, else 'error' is returned
%% and error messages are written to the log.
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
%%% Snapshot utilities
%%%----------------------------------------------------------------------

snapshot_add_analysis_ret(AnalysisRet) ->
    ref_add(?ANALYSIS_RET, AnalysisRet).

snapshot_add_files(Files) ->
    ref_add(?FILES, Files).

snapshot_cleanup() ->
    os:cmd("rm -rf " ++ ?IMPORT_DIR).

snapshot_export(Export) ->
    AnalysisRet = ref_lookup(?ANALYSIS_RET),
    Files = ref_lookup(?FILES),
    ModuleList = ref_lookup(?MODULE_LIST),
    ModuleID = wxListBox:getSelection(ModuleList),
    FunctionList = ref_lookup(?FUNCTION_LIST),
    FunctionID = wxListBox:getSelection(FunctionList),
    ErrorList = ref_lookup(?ERROR_LIST),
    ErrorID = wxListBox:getSelection(ErrorList),
    IleaveList = ref_lookup(?ILEAVE_LIST),
    IleaveID = wxListBox:getSelection(IleaveList),
    Selection = snapshot:selection(ModuleID, FunctionID,
                                   ErrorID, IleaveID),
    snapshot:export(AnalysisRet, Files, Selection, Export).

snapshot_import(Import) ->
    clearAll(),
    snapshot_cleanup(),
    case snapshot:import(Import) of
        ok -> continue;
        Snapshot ->
            Mods = snapshot:get_modules(Snapshot),
            Files = [[filename:absname(M)] || M <- Mods],
            addListItems(?MODULE_LIST, Files),
            ref_add(?FILE_PATH, getDirectory()),
            Selection = snapshot:get_selection(Snapshot),
            ModuleList = ref_lookup(?MODULE_LIST),
            ModuleID = snapshot:get_module_id(Selection),
            wxControlWithItems:setSelection(ModuleList, ModuleID),
            refresh(),
            FunctionList = ref_lookup(?FUNCTION_LIST),
            FunctionID = snapshot:get_function_id(Selection),
            wxControlWithItems:setSelection(FunctionList, FunctionID),
            refreshFun(),
            AnalysisRet = snapshot:get_analysis(Snapshot),
            case AnalysisRet of
                {ok, _Info} ->
                    log:log("No errors found.~n");
                {error, analysis, _Info, Tickets} ->
                    log:log("Found ~p erroneous interleaving(s).~n",
                            [length(Tickets)]);
                _Other -> continue
            end,
            analysis_cleanup(AnalysisRet),
            ErrorList = ref_lookup(?ERROR_LIST),
            ErrorID = snapshot:get_error_id(Selection),
            wxControlWithItems:setSelection(ErrorList, ErrorID),
            show_details(),
            IleaveList = ref_lookup(?ILEAVE_LIST),
            IleaveID = snapshot:get_ileave_id(Selection),
            wxControlWithItems:setSelection(IleaveList, IleaveID)
    end.

snapshot_init() ->
    ref_add(?ANALYSIS_RET, undef),
    ref_add(?FILES, []).

%%%----------------------------------------------------------------------
%%% Main event loop
%%%----------------------------------------------------------------------

loop() ->
    receive
	%% -------------------- Button handlers -------------------- %%
	#wx{id = ?ADD, event = #wxCommand{type = command_button_clicked}} ->
	    Frame = ref_lookup(?FRAME),
	    addDialog(Frame),
            send_event_msg_to_self(?MODULE_LIST),
	    loop();
	#wx{id = ?ANALYZE, event = #wxCommand{type = command_button_clicked}} ->
	    analyze(),
            send_event_msg_to_self(?ERROR_LIST),
	    loop();
	#wx{id = ?CLEAR, event = #wxCommand{type = command_button_clicked}} ->
            clearMods(),
            clearFuns(),
            clearSrc(),
	    loop();
	#wx{id = ?REMOVE, event = #wxCommand{type = command_button_clicked}} ->
	    remove(),
	    loop();
	%% -------------------- Listbox handlers --------------------- %%
	#wx{id = ?ERROR_LIST,
	    event = #wxCommand{type = command_listbox_doubleclicked}} ->
	    %% do nothing
	    loop();
	#wx{id = ?ERROR_LIST,
            event = #wxCommand{type = command_listbox_selected}} ->
	    show_details(),
            send_event_msg_to_self(?ILEAVE_LIST),
	    loop();
	#wx{id = ?ILEAVE_LIST,
	    event = #wxCommand{type = command_listbox_doubleclicked}} ->
	    %% do nothing
	    loop();
	#wx{id = ?ILEAVE_LIST,
            event = #wxCommand{type = command_listbox_selected}} ->
	    %% do nothing
	    loop();
	#wx{id = ?FUNCTION_LIST,
	    event = #wxCommand{type = command_listbox_doubleclicked}} ->
	    analyze(),
            send_event_msg_to_self(?ERROR_LIST),
	    loop();
	#wx{id = ?FUNCTION_LIST,
	    event = #wxCommand{type = command_listbox_selected}} ->
            refreshFun(),
	    loop();
	#wx{id = ?MODULE_LIST,
	    event = #wxCommand{type = command_listbox_doubleclicked}} ->
	    %% do nothing
	    loop();
	#wx{id = ?MODULE_LIST,
            event = #wxCommand{type = command_listbox_selected}} ->
	    refresh(),
            send_event_msg_to_self(?FUNCTION_LIST),
	    loop();
	%% -------------------- Menu handlers -------------------- %%
	#wx{id = ?ABOUT, event = #wxCommand{type = command_menu_selected}} ->
	    Caption = "About" ++ ?APP_STRING,
	    Frame = ref_lookup(?FRAME),
	    Dialog = wxMessageDialog:new(Frame, ?INFO_MSG,
                                         [{style, ?wxOK}, {caption, Caption}]),
	    wxDialog:showModal(Dialog),
	    wxWindow:destroy(Dialog),
	    loop();
	#wx{id = ?ADD, event = #wxCommand{type = command_menu_selected}} ->
	    Frame = ref_lookup(?FRAME),
	    addDialog(Frame),
            send_event_msg_to_self(?MODULE_LIST),
	    loop();
	#wx{id = ?ANALYZE, event = #wxCommand{type = command_menu_selected}} ->
	    analyze(),
            send_event_msg_to_self(?ERROR_LIST),
	    loop();
	#wx{id = ?CLEAR, event = #wxCommand{type = command_menu_selected}} ->
            clearMods(),
            clearFuns(),
            clearSrc(),
	    loop();
        #wx{id = ?EXPORT, event = #wxCommand{type = command_menu_selected}} ->
            Frame = ref_lookup(?FRAME),
            exportDialog(Frame),
	    loop();
        #wx{id = ?IMPORT, event = #wxCommand{type = command_menu_selected}} ->
            Frame = ref_lookup(?FRAME),
            importDialog(Frame),
	    loop();
	#wx{id = ?PREFS, event = #wxCommand{type = command_menu_selected}} ->
	    Frame = ref_lookup(?FRAME),
	    prefsDialog(Frame),
	    loop();
	#wx{id = ?THEME_LIGHT,
	    event = #wxCommand{type = command_menu_selected}} ->
	    SourceText = ref_lookup(?SOURCE_TEXT),
	    setupSourceText(SourceText, light),
	    loop();
	#wx{id = ?THEME_DARK,
	    event = #wxCommand{type = command_menu_selected}} ->
	    SourceText = ref_lookup(?SOURCE_TEXT),
	    setupSourceText(SourceText, dark),
	    loop();
	#wx{id = ?REFRESH, event = #wxCommand{type = command_menu_selected}} ->
	    refresh(),
            send_event_msg_to_self(?FUNCTION_LIST),
	    loop();
	#wx{id = ?REMOVE, event = #wxCommand{type = command_menu_selected}} ->
	    remove(),
	    loop();
	#wx{id = ?EXIT, event = #wxCommand{type = command_menu_selected}} ->
	    ok;
	%% -------------------- Misc handlers -------------------- %%
	%% FIXME: To be deleted shortly.
	%% #gui{type = dot, msg = ok} ->
	%%     StaticBmp = ref_lookup(?STATIC_BMP),
	%%     ScrGraph = ref_lookup(?SCR_GRAPH),
	%%     os:cmd("dot -Tpng < schedule.dot > schedule.png"),
	%%     Image = wxBitmap:new("schedule.png", [{type, ?wxBITMAP_TYPE_PNG}]),
	%%     {W, H} = {wxBitmap:getWidth(Image), wxBitmap:getHeight(Image)},
	%%     wxScrolledWindow:setScrollbars(ScrGraph, 20, 20, W div 20,
        %%                                    H div 20),
	%%     wxStaticBitmap:setBitmap(StaticBmp, Image),
	%%     %% NOTE: Important, memory leak if left out!
	%%     wxBitmap:destroy(Image),
	%%     loop();
	%% #gui{type = log, msg = String} ->
	%%     ProcText = ref_lookup(?PROC_TEXT),
	%%     wxTextCtrl:appendText(ProcText, String),
	%%     loop();
	#wx{event = #wxClose{type = close_window}} ->
	    ok;
	%% Ignore normal 'EXIT' messages from linked processes.
	%% (Added to ignore exit messages coming from calls to compile:file
	%% and compile:forms)
	{'EXIT', _Pid, normal} ->
	    loop();
	%% -------------------- Catchall -------------------- %%
	Other ->
	    io:format("main loop unimplemented: ~p~n", [Other]),
	    loop()
    end.
