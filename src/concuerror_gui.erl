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
%%% Description : Graphical User Interface
%%%----------------------------------------------------------------------

-module(concuerror_gui).

%% UI exports.
-export([start/1]).
%% Log server callback exports.
-export([init/1, terminate/2, handle_event/2]).

-include_lib("wx/include/wx.hrl").
-include("gen.hrl").
-include("gui.hrl").

%% Log event handler internal state.
-type state() :: {non_neg_integer(), %% Verbose level
                  concuerror_util:progress() | 'noprogress'}.

%%%----------------------------------------------------------------------
%%% UI functions
%%%----------------------------------------------------------------------

%% @spec start(concuerror:options()) -> 'true'
%% @doc: Start the Concuerror GUI.
-spec start(concuerror:options()) -> 'true'.

start(Options) ->
    register(?RP_GUI, self()),
    _ = wx:new(),
    %% Start the object reference mapping service.
    ref_start(),
    Frame = setupFrame(),
    wxFrame:show(Frame),
    setSplitterInitSizes(),
    %% Attach the event handler below.
    _ = concuerror_log:attach(?MODULE, {wx:get_env(), Options}),
    %% Load preferences from Options.
    loadPrefs(Options),
    refresh(),
    %% Start the replay server.
    loop(),
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
init({Env, Options}) ->
    wx:set_env(Env),
    Progress =
        case lists:keyfind(noprogress, 1, Options) of
            {noprogress} -> noprogress;
            false -> concuerror_util:init_state()
        end,
    Verbosity =
        case lists:keyfind('verbose', 1, Options) of
            {'verbose', V} -> V;
            false -> 0
        end,
    {ok, {Verbosity, Progress}}.

-spec terminate(term(), state()) -> 'ok'.

terminate(_Reason, {_Verb, 'noprogress'}) ->
    ok;
terminate(_Reason, {_Verb, {_RunCnt, _NumErrors, _Elapsed, Timer}}) ->
    concuerror_util:timer_stop(Timer),
    ok.

-spec handle_event(concuerror_log:event(), state()) -> {'ok', state()}.

handle_event({msg, String, MsgVerb}, {Verb, _Progress}=State) ->
    if
        Verb >= MsgVerb ->
            wxTextCtrl:appendText(ref_lookup(?LOG_TEXT), String);
        true ->
            ok
    end,
    {ok, State};

handle_event({progress, _Type}, {_Verb, 'noprogress'}=State) ->
    {ok, State};
handle_event({progress, Type}, {Verb, Progress}) ->
    case Type of
        {error, Ticket} ->
            Error = concuerror_ticket:get_error(Ticket),
            ErrorItem = concuerror_util:flat_format("~s~n~s",
                [concuerror_error:type(Error), concuerror_error:short(Error)]),
            List = ref_lookup(?ERROR_LIST),
            wxControlWithItems:append(List, ErrorItem),
            addListData(?ERROR_LIST, [Ticket]),
            ok;
        _Other ->
            ok
    end,
    case concuerror_util:progress_bar(Type, Progress) of
        {NewProgress, ""} ->
            {ok, {Verb, NewProgress}};
        {NewProgress, Msg} ->
            This = ref_lookup(?LOG_TEXT),
            NumLines = wxTextCtrl:getNumberOfLines(This),
            FromPos = wxTextCtrl:xYToPosition(This, 0, NumLines-1),
            EndPos  = wxTextCtrl:getLastPosition(This),
            wxTextCtrl:replace(This, FromPos, EndPos, Msg),
            {ok, {Verb, NewProgress}}
    end;

handle_event('reset', {_Verb, 'noprogress'}=State) ->
    {ok, State};
handle_event('reset', {Verb, _Progress}) ->
    {ok, {Verb, concuerror_util:init_state()}}.


%%%----------------------------------------------------------------------
%%% Setup functions
%%%----------------------------------------------------------------------

setupFrame() ->
    Frame = wxFrame:new(wx:null(), ?FRAME, ?APP_STRING),
    ref_add(?FRAME, Frame),
    MenuBar = wxMenuBar:new(),
    setupMenu(MenuBar, ?MENU_SPEC),
    wxFrame:setMenuBar(Frame, MenuBar),
    _ = wxFrame:createStatusBar(Frame, [{id, ?STATUS_BAR}]),
    wxEvtHandler:connect(Frame, close_window),
    wxEvtHandler:connect(Frame, command_menu_selected),
    wxEvtHandler:connect(Frame, command_button_clicked),
    wxEvtHandler:connect(Frame, command_listbox_selected),
    wxEvtHandler:connect(Frame, command_listbox_doubleclicked),
    wxEvtHandler:connect(Frame, command_splitter_sash_pos_changed),
    _ = setupTopSplitter(Frame),
    wxWindow:setSize(Frame, ?FRAME_SIZE_INIT),
    %% wxWindow:fit(Frame),
    wxFrame:center(Frame),
    Frame.

