-module(gui).
-compile(export_all).

-include_lib("wx/include/wx.hrl").
-include("gui.hrl").


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
    
    setupPanel(Frame),
    wxWindow:fit(Frame),
    wxFrame:center(Frame),

    Frame.

setupPanel(Parent) ->
    Panel = wxPanel:new(Parent),
    
    %% --------------------------------- Left Column -------------------------------------- %%

    ModuleList = wxListBox:new(Panel,
			       ?MODULE_LIST,
			       [{size, {300, 200}}]),
    refServer:add({?MODULE_LIST, ModuleList}),

    FunctionList = wxListBox:new(Panel,
     				 ?FUNCTION_LIST,
     				 [{size, {300, 200}}, {style, ?wxLB_SORT}]),
    refServer:add({?FUNCTION_LIST, FunctionList}),

    AddButton = wxButton:new(Panel, ?ADD, [{label, "Add..."}]),
    RemButton = wxButton:new(Panel, ?REMOVE),
    ClearButton = wxButton:new(Panel, ?CLEAR),
    AnalyzeButton = wxButton:new(Panel, ?ANALYZE, [{label, "Analyze"}]),

    AddRemSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(AddRemSizer,
		AddButton,
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),
    wxSizer:add(AddRemSizer,
		RemButton,
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),
    wxSizer:add(AddRemSizer,
		ClearButton,
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),

    LeftColumnSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(LeftColumnSizer,
		wxStaticText:new(Panel, ?wxID_ANY, "Modules"),
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),
    wxSizer:add(LeftColumnSizer,
		ModuleList,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxSizer:add(LeftColumnSizer,
		AddRemSizer,
		[{proportion, 0}, {flag, ?wxALL bor ?wxALIGN_CENTER}, {border, 10}]),
    wxSizer:add(LeftColumnSizer,
		wxStaticText:new(Panel, ?wxID_ANY, "Functions"),
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),
    wxSizer:add(LeftColumnSizer,
		FunctionList,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxSizer:add(LeftColumnSizer,
		AnalyzeButton,
		[{proportion, 0}, {flag, ?wxALL bor ?wxALIGN_CENTER}, {border, 0}]),
    
    
    %% -------------------------------- Right Column -------------------------------------- %%

    Notebook = wxNotebook:new(Panel, ?NOTEBOOK, [{size, {500, 400}}]),
    refServer:add({?NOTEBOOK, Notebook}),

    LogPanel = wxPanel:new(Notebook),
    GraphPanel = wxPanel:new(Notebook),

    LogText = wxTextCtrl:new(LogPanel,
     			     ?LOG_TEXT,
     			     [{size, {400, 400}},
     			      {style, ?wxTE_MULTILINE bor ?wxTE_READONLY}]),
    refServer:add({?LOG_TEXT, LogText}),
    
    ScrGraph = wxScrolledWindow:new(GraphPanel),
    refServer:add({?SCR_GRAPH, ScrGraph}),

    LogPanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(LogPanelSizer,
		LogText,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxWindow:setSizer(LogPanel, LogPanelSizer),

    GraphPanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(GraphPanelSizer,
		ScrGraph,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxWindow:setSizer(GraphPanel, GraphPanelSizer),

    wxNotebook:addPage(Notebook, LogPanel, "Log", [{bSelect, true}]),
    wxNotebook:addPage(Notebook, GraphPanel, "Graph", [{bSelect, false}]),

    RightColumnSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(RightColumnSizer,
		Notebook,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),


    %% ------------------------ Two-column top level layout ------------------------------- %%

    TopSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(TopSizer,
     		LeftColumnSizer,
		[{proportion, 0}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    wxSizer:add(TopSizer,
     		RightColumnSizer,
		[{proportion, 1}, {flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),

    wxWindow:setSizer(Panel, TopSizer),
    wxSizer:fit(TopSizer, Panel),
    wxSizer:setSizeHints(TopSizer, Parent),

    Panel.
    

%% Menu constructor according to specification (gui.hrl)
setupMenu(MenuBar, [{Title, Items} | Rest]) ->
    setupMenu(MenuBar, [{Title, Items, []} | Rest]);

setupMenu(_MenuBar, []) ->
    ok;
setupMenu(MenuBar, [{Title, Items, Options} | Rest]) ->
    Menu = wxMenu:new(Options),
    setupMenuItems(Menu, Items),
    wxMenuBar:append(MenuBar, Menu, Title),
    setupMenu(MenuBar, Rest).

setupMenuItems(_Menu, []) ->
    ok;
setupMenuItems(Menu, [Options | Rest]) ->
    Item = wxMenuItem:new(Options),
    wxMenu:append(Menu, Item),
    setupMenuItems(Menu, Rest).

%% Module-adding dialog
addDialog(Parent) ->
    Caption = "Open erlang module",
    Wildcard = "Erlang source (*.erl)|*.erl| All files (.*)|*",
    DefaultDir = ".",
    DefaultFile = "",
    Dialog = wxFileDialog:new(Parent,
			      [{message, Caption},
			       {defaultDir, DefaultDir},
			       {defaultFile, DefaultFile},
			       {wildCard, Wildcard},
			       {style, ?wxFD_OPEN bor ?wxFD_FILE_MUST_EXIST bor ?wxFD_MULTIPLE}]),
    case wxDialog:showModal(Dialog) of
	?wxID_OK ->
	    addListItems(?MODULE_LIST, wxFileDialog:getPaths(Dialog));
	_Other -> 
	    continue
    end,
    wxDialog:destroy(Dialog).

%% Add items to ListBox (Id)
addListItems(Id, Items) ->
    List = refServer:lookup(Id),
    MyCount = wxControlWithItems:getCount(List),
    if
	MyCount =:= 0 ->
	    Flag = true;
	true ->
	    Flag = false
    end,
    Count = wxListBox:getCount(List),
    wxListBox:insertItems(List, Items, Count),
    case Flag of
	true ->
	    wxControlWithItems:setSelection(List, 0),
	    %% XXX: hack (send event message to self)
	    self() ! #wx{id = Id, event = #wxCommand{type = command_listbox_selected}};
	false ->
	    continue
    end.

%% Set ListBox (Id) items (remove existing)
setListItems(Id, Items) ->
    if
	Items =/= [], Items =/= [[]] ->
	    List = refServer:lookup(Id),
	    wxListBox:set(List, Items),
	    wxControlWithItems:setSelection(List, 0),
	    %% XXX: hack (send event message to self)
	    self() ! #wx{id = Id, event = #wxCommand{type = command_listbox_selected}};
	true ->
	    continue
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
    getStrings(Ref, N + 1, Count, [String | Strings]).

%% Instrument all modules in ModuleList
instrumentAll(Id) ->
    ModuleList = refServer:lookup(Id),
    instrumentList(getStrings(ModuleList)).

instrumentList([]) ->
    ok;
instrumentList([String | Strings]) ->
    instrument:c(String),
    instrumentList(Strings).

getModule() ->
    ModuleList = refServer:lookup(?MODULE_LIST),
    Path = wxControlWithItems:getStringSelection(ModuleList),
    case re:run(Path,
		".*/(?<MODULE>.*?)\.erl\$",
		[dotall, {capture, ['MODULE'], list}]) of
	{match, [Module]} ->
	    list_to_atom(Module);
	nomatch -> 
	    ''
    end.

getFunction() ->
    FunctionList = refServer:lookup(?FUNCTION_LIST),
    Expr = wxControlWithItems:getStringSelection(FunctionList),
    case re:run(Expr,
		"(?<FUN>.*)/(?<ARITY>.*)\$",
		[dotall, {capture, ['FUN', 'ARITY'], list}]) of
	{match, [Fun, Arity]} ->
	    {list_to_atom(Fun), list_to_integer(Arity)};
	nomatch -> 
	    {'', 0}
    end.

%% TODO
argDialog(Parent, Argnum) ->
    Dialog = wxDialog:new(Parent, ?wxID_ANY, "Function arguments"),
    TopSizer = wxBoxSizer:new(?wxVERTICAL),
    addArgs(Dialog, TopSizer, Argnum),

    ButtonSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(ButtonSizer,
		wxButton:new(Dialog, ?wxID_OK),
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),
    wxSizer:add(ButtonSizer,
		wxButton:new(Dialog, ?wxID_CANCEL),
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),

    wxSizer:add(TopSizer,
		ButtonSizer,
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),

    wxWindow:setSizer(Dialog, TopSizer),
    wxSizer:fit(TopSizer, Dialog),

    %% TODO: Don't forget to destroy!!!
    case wxDialog:showModal(Dialog) of
	?wxID_OK ->
	    ok;
	_Other ->
	    continue
    end.

addArgs(_Parent, _Sizer, 0) ->
    ok;
addArgs(Parent, Sizer, Count) ->
    wxSizer:add(Sizer,
		wxTextCtrl:new(Parent, ?wxID_ANY),
		[{proportion, 0}, {flag, ?wxALL}, {border, 10}]),
    addArgs(Parent, Sizer, Count - 1).


%% Main event loop
loop() ->
    receive
	
	%% ------------------------------- Button handlers ------------------------------------- %%

	#wx{id = ?ADD, event = #wxCommand{type = command_button_clicked}} ->
	    Frame = refServer:lookup(?FRAME),
	    addDialog(Frame),
	    loop();

	#wx{id = ?REMOVE, event = #wxCommand{type = command_button_clicked}} ->
	    ModuleList = refServer:lookup(?MODULE_LIST),
	    Selection = wxListBox:getSelection(ModuleList),
	    FunctionList = refServer:lookup(?FUNCTION_LIST),
	    if
		Selection =:= ?wxNOT_FOUND ->
		    continue;
		true ->
		    wxControlWithItems:delete(ModuleList, Selection),
		    Count = wxControlWithItems:getCount(ModuleList),
		    if
			Count =:= 0 ->
			    wxControlWithItems:clear(FunctionList);
			Selection =:= Count ->
			    wxControlWithItems:setSelection(ModuleList, Selection - 1);
			true ->
			    wxControlWithItems:setSelection(ModuleList, Selection)
		    end
	    end,
	    loop();

	#wx{id = ?CLEAR, event = #wxCommand{type = command_button_clicked}} ->
	    ModuleList = refServer:lookup(?MODULE_LIST),
	    FunctionList = refServer:lookup(?FUNCTION_LIST),
	    wxControlWithItems:clear(ModuleList),
	    wxControlWithItems:clear(FunctionList),
	    loop();

	#wx{id = ?ANALYZE, event = #wxCommand{type = command_button_clicked}} ->
	    Module = getModule(),
	    {Function, Arity} = getFunction(),
	    Self = self(),
	    if
	     	Module =/= '', Function =/= '' ->
		    LogText = refServer:lookup(?LOG_TEXT),
		    wxTextCtrl:clear(LogText),
		    instrumentAll(?MODULE_LIST),
		    case Arity of
			0 ->
			    spawn(fun() -> driver:drive(
					     fun() -> Module:Function() end,
					     Self)
                                  end);
			Count ->
			    Frame = refServer:lookup(?FRAME),
			    case argDialog(Frame, Count) of
				{?wxID_OK, Args} ->
				    spawn(fun() ->
						  driver:drive(
						    fun() -> apply(Module, Function, Args) end,
						    Self
						   ) end);
				_Other ->
				    continue
			    end
		    end;
		true ->
		    continue
	    end,
	    loop();


	%% ------------------------------ Listbox handlers ------------------------------------- %%

	#wx{id = ?MODULE_LIST, event = #wxCommand{type = command_listbox_selected}} ->
	    ModuleList = refServer:lookup(?MODULE_LIST),
	    case wxListBox:getSelection(ModuleList) of
		?wxNOT_FOUND ->
		    continue;
		_Other ->
		    Module = wxListBox:getStringSelection(ModuleList),
		    Funs = funs:stringList(Module),
		    setListItems(?FUNCTION_LIST, Funs)
	    end,
	    loop();

	#wx{id = ?FUNCTION_LIST, event = #wxCommand{type = command_listbox_selected}} ->
	    loop();
	

	%% -------------------------------- Misc handlers -------------------------------------- %%

	#wx{event = #wxClose{type = close_window}} ->
	    close;

	#gui{type = log, msg = String} ->
	    LogText = refServer:lookup(?LOG_TEXT),
	    wxTextCtrl:appendText(LogText, String),
	    loop();

	%% TODO
	#gui{type = dot, msg = ok} ->
	    os:cmd("dot -Tpng < schedule.dot > schedule.png"),
	    Image= wxBitmap:new("schedule.png", [{type, ?wxBITMAP_TYPE_PNG}]),
	    {W, H} = {wxBitmap:getWidth(Image), wxBitmap:getHeight(Image)},
	    %%wxScrolledWindow:doPrepareDC(ScrGraph, Dc),
	    %%wxDC:drawBitmap(Dc, Image, {0, 0}, [{useMask, false}]),
	    %%wxClientDC:destroy(Dc),
	    ScrGraph = refServer:lookup(?SCR_GRAPH),
	    wxScrolledWindow:setScrollbars(ScrGraph, 20, 20, W div 20, H div 20),
	    
	    case refServer:lookup(?STATIC_BMP) of
		false ->
		    StaticBmp = wxStaticBitmap:new(ScrGraph, ?wxID_ANY, Image),
		    refServer:add({?STATIC_BMP, StaticBmp});
		Result ->
		    wxStaticBitmap:setBitmap(Result, Image)
	    end,
	    loop();

	%% -------------------------------- Menu handlers -------------------------------------- %%

	#wx{id = ?EXIT, event = #wxCommand{type = command_menu_selected}} ->
	    close;

	#wx{id = ?ABOUT, event = #wxCommand{type = command_menu_selected}} ->
	    Caption = "About PULSE",
	    Frame = refServer:lookup(?FRAME),
	    Dialog = wxMessageDialog:new(Frame,
					 ?INFO_MSG,
					 [{style, ?wxOK}, {caption, Caption}]),
	    wxDialog:showModal(Dialog),
	    wxWindow:destroy(Dialog),
	    loop();

	#wx{id = ?ADD, event = #wxCommand{type = command_menu_selected}} ->
	    Frame = refServer:lookup(?FRAME),
	    addDialog(Frame),
	    loop();


	%% ---------------------------------- Catchall ---------------------------------------- %%

	Other ->
	    io:format("loop unimplemented: ~p~n", [Other]),
	    loop()
    end.