setupTopSplitter(Parent) ->
    Splitter = wxSplitterWindow:new(Parent, [{id, ?TOP_SPLITTER}]),
    ref_add(?TOP_SPLITTER, Splitter),
    LeftPanel = wxPanel:new(Splitter),
    LeftSizer = setupLeftColumn(LeftPanel),
    wxWindow:setSizer(LeftPanel, LeftSizer),
    _ = wxSizer:fit(LeftSizer, LeftPanel),
    RightPanel = wxPanel:new(Splitter),
    RightSizer = setupRightColumn(RightPanel),
    wxWindow:setSizer(RightPanel, RightSizer),
    _ = wxSizer:fit(RightSizer, RightPanel),
    wxSplitterWindow:setMinimumPaneSize(Splitter, ?MIN_TOP),
    wxSplitterWindow:setSashGravity(Splitter, ?GRAV_TOP),
    wxSplitterWindow:splitVertically(Splitter, LeftPanel, RightPanel),
    Splitter.

%% Sets initial sizes for all splitters.
setSplitterInitSizes() ->
    Fun = fun(S, V) -> wxSplitterWindow:setSashPosition(ref_lookup(S), V)
          end,
    lists:foreach(fun ({S, V}) -> Fun(S, V) end, ?SPLITTER_INIT).

%% Setup left column of top-level panel, including module and function
%% listboxes and several buttons.
setupLeftColumn(Parent) ->
    Splitter = wxSplitterWindow:new(Parent, [{id, ?MOD_FUN_SPLITTER}]),
    ref_add(?MOD_FUN_SPLITTER, Splitter),
    ModulePanel = wxPanel:new(Splitter),
    ModuleSizer = setupModuleSizer(ModulePanel),
    wxWindow:setSizerAndFit(ModulePanel, ModuleSizer),
    FunctionPanel = wxPanel:new(Splitter),
    FunctionSizer = setupFunctionSizer(FunctionPanel),
    wxWindow:setSizerAndFit(FunctionPanel, FunctionSizer),
    wxSplitterWindow:setMinimumPaneSize(Splitter, ?MIN_MOD_FUN),
    wxSplitterWindow:setSashGravity(Splitter, ?GRAV_MOD_FUN),
    wxSplitterWindow:splitHorizontally(Splitter, ModulePanel, FunctionPanel),
    %% Add padding to the whole sizer.
    LeftColumnSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(LeftColumnSizerOuter, Splitter,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    LeftColumnSizerOuter.

setupModuleSizer(Parent) ->
    ModuleBox = wxStaticBox:new(Parent, ?wxID_ANY, "Modules"),
    ModuleList = wxListBox:new(Parent, ?MODULE_LIST),
    ref_add(?MODULE_LIST, ModuleList),
    AddButton = wxButton:new(Parent, ?ADD),
    RemButton = wxButton:new(Parent, ?REMOVE),
    ClearButton = wxButton:new(Parent, ?CLEAR),
    RefreshButton = wxButton:new(Parent, ?REFRESH),
    %% Setup button sizers
    AddRemSizer = wxBoxSizer:new(?wxHORIZONTAL),
    _ = wxSizer:add(AddRemSizer, AddButton,
                    [{proportion, 1}, {flag, ?wxRIGHT}, {border, 5}]),
    _ = wxSizer:add(AddRemSizer, RemButton,
                    [{proportion, 1}, {flag, ?wxLEFT}, {border, 5}]),
    ClrSizer = wxBoxSizer:new(?wxHORIZONTAL),
    _ = wxSizer:add(ClrSizer, ClearButton,
                    [{proportion, 1}, {flag, ?wxRIGHT}, {border, 5}]),
    _ = wxSizer:add(ClrSizer, RefreshButton,
                    [{proportion, 1}, {flag, ?wxLEFT}, {border, 5}]),
    %% Setup module sizers
    ModuleSizer = wxStaticBoxSizer:new(ModuleBox, ?wxVERTICAL),
    _ = wxSizer:add(ModuleSizer, ModuleList,
                    [{proportion, 1},
                     {flag, ?wxEXPAND bor ?wxTOP bor ?wxLEFT bor ?wxRIGHT},
                     {border, 10}]),
    _ = wxSizer:add(ModuleSizer, AddRemSizer,
                    [{proportion, 0},
                     {flag, ?wxEXPAND bor ?wxTOP bor ?wxLEFT bor ?wxRIGHT},
                     {border, 10}]),
    _ = wxSizer:add(ModuleSizer, ClrSizer,
                    [{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    %% Add padding to the whole sizer.
    ModuleSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(ModuleSizerOuter, ModuleSizer,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxBOTTOM},
                     {border, 5}]),
    ModuleSizerOuter.

setupFunctionSizer(Parent) ->
    %% Create widgets
    FunctionBox = wxStaticBox:new(Parent, ?wxID_ANY, "Functions"),
    FunctionList = wxListBox:new(Parent, ?FUNCTION_LIST, [{style, ?wxLB_SORT}]),
    ref_add(?FUNCTION_LIST, FunctionList),
    AnalyzeButton = wxButton:new(Parent, ?ANALYZE, [{label, "Ana&lyze"}]),
    ref_add(?ANALYZE, AnalyzeButton),
    StopButton = wxButton:new(Parent, ?STOP, [{label, "&Stop"}]),
    ref_add(?STOP, StopButton),
    %% Setup sizers
    AnalStopSizer = wxBoxSizer:new(?wxHORIZONTAL),
    _ = wxSizer:add(AnalStopSizer, AnalyzeButton,
                    [{proportion, 1}, {flag, ?wxRIGHT}, {border, 5}]),
    _ = wxSizer:add(AnalStopSizer, StopButton,
                    [{proportion, 1}, {flag, ?wxLEFT}, {border, 5}]),
    ref_add(?ANAL_STOP_SIZER, AnalStopSizer),
    FunctionSizer = wxStaticBoxSizer:new(FunctionBox, ?wxVERTICAL),
    _ = wxSizer:add(FunctionSizer, FunctionList,
                    [{proportion, 1},
                     {flag, ?wxEXPAND bor ?wxTOP bor ?wxLEFT bor ?wxRIGHT},
                     {border, 10}]),
    _ = wxSizer:add(FunctionSizer, AnalStopSizer,
                    [{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    %% Add padding to the whole sizer.
    FunctionSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(FunctionSizerOuter, FunctionSizer,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxTOP},
                     {border, 0}]),
    FunctionSizerOuter.

%% Setup right column of top-level panel, including a notebook for displaying
%% tabbed main, graph and source code panels and another notebook for displaying
%% log messages.
setupRightColumn(Parent) ->
    Splitter = wxSplitterWindow:new(Parent, [{id, ?NOTEBOOK_SPLITTER}]),
    ref_add(?NOTEBOOK_SPLITTER, Splitter),
    TopPanel = wxPanel:new(Splitter),
    TopSizer = setupMainNotebookSizer(TopPanel),
    wxWindow:setSizerAndFit(TopPanel, TopSizer),
    BottomPanel = wxPanel:new(Splitter),
    BottomSizer = setupLogNotebookSizer(BottomPanel),
    wxWindow:setSizerAndFit(BottomPanel, BottomSizer),
    wxSplitterWindow:setMinimumPaneSize(Splitter, ?MIN_NOTEBOOK),
    wxSplitterWindow:setSashGravity(Splitter, ?GRAV_NOTEBOOK),
    wxSplitterWindow:splitHorizontally(Splitter, TopPanel, BottomPanel),
    %% Add padding to the whole sizer.
    RightColumnSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(RightColumnSizerOuter, Splitter,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    RightColumnSizerOuter.

%% Setup main notebook, containing 3 tabs:
%% Main tab: Contains a list showing the errors encountered and another list
%%           showing the selected erroneous interleaving.
%% Graph tab: Displays a process interaction graph of the selected erroneous
%%            interleaving.
%% Source tab: Displays the source code for the selected module.
%% TODO: Temporarily removed graph tab.
setupMainNotebookSizer(Parent) ->
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
    %% Add padding to the notebook.
    NotebookSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(NotebookSizerOuter, Notebook,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxBOTTOM},
                     {border, 5}]),
    NotebookSizerOuter.

setupMainPanel(Parent) ->
    MainPanel = wxPanel:new(Parent),
    Splitter = wxSplitterWindow:new(MainPanel, [{id, ?ERROR_ILEAVE_SPLITTER}]),
    ref_add(?ERROR_ILEAVE_SPLITTER, Splitter),
    ErrorPanel = wxPanel:new(Splitter),
    ErrorSizer = setupErrorListSizer(ErrorPanel),
    wxWindow:setSizerAndFit(ErrorPanel, ErrorSizer),
    IleavePanel = wxPanel:new(Splitter),
    IleaveSizer = setupIleaveListSizer(IleavePanel),
    wxWindow:setSizerAndFit(IleavePanel, IleaveSizer),
    wxSplitterWindow:setMinimumPaneSize(Splitter, ?MIN_ERROR_ILEAVE),
    wxSplitterWindow:setSashGravity(Splitter, ?GRAV_ERROR_ILEAVE),
    wxSplitterWindow:splitVertically(Splitter, ErrorPanel, IleavePanel),
    %% Add padding to the panel.
    MainPanelSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(MainPanelSizerOuter, Splitter,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    wxWindow:setSizer(MainPanel, MainPanelSizerOuter),
    MainPanel.

setupErrorListSizer(Parent) ->
    ErrorBox = wxStaticBox:new(Parent, ?wxID_ANY, "Errors"),
    ErrorList = wxListBox:new(Parent, ?ERROR_LIST),
    ref_add(?ERROR_LIST, ErrorList),
    %% Setup sizers.
    ErrorSizer = wxStaticBoxSizer:new(ErrorBox, ?wxVERTICAL),
    _ = wxSizer:add(ErrorSizer, ErrorList,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    %% Add padding to the whole sizer.
    ErrorSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(ErrorSizerOuter, ErrorSizer,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxRIGHT},
                     {border, 5}]),
    ErrorSizerOuter.

setupIleaveListSizer(Parent) ->
    IleaveBox = wxStaticBox:new(Parent, ?wxID_ANY, "Process interleaving"),
    IleaveList = wxListBox:new(Parent, ?ILEAVE_LIST),
    ref_add(?ILEAVE_LIST, IleaveList),
    %% Setup sizers.
    IleaveSizer = wxStaticBoxSizer:new(IleaveBox, ?wxVERTICAL),
    _ = wxSizer:add(IleaveSizer, IleaveList,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    %% Add padding to the whole sizer.
    IleaveSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(IleaveSizerOuter, IleaveSizer,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxLEFT},
                     {border, 5}]),
    IleaveSizerOuter.

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
    _ = wxSizer:add(PanelSizer, ScrGraph,
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
    _ = wxSizer:add(PanelSizer, SourceText,
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
                                wxStyledTextCtrl:styleSetFont(Ref,
                                                              Style,
                                                              BoldFont);
                            _Other ->
                                wxStyledTextCtrl:styleSetFont(Ref,
                                                              Style,
                                                              NormalFont)
                        end,
                        wxStyledTextCtrl:styleSetForeground(Ref, Style, Color),
                        wxStyledTextCtrl:styleSetBackground(Ref, Style, BgColor)
                end,
    lists:foreach(fun(Style) -> SetStyles(Style) end, Styles),
    wxStyledTextCtrl:setKeyWords(Ref, 0, ?KEYWORDS).

%% Setup a notebook for displaying log messages.
setupLogNotebookSizer(Parent) ->
    %% Log notebook widgets (notebook -> panel -> textcontrol).
    Notebook = wxNotebook:new(Parent, ?LOG_NOTEBOOK,
                              [{style, ?wxNB_NOPAGETHEME}]),
    ref_add(?LOG_NOTEBOOK, Notebook),
    %% Setup tab panels
    LogPanel = setupLogPanel(Notebook),
    ErrorPanel = setupErrorPanel(Notebook),
    %% Add tabs to log notebook.
    wxNotebook:addPage(Notebook, LogPanel, "Log", [{bSelect, true}]),
    wxNotebook:addPage(Notebook, ErrorPanel, "Problems", [{bSelect, false}]),
    NotebookSizerOuter = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(NotebookSizerOuter, Notebook,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxBOTTOM},
                     {border, 0}]),
    NotebookSizerOuter.

setupLogPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    LogText = wxTextCtrl:new(Panel, ?LOG_TEXT,
                             [{style, ?wxTE_MULTILINE bor ?wxTE_READONLY}]),
    ref_add(?LOG_TEXT, LogText),
    Style = wxTextAttr:new(),
    wxTextAttr:setFont(Style, wxFont:new(10, ?wxFONTFAMILY_MODERN,
                                         ?wxFONTSTYLE_NORMAL, -1)),
    wxTextCtrl:setDefaultStyle(LogText, Style),
    PanelSizer = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(PanelSizer, LogText,
                    [{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    wxWindow:setSizer(Panel, PanelSizer),
    Panel.

setupErrorPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    ErrorText = wxTextCtrl:new(Panel, ?ERROR_TEXT,
                               [{style, ?wxTE_MULTILINE bor ?wxTE_READONLY}]),
    ref_add(?ERROR_TEXT, ErrorText),
    Style = wxTextAttr:new(),
    wxTextAttr:setFont(Style, wxFont:new(10, ?wxFONTFAMILY_MODERN,
                                         ?wxFONTSTYLE_NORMAL, -1)),
    wxTextCtrl:setDefaultStyle(ErrorText, Style),
    PanelSizer = wxBoxSizer:new(?wxVERTICAL),
    _ = wxSizer:add(PanelSizer, ErrorText,
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
    Item =
        case lists:keytake(sub, 1, Options) of
            {value, {sub, SubItems}, NewOptions} ->
                Submenu = wxMenu:new(),
                setupMenuItems(Submenu, SubItems),
                I = createMenuItem(NewOptions),
                wxMenuItem:setSubMenu(I, Submenu),
                I;
            false -> createMenuItem(Options)
        end,
    _ = wxMenu:append(Menu, Item),
    setupMenuItems(Menu, Rest).

createMenuItem(Options) ->
    case lists:keytake(label, 1, Options) of
        {value, {label, Label}, NewOptions} ->
            Item = wxMenuItem:new(NewOptions),
            ref_add(Label, Item),
            Item;
        false -> wxMenuItem:new(Options)
    end.

%%%----------------------------------------------------------------------
%%% GUI element reference store/retrieve interface
%%%----------------------------------------------------------------------

ref_add(Id, Ref) ->
    ets:insert(?NT_REF, {Id, Ref}).

ref_lookup(Id) ->
    ets:lookup_element(?NT_REF, Id, 2).

ref_start() ->
    ?NT_REF = ets:new(?NT_REF, [set, public, named_table]),
    ok.

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
    _ = wxSizer:add(HorizSizer,
                    wxStaticText:new(Parent, ?wxID_ANY,
                                     io_lib:format("Arg~p: ", [I + 1])),
                    [{proportion, 0}, {flag, ?wxALIGN_CENTER bor ?wxRIGHT},
                     {border, 5}]),
    _ = wxSizer:add(HorizSizer, Ref, [{proportion, 1},
                                      {flag, ?wxALIGN_CENTER bor ?wxALL},
                                      {border, 0}]),
    _ = wxSizer:add(Sizer, HorizSizer, [{proportion, 0},
                                        {flag, ?wxEXPAND bor ?wxALL},
                                        {border, 10}]),
    addArgs(Parent, Sizer, I + 1, Max, [Ref|Refs]).

%% Module-adding dialog
addDialog(Parent) ->
    Caption = "Open erlang module",
    Wildcard = "Erlang source|*.erl| All files|*",
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
            NewFiles = wxFileDialog:getPaths(Dialog),
            ModuleList = ref_lookup(?MODULE_LIST),
            OldFiles = getStrings(ModuleList),
            case checkDuplicates(OldFiles, NewFiles) of
                false ->
                    addListItems(?MODULE_LIST, NewFiles),
                    ref_add(?FILE_PATH, getDirectory());
                Duplicates ->
                    wxTextCtrl:appendText(ref_lookup(?ERROR_TEXT),
                                          io_lib:format("Duplicate modules: "
                                                        "~p~n",
                                                        [Duplicates])),
                    continue
            end;
        _Other -> continue
    end,
    wxDialog:destroy(Dialog).

addListData(Id, DataList) ->
    List = ref_lookup(Id),
    Count = wxControlWithItems:getCount(List),
    setListData_aux(List, DataList, Count - 1).

%% Add items to ListBox (Id) and select first of newly added modules
addListItems(Id, Items) ->
    List = ref_lookup(Id),
    Count = wxControlWithItems:getCount(List),
    wxListBox:insertItems(List, Items, Count),
    wxControlWithItems:setSelection(List, Count).

analyze_proc() ->
    Env = wx:get_env(),
    spawn_link(fun() ->
                       wx:set_env(Env),
                       analyze(),
                       send_event_msg_to_self(?ERROR_LIST)
               end).

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
    Preb = case ref_lookup(?PREF_PREB_ENABLED) of
                true -> {preb, ref_lookup(?PREF_PREB_BOUND)};
                false -> {preb, inf}
           end,
    Include = {'include', ref_lookup(?PREF_INCLUDE)},
    Define = {'define', ref_lookup(?PREF_DEFINE)},
    Dpor = case ets:lookup(?NT_OPTIONS, 'dpor') of
                [] -> {'dpor', 'none'};
                [Flavor] -> Flavor
           end,
    Opts = [Include, Define, Preb, Dpor],
    Result = concuerror_sched:analyze(Target, Files, Opts),
    ref_add(?ANALYSIS_RET, Result),
    analysis_cleanup().


%% Initialization actions before starting analysis (clear log, etc.).
analysis_init() ->
    Separator = "----o----o----o----o----o----o----o----o----o----o----o\n",
    wxTextCtrl:appendText(ref_lookup(?LOG_TEXT), Separator),
    clearProbs(),
    clearErrors(),
    clearIleaves(),
    disableMenuItems(),
    AnalStopSizer = ref_lookup(?ANAL_STOP_SIZER),
    AnalyzeButton = ref_lookup(?ANALYZE),
    Parent = wxWindow:getParent(AnalyzeButton),
    AnalyzeGauge = wxGauge:new(Parent, ?wxID_ANY, 100,
                               [{style, ?wxGA_HORIZONTAL}]),
    ref_add(?ANALYZE_GAUGE, AnalyzeGauge),
    wxSizer:replace(AnalStopSizer, AnalyzeButton, AnalyzeGauge),
    wxWindow:destroy(AnalyzeButton),
    wxSizer:layout(AnalStopSizer),
    start_pulsing(AnalyzeGauge).

%% Cleanup actions after completing analysis
%% (reactivate `analyze` button, etc.).
analysis_cleanup() ->
    enableMenuItems(),
    AnalyzeGauge = ref_lookup(?ANALYZE_GAUGE),
    stop_pulsing(AnalyzeGauge),
    AnalStopSizer = ref_lookup(?ANAL_STOP_SIZER),
    Parent = wxWindow:getParent(AnalyzeGauge),
    AnalyzeButton = wxButton:new(Parent, ?ANALYZE, [{label, "Ana&lyze"}]),
    ref_add(?ANALYZE, AnalyzeButton),
    wxSizer:replace(AnalStopSizer, AnalyzeGauge, AnalyzeButton),
    wxWindow:destroy(AnalyzeGauge),
    wxMenuItem:enable(ref_lookup(?STOP_MENU_ITEM)),
    try
        StopGauge = ref_lookup(?STOP_GAUGE),
        stop_pulsing(StopGauge),
        StopButton = wxButton:new(Parent, ?STOP, [{label, "&Stop"}]),
        ref_add(?STOP, StopButton),
        wxSizer:replace(AnalStopSizer, StopGauge, StopButton),
        wxWindow:destroy(StopGauge)
    catch
        error:badarg -> continue
    end,
    wxSizer:layout(AnalStopSizer).

checkDuplicates(OldFiles, NewFiles) ->
    OldBase = [concuerror_util:get_module_name(O) || O <- OldFiles],
    NewBase = [concuerror_util:get_module_name(N) || N <- NewFiles],
    IBase = sets:intersection(sets:from_list(OldBase), sets:from_list(NewBase)),
    case sets:size(IBase) of
        0 -> false;
        _ -> sets:to_list(IBase)
    end.

start_pulsing(Gauge) ->
    Env = wx:get_env(),
    Pid = spawn(fun() -> wx:set_env(Env), pulse(Gauge) end),
    [Hash] = io_lib:format("~c", [erlang:phash2(Gauge)]),
    Reg = list_to_atom("_._GP_" ++ Hash),
    register(Reg, Pid).

stop_pulsing(Gauge) ->
    [Hash] = io_lib:format("~c", [erlang:phash2(Gauge)]),
    Reg = list_to_atom("_._GP_" ++ Hash),
    Reg ! stop.

pulse(Gauge) ->
    wxGauge:pulse(Gauge),
    receive
        stop -> ok
    after 200 -> pulse(Gauge)
    end.

%% Dialog prompting the user to insert function arguments (valid erlang terms
%% without the terminating `.`).
argDialog(Parent, Argnum) ->
    Dialog = wxDialog:new(Parent, ?wxID_ANY, "Enter arguments"),
    TopSizer = wxBoxSizer:new(?wxVERTICAL),
    Box = wxStaticBox:new(Dialog, ?wxID_ANY, "Arguments"),
    InSizer = wxStaticBoxSizer:new(Box, ?wxVERTICAL),
    Refs = addArgs(Dialog, InSizer, 0, Argnum, []),
    ButtonSizer = wxBoxSizer:new(?wxHORIZONTAL),
    _ = wxSizer:add(ButtonSizer, wxButton:new(Dialog, ?wxID_OK),
                    [{proportion, 0}, {flag, ?wxRIGHT}, {border, 5}]),
    _ = wxSizer:add(ButtonSizer, wxButton:new(Dialog, ?wxID_CANCEL),
                    [{proportion, 0}, {flag, ?wxLEFT}, {border, 5}]),
    _ = wxSizer:add(TopSizer, InSizer,
                    [{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    _ = wxSizer:add(TopSizer, ButtonSizer,
                    [{proportion, 0},
                     {flag, ?wxALIGN_CENTER bor
                          ?wxRIGHT bor ?wxLEFT bor ?wxBOTTOM},
                     {border, 10}]),
    wxWindow:setSizer(Dialog, TopSizer),
    _ = wxSizer:fit(TopSizer, Dialog),
    case wxDialog:showModal(Dialog) of
        ?wxID_OK ->
            clearProbs(),
            ValResult = validateArgs(0, Refs, [], ?ERROR_TEXT),
            wxDialog:destroy(Dialog),
            case ValResult of
                {ok, _Args} = Ok -> Ok;
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
    _ = wxSizer:add(HorizSizer1,
                    wxStaticText:new(Dialog, ?wxID_ANY,
                                     "Enable preemption bounding:"),
                    [{proportion, 1}, {flag, ?wxALIGN_CENTER bor ?wxALL},
                     {border, 0}]),
    _ = wxSizer:add(HorizSizer1, PrebEnabledCheckBox,
                    [{proportion, 0}, {flag, ?wxALIGN_CENTER bor ?wxALL},
                     {border, 0}]),
    HorizSizer2 = wxBoxSizer:new(?wxHORIZONTAL),
    PrebBoundSpinCtrl = wxSpinCtrl:new(Dialog, [{id, ?PREB_BOUND_SPIN},
                                                {size, {50, -1}},
                                                {min, 0},
                                                {initial, PrebBound}]),
    _ = wxSizer:add(HorizSizer2,
                    wxStaticText:new(Dialog, ?wxID_ANY, "Preemption bound:"),
                    [{proportion, 1}, {flag, ?wxALIGN_CENTER bor ?wxALL},
                     {border, 0}]),
    _ = wxSizer:add(HorizSizer2, PrebBoundSpinCtrl,
                    [{proportion, 0}, {flag, ?wxALIGN_CENTER bor ?wxALL},
                     {border, 0}]),
    _ = wxSizer:add(PrebBoxSizer, HorizSizer1,
                    [{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    _ = wxSizer:add(PrebBoxSizer, HorizSizer2,
                    [{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    %% Buttons.
    ButtonSizer = wxBoxSizer:new(?wxHORIZONTAL),
    _ = wxSizer:add(ButtonSizer, wxButton:new(Dialog, ?wxID_CANCEL),
                    [{proportion, 3}, {flag, ?wxLEFT}, {border, 0}]),
    _ = wxSizer:addStretchSpacer(ButtonSizer),
    _ = wxSizer:add(ButtonSizer,
                    wxButton:new(Dialog, ?wxID_OK, [{label, "&Save"}]),
                    [{proportion, 4}, {flag, ?wxRIGHT}, {border, 0}]),
    %% Top level sizer.
    _ = wxSizer:add(TopSizer, PrebBoxSizer,
                    [{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL},
                     {border, 10}]),
    _ = wxSizer:add(TopSizer, ButtonSizer,
                    [{proportion, 0},
                     {flag, ?wxALIGN_CENTER bor ?wxEXPAND bor
                          ?wxRIGHT bor ?wxLEFT bor ?wxBOTTOM},
                     {border, 10}]),
    wxWindow:setSizer(Dialog, TopSizer),
    _ = wxSizer:fit(TopSizer, Dialog),
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
loadPrefs(Options) ->
    %% Set initial file load path (used by the module addition dialog).
    ref_add(?FILE_PATH, "."),
    %% Disable save as (we don't have any results yet)
    wxMenuItem:enable(ref_lookup(?SAVEAS_MENU_ITEM), [{enable, false}]),
    ref_add(?ANALYSIS_RET, undef),
    %% Set files
    case lists:keyfind('files', 1, Options) of
        false -> continue;
        {'files', Files} ->
            AbsFiles = [filename:absname(F) || F <- Files],
            ErlFiles = [F || F <- AbsFiles, concuerror_util:is_erl_source(F)],
            addListItems(?MODULE_LIST, ErlFiles)
    end,
    %% Set include_dirs
    case lists:keyfind('include', 1, Options) of
        false -> ref_add(?PREF_INCLUDE, ?DEFAULT_INCLUDE);
        {'include', Include} -> ref_add(?PREF_INCLUDE, Include)
    end,
    %% Set defined macros
    case lists:keyfind('define', 1, Options) of
        false -> ref_add(?PREF_DEFINE, ?DEFAULT_DEFINE);
        {'define', Define} -> ref_add(?PREF_DEFINE, Define)
    end,
    %% Set preemption bound
    case lists:keyfind('preb', 1, Options) of
        false ->
            ref_add(?PREF_PREB_ENABLED, true),
            ref_add(?PREF_PREB_BOUND, ?DEFAULT_PREB);
        {'preb', inf} ->
            ref_add(?PREF_PREB_ENABLED, false),
            ref_add(?PREF_PREB_BOUND, ?DEFAULT_PREB);
        {'preb', Preb} ->
            ref_add(?PREF_PREB_ENABLED, true),
            ref_add(?PREF_PREB_BOUND, Preb)
    end.

%% Do nothing for now.
savePrefs() ->
    ok.

%%clearAll() ->
%%    clearMods(),
%%    clearFuns(),
%%    clearSrc(),
%%    clearLog(),
%%    clearProbs(),
%%    clearErrors(),
%%    clearIleaves().

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

%%clearLog() ->
%%    LogText = ref_lookup(?LOG_TEXT),
%%    wxTextCtrl:clear(LogText).

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

disableMenuItems() ->
    Opts = [{enable, false}],
    wxMenuItem:enable(ref_lookup(?ANALYZE_MENU_ITEM), Opts),
    wxMenuItem:enable(ref_lookup(?SAVEAS_MENU_ITEM), Opts).

enableMenuItems() ->
    wxMenuItem:enable(ref_lookup(?ANALYZE_MENU_ITEM)),
    wxMenuItem:enable(ref_lookup(?SAVEAS_MENU_ITEM)).

%% Export dialog
exportDialog(Parent) ->
    Caption = "Save to " ++ ?APP_STRING ++ " file",
    Wildcard = "Text files |*" ++ ?EXPORT_EXT,
    DefaultDir = ".",
    DefaultFile = "",
    Dialog = wxFileDialog:new(Parent, [{message, Caption},
                                       {defaultDir, DefaultDir},
                                       {defaultFile, DefaultFile},
                                       {wildCard, Wildcard},
                                       {style, ?wxFD_SAVE bor
                                            ?wxFD_OVERWRITE_PROMPT}]),
    wxFileDialog:setFilename(Dialog, ?EXPORT_FILE),
    case wxDialog:showModal(Dialog) of
        ?wxID_OK ->
            AnalysisRet = ref_lookup(?ANALYSIS_RET),
            Output = wxFileDialog:getPath(Dialog),
            concuerror_log:log(0, "Writing output to file ~s... ", [Output]),
            case concuerror:export(AnalysisRet, Output) of
                {'error', Msg} ->
                    concuerror_log:log(0, "~s\n", [file:format_error(Msg)]);
                ok ->
                    concuerror_log:log(0, "done\n")
            end;
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
            Funs = concuerror_util:funs(Module, string),
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
                    Line = concuerror_util:funLine(Path, Function, Arity),
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

%% Kill the analysis process.
stop() ->
    try
        ?RP_SCHED ! stop_analysis
%%        wxMenuItem:enable(ref_lookup(?STOP_MENU_ITEM), [{enable, false}]),
%%        StopButton = ref_lookup(?STOP),
%%        Parent = wxWindow:getParent(StopButton),
%%        StopGauge = wxGauge:new(Parent, ?wxID_ANY, 100,
%%                                [{style, ?wxGA_HORIZONTAL}]),
%%        ref_add(?STOP_GAUGE, StopGauge),
%%        AnalStopSizer = ref_lookup(?ANAL_STOP_SIZER),
%%        wxSizer:replace(AnalStopSizer, StopButton, StopGauge),
%%        wxWindow:destroy(StopButton),
%%        wxSizer:layout(AnalStopSizer),
%%        start_pulsing(StopGauge)
    catch
        error:badarg -> continue
    end.

%% XXX: hack (send event message to self)
send_event_msg_to_self(Id) ->
    Cmd = #wxCommand{type = command_listbox_selected},
    ?RP_GUI ! #wx{id = Id, event = Cmd},
    ok.

%% Set ListBox (Id) data (remove existing).
%%setListData(Id, DataList) ->
%%    List = ref_lookup(Id),
%%    setListData_aux(List, DataList, 0).

setListData_aux(_List, [], _N) ->
    ok;
setListData_aux(List, [Data|Rest], N) ->
    wxControlWithItems:setClientData(List, N, Data),
    setListData_aux(List, Rest, N + 1).

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
            Ticket = wxControlWithItems:getClientData(ErrorList, Id),
            setListItems(?ILEAVE_LIST,
                concuerror_ticket:details_to_strings(Ticket)),
            clearProbs(),
            Error = concuerror_ticket:get_error(Ticket),
            wxTextCtrl:appendText(ref_lookup(?ERROR_TEXT),
                concuerror_error:long(Error))
    end.

%% Validate user provided function arguments.
%% The arguments are first scanned and then parsed to ensure that they
%% represent valid erlang terms.
%% Returns {ok, ListOfArgs} if everything is valid, else 'error' is returned
%% and error messages are written to the log.
validateArgs(_I, [], Args, _ErrorId) ->
    {ok, lists:reverse(Args)};
validateArgs(I, [Ref|Refs], Args, ErrorId) ->
    String = wxTextCtrl:getValue(Ref) ++ ".",
    case erl_scan:string(String) of
        {ok, T, _} ->
            case erl_parse:parse_term(T) of
                {ok, Arg} -> validateArgs(I + 1, Refs, [Arg|Args], ErrorId);
                {error, {_, _, Info}} ->
                    wxTextCtrl:appendText(ref_lookup(?ERROR_TEXT),
                                          io_lib:format("Arg ~p - ~s~n",
                                                        [I + 1, Info])),
                    error
            end;
        {error, {_, _, Info}, _} ->
            wxTextCtrl:appendText(ref_lookup(?ERROR_TEXT), Info ++ "\n"),
            error
    end.



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
            analyze_proc(),
            loop();
        #wx{id = ?CLEAR, event = #wxCommand{type = command_button_clicked}} ->
            clearMods(),
            clearFuns(),
            clearSrc(),
            loop();
        #wx{id = ?REMOVE, event = #wxCommand{type = command_button_clicked}} ->
            remove(),
            loop();
        #wx{id = ?STOP, event = #wxCommand{type = command_button_clicked}} ->
            stop(),
            loop();
        #wx{id = ?REFRESH, event = #wxCommand{type = command_button_clicked}} ->
            refresh(),
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
            analyze_proc(),
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
            analyze_proc(),
            loop();
        #wx{id = ?CLEAR, event = #wxCommand{type = command_menu_selected}} ->
            clearMods(),
            clearFuns(),
            clearSrc(),
            loop();
        #wx{id = ?EXIT, event = #wxCommand{type = command_menu_selected}} ->
            ok;
        #wx{id = ?SAVEAS, event = #wxCommand{type = command_menu_selected}} ->
            Frame = ref_lookup(?FRAME),
            exportDialog(Frame),
            loop();
        #wx{id = ?PREFS, event = #wxCommand{type = command_menu_selected}} ->
            Frame = ref_lookup(?FRAME),
            prefsDialog(Frame),
            loop();
        #wx{id = ?REFRESH, event = #wxCommand{type = command_menu_selected}} ->
            refresh(),
            send_event_msg_to_self(?FUNCTION_LIST),
            loop();
        #wx{id = ?REMOVE, event = #wxCommand{type = command_menu_selected}} ->
            remove(),
            loop();
        #wx{id = ?STOP, event = #wxCommand{type = command_menu_selected}} ->
            stop(),
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
        %% -------------------- Misc handlers -------------------- %%
        %% Every time a splitter sash changes its position, refresh the whole
        %% window to avoid annoying artifacts from the previous position of the
        %% sash.
        #wx{event = #wxSplitter{type = command_splitter_sash_pos_changed}} ->
            Frame = ref_lookup(?FRAME),
            wxWindow:refresh(Frame),
            loop();
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
