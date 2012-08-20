%%%----------------------------------------------------------------------
%%% Copyright (c) 2012, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Ilias Tsitsimpis <iliastsi@hotmail.com>
%%% Description : Command Line Interface
%%%----------------------------------------------------------------------

-module(concuerror).

%% UI exports.
-export([gui/0, cli/0, analyze/1, show/1, stop/0]).
%% Log server callback exports.
-export([init/1, terminate/2, handle_event/2]).

-export_type([options/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Debug
%%%----------------------------------------------------------------------

%%-define(TTY, true).
-ifdef(TTY).
-define(tty(), ok).
-else.
-define(tty(), error_logger:tty(false)).
-endif.

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

%% Log event handler internal state.
%% The state (if we want have progress bar) contains
%% the current preemption number,
%% the progress in per cent,
%% the number of interleaving contained in this preemption number,
%% the number of errors we have found so far.
-type state() :: {non_neg_integer(), non_neg_integer(),
                  non_neg_integer(), non_neg_integer()}
                 | 'no_progress'.

%% Command line options
-type options() ::
    [ {'target',  sched:analysis_target()}
    | {'files',   [file()]}
    | {'snapshot',  file()}
    | {'include', [file()]}
    | {'no_progress'}
    | {'preb',    sched:bound()}
    | {'number', [pos_integer() | {pos_integer(), pos_integer()|'end'}]}
    | {'details'}
    | {'all'}
    ].


%%%----------------------------------------------------------------------
%%% UI functions
%%%----------------------------------------------------------------------

%% @spec stop() -> ok
%% @doc: Stop the Concuerror analysis
-spec stop() -> ok.
stop() ->
    %% XXX: Erlang nodes is erroneous with Concuerror right
    %% now and there is times this approach may crash.
    %% Get the hostname
    Temp1 = atom_to_list(node()),
    Host = lists:dropwhile(fun(E) -> E /= $@ end, Temp1),
    %% Set Concuerror Node
    Node = list_to_atom("Concuerror" ++ Host),
    %% Connect to node
    case net_adm:ping(Node) of
        pong ->
            %% Stop analysis
            spawn(Node, fun() -> ?RP_SCHED ! stop_analysis end);
        _ ->
            %% Well some times we could not connect with the
            %% first try so for now just repeat
            stop()
    end,
    ok.

%% @spec gui() -> 'true'
%% @doc: Start the CED GUI.
-spec gui() -> 'true'.
gui() ->
    %% Disable error logging messages.
    ?tty(),
    gui:start().

%% @spec cli() -> 'true'
%% @doc: Parse the command line arguments and start Concuerror.
-spec cli() -> 'true'.
cli() ->
    %% Disable error logging messages.
    ?tty(),
    %% First get the command line options
    Args1 = init:get_arguments(),
    %% And keep only this referring to Concuerror
    %% Hack: to do this add the flag `-concuerror_options'
    %% which separates erlang from concuerror options
    Pred = fun(P) -> {concuerror_options, []} /= P end,
    [_ | Args2] = lists:dropwhile(Pred, Args1),
    %% Firstly parse the command option
    case init:get_plain_arguments() of
        ["analyze"] -> action_analyze(Args2, []);
        ["show"]    -> action_show(Args2, []);
        ["gui"]     -> action_gui(Args2);
        ["help"]    -> help();
        [Action] ->
            io:format("~s: unrecognised command: ~s\n", [?APP_STRING, Action]),
            init:stop(1);
        _ -> help()
    end,
    true.

%% We don't allow any options for action `gui'
action_gui([]) -> gui();
action_gui([Op|_]) ->
    io:format("~s: unrecognised flag: ~s\n", [?APP_STRING, Op]),
    init:stop(1).

%% Parse options for analyze command and call `analyze/1'
action_analyze([{Opt, [Module,Func|Params]} | Args], Options)
        when (Opt =:= 't') orelse (Opt =:= '-target') ->
    %% Found --target option
    AtomModule = erlang:list_to_atom(Module),
    AtomFunc   = erlang:list_to_atom(Func),
    AtomParams = validateParams(Params, []),
    Target = {AtomModule, AtomFunc, AtomParams},
    NewOptions = lists:keystore(target, 1, Options, {target, Target}),
    action_analyze(Args, NewOptions);
action_analyze([{Opt, _} | _Args], _Options)
        when (Opt =:= 't') orelse (Opt =:= '-target') ->
    %% Found --target option with wrong parameters
    io:format("~s: wrong number of arguments for option -~s\n",
        [?APP_STRING, Opt]),
    init:stop(1);
action_analyze([{Opt, []} | _Args], _Options)
        when (Opt =:= 'f') orelse (Opt =:= '-files') ->
    %% Found --files options without parameters
    io:format("~s: wrong number of arguments for option -~s\n",
        [?APP_STRING, Opt]),
    init:stop(1);
action_analyze([{Opt, Files} | Args], Options)
        when (Opt =:= 'f') orelse (Opt =:= '-files') ->
    %% Found --files option
    AbsFiles = lists:map(fun filename:absname/1, Files),
    NewOptions = keyAppend(files, 1, Options, AbsFiles),
    action_analyze(Args, NewOptions);
action_analyze([{Opt, [File]} | Args], Options)
        when (Opt =:= 'o') orelse (Opt =:= '-output') ->
    %% Found --output option
    NewOptions = lists:keystore(snapshot, 1, Options, {snapshot, File}),
    action_analyze(Args, NewOptions);
action_analyze([{Opt, _Files} | _Args], _Options)
        when (Opt =:= 'o') orelse (Opt =:= '-output') ->
    %% Found --output option with wrong parameters
    io:format("~s: wrong number of arguments for option -~s\n",
        [?APP_STRING, Opt]),
    init:stop(1);
action_analyze([{Opt, [Preb]} | Args], Options)
        when (Opt =:= 'p') orelse (Opt =:= '-preb') ->
    %% Found --preb option
    NewPreb =
        case string:to_integer(Preb) of
            {P, []} when P>=0 -> P;
            _ when (Preb=:="inf") orelse (Preb=:="off") -> inf;
            _ ->
                io:format("~s: wrong type of argument for option -~s\n",
                    [?APP_STRING, Opt]),
                init:stop(1)
        end,
    NewOptions = lists:keystore(preb, 1, Options, {preb, NewPreb}),
    action_analyze(Args, NewOptions);
action_analyze([{Opt, _Prebs} | _Args], _Options)
        when (Opt =:= 'p') orelse (Opt =:= '-preb') ->
    %% Found --preb option with wrong parameters
    io:format("~s: wrong number of arguments for option -~s\n",
        [?APP_STRING, Opt]),
    init:stop(1);
action_analyze([{'I', Includes} | Args], Options) ->
    %% Found -I option
    NewOptions = keyAppend(include, 1, Options, Includes),
    action_analyze(Args, NewOptions);
action_analyze([{'-no_progress', []} | Args], Options) ->
    %% Found --no_progress option
    NewOptions = lists:keystore(no_progress, 1, Options, {no_progress}),
    action_analyze(Args, NewOptions);
action_analyze([{'-no_progress', _} | _Args], _Options) ->
    %% Found --no_progress option with wrong parameters
    io:format("~s: wrong number of arguments for option --no_progress\n",
        [?APP_STRING]),
    init:stop(1);
action_analyze([], Options) ->
    analyze(Options);
action_analyze([Arg | _Args], _Options) ->
    io:format("~s: unrecognised concuerror flag: ~p\n", [?APP_STRING, Arg]),
    init:stop(1).

%% Validate user provided function parameters.
validateParams([], Params) ->
    lists:reverse(Params);
validateParams([String|Strings], Params) ->
    case erl_scan:string(String ++ ".") of
        {ok, T, _} ->
            case erl_parse:parse_term(T) of
                {ok, Param} -> validateParams(Strings, [Param|Params]);
                {error, {_, _, Info}} ->
                    io:format("~s: arg ~s - ~s\n",
                        [?APP_STRING, String, Info]),
                    init:stop(1)
            end;
        {error, {_, _, Info}, _} ->
            io:format("~s: info ~s\n", [?APP_STRING, Info]),
            init:stop(1)
    end.

%% Parse options for show command and call `show/1'
action_show([{'-snapshot', [File]} | Args], Options) ->
    %% Found --snapshot option
    NewOptions = lists:keystore(snapshot, 1, Options, {snapshot, File}),
    action_show(Args, NewOptions);
action_show([{'-snapshot', _Files} | _Args], _Options) ->
    %% Found --snapshot with wrong paramemters
    io:format("~s: wrong number of arguments for option --snapshot\n",
        [?APP_STRING]),
    init:stop(1);
action_show([{'n', Numbers} | Args], Options) ->
    %% Found -n option
    Fun = fun(Nr) ->
            case string:to_integer(Nr) of
                {N, []} when N>0 -> N;
                {N1, [$.,$.|N2]} when N1>0 ->
                    case string:to_integer(N2) of
                        {N3, []} when (N3>0) andalso (N1<N3) -> {N1, N3};
                        _ when (N2=:="end") -> {N1, 'end'};
                        _ ->
                            io:format("~s: wrong type of number ~s\n",
                                [?APP_STRING, N2]),
                            init:stop(1)
                    end;
                _ ->
                    io:format("~s: wrong type of number ~s\n",
                        [?APP_STRING, Nr]),
                    init:stop(1)
            end
          end,
    NewNumbers = lists:map(Fun, Numbers),
    NewOptions = keyAppend(number, 1, Options, NewNumbers),
    action_show(Args, NewOptions);
action_show([{'-all', []} | Args], Options) ->
    %% Found --all option
    NewOptions = lists:keystore(all, 1, Options, {all}),
    action_show(Args, NewOptions);
action_show([{'-all', _Param} | _Args], _Options) ->
    %% Found --all option with wrong parameters
    io:format("~s: wrong number of arguments for option --all\n",
        [?APP_STRING]),
    init:stop(1);
action_show([{Opt, []} | Args], Options)
        when (Opt =:= 'd') orelse (Opt =:= '-details') ->
    %% Found --details options
    NewOptions = lists:keystore(details, 1, Options, {details}),
    action_show(Args, NewOptions);
action_show([{Opt, _Params} | _Args], _Options)
        when (Opt =:= 'd') orelse (Opt =:= '-details') ->
    %% Found --details option with wrong parameters
    io:format("~s: wrong number of arguments for option --details\n",
        [?APP_STRING]),
    init:stop(1);
action_show([], Options) ->
    show(Options);
action_show([Arg | _Args], _Options) ->
    io:format("~s: unrecognised concuerror flag: ~p\n", [?APP_STRING, Arg]),
    init:stop(1).


keyAppend(Key, Pos, TupleList, Value) ->
    case lists:keytake(Key, Pos, TupleList) of
        {value, {Key, PrevValue}, TupleList2} ->
            [{Key, Value ++ PrevValue} | TupleList2];
        false ->
            [{Key, Value} | TupleList]
    end.


help() ->
    io:format(
     "usage: concuerror <command> [<args>]\n"
     "A Systematic Testing Framework for detecting\n"
     "Concurrency Errors in Erlang Programs\n"
     "\n"
     "Commands:\n"
     "  analyze         Analyze a specific target\n"
     "  show            Show the results of an analysis\n"
     "  gui             Run concuerror with graphics\n"
     "  help            Show this help message\n"
     "\n"
     "Analyze options:\n"
     "  -t|--target module function [args]\n"
     "                          Specify the function to execute\n"
     "  -f|--files  modules     Specify the files (modules) to instrument\n"
     "  -o|--output file        Specify the output file (default results.ced)\n"
     "  -p|--preb   number|inf  Set preemption bound (default is 2)\n"
     "  -I          include_dir Pass the include_dir to concuerror\n"
     "  --no-progress           Disable progress bar\n"
     "\n"
     "Show options:\n"
     "  --snapshot   file       Specify input (snapshot) file\n"
     "  -n           from..to   Specify which errors we want (default -all)\n"
     "  --all                   Show all errors\n"
     "  -d|--details            Show details about each error\n"
     "\n"
     "Examples:\n"
     "  concuerror analyze --target foo bar arg1 arg2 "
            "--files \"temp/foo.erl\" -o out.ced\n"
     "  concuerror show --snapshot out.ced --all\n"
     "  concuerror show --snapshot out.ced -n 1 4..end --details\n\n").


%%%----------------------------------------------------------------------
%%% Analyze Commnad
%%%----------------------------------------------------------------------

%% @spec analyze(options()) -> 'true'
%% @doc: Run Concuerror analysis with the given options.
-spec analyze(options()) -> 'true'.
analyze(Options) ->
    %% Disable error logging messages.
    ?tty(),
    %% Get target
    Target =
        case lists:keyfind(target, 1, Options) of
            {target, T} -> T;
            false ->
                io:format("~s: no target specified\n", [?APP_STRING]),
                init:stop(1)
        end,
    %% Get input files
    Files =
        case lists:keyfind(files, 1, Options) of
            {files, F} -> F;
            false ->
                io:format("~s: no input files specified\n", [?APP_STRING]),
                init:stop(1)
        end,
    %% Set output file
    Output =
        case lists:keyfind(snapshot, 1, Options) of
            {snapshot, O} -> O;
            false -> "results.ced"
        end,
    %% Set include dirs
    %% XXX: We have to actually use it
    Include =
        case lists:keyfind(include, 1, Options) of
            {include, I} -> I;
            false -> []
        end,
    %% Set preemption bound
    Preb =
        case lists:keyfind(preb, 1, Options) of
            {preb, P} -> P;
            false -> 2
        end,
    %% Create analysis_options
    AnalysisOptions = [{preb, Preb}, {include, Include}],
    %% Start the log manager and attach the event handler below.
    _ = log:start(),
    _ = log:attach(?MODULE, Options),
    %% Start the analysis
    AnalysisRet = sched:analyze(Target, Files, AnalysisOptions),
    %% Save result to a snapshot
    Selection = snapshot:selection(1, 1),
    snapshot:export(AnalysisRet, Files, Selection, Output),
    %% Stop event handler
    log:stop(),
    true.


%%%----------------------------------------------------------------------
%%% Show Commnad
%%%----------------------------------------------------------------------

%% @spec show(options()) -> 'true'
%% @doc: Examine Concuerror results with the given options.
-spec show(options()) -> 'true'.
show(Options) ->
    %% Disable error logging messages.
    ?tty(),
    %% Get snapshot file
    File =
        case lists:keyfind(snapshot, 1, Options) of
            {snapshot, S} -> S;
            false ->
                io:format("~s: no snapshot file specified\n", [?APP_STRING]),
                init:stop(1)
        end,
    %% Get index of errors to examine
    Indexes1 =
        case lists:keyfind(number, 1, Options) of
            {number, N} -> N;
            false -> all
        end,
    Indexes2 =
        case lists:keyfind(all, 1, Options) of
            {all} -> all;
            false -> Indexes1
        end,
    %% Get details option
    Details =
        case lists:keyfind(details, 1, Options) of
            {details} -> true;
            false -> false
        end,
    %% Start the log manager and attach the event handler below.
    _ = log:start(),
    _ = log:attach(?MODULE, [{no_progress}]),
    %% Load snapshot
    snapshot:cleanup(),
    case snapshot:import(File) of
        ok -> continue;
        Snapshot ->
            Modules = snapshot:get_modules(Snapshot),
            Files = lists:map(fun filename:absname/1, Modules),
            AnalysisRet = snapshot:get_analysis(Snapshot),
            %% Instrument and load the files
            %% Note: No error checking here.
            {ok, Bin} = instr:instrument_and_compile(Files),
            ok = instr:load(Bin),
            log:log("\n"),
            showAux(AnalysisRet, Indexes2, Details),
            instr:delete_and_purge(Files)
    end,
    snapshot:cleanup(),
    %% Stop event handler
    log:stop(),
    true.

showAux({error, analysis, {_Target, _RunCount}, Tickets}, Indexes, Details) ->
    TickLen = length(Tickets),
    NewIndexes = uIndex(Indexes, TickLen),
    KeyTickets = lists:zip(lists:seq(1, TickLen), Tickets),
    NewTickets = selectKeys(NewIndexes, KeyTickets, []),
    lists:foreach(fun(T) -> showDetails(Details, T) end, NewTickets);
showAux({error, instr, {_Target, _RunCount}}, _Indexes, _Details) ->
    log:log("Instrumentation error.");
showAux({ok, _RunCount}, _Indexes, _Details) ->
    log:log("No errors found.\n").

%% Take the indexes from command line and create a sorted list
uIndex(all, TickLen) ->
    lists:seq(1, TickLen);
uIndex(Indexes, TickLen) ->
    Fun = fun(I) ->
            case I of
                {From, 'end'} -> lists:seq(From, TickLen);
                {From, To}  -> lists:seq(From, To);
                Number -> Number
            end
          end,
    Indexes1 = lists:map(Fun, Indexes),
    Indexes2 = lists:flatten(Indexes1),
    lists:usort(Indexes2).

%% Keep only this elements whose keys are in Keys list
%% Both lists are sorted by keys
selectKeys(_Indexes, [], Acc) ->
    lists:reverse(Acc);
selectKeys([], _Tickets, Acc) ->
    lists:reverse(Acc);
selectKeys([I | Is], [{I,_T}=Tick | Tickets], Acc) ->
    selectKeys(Is, Tickets, [Tick | Acc]);
selectKeys(Indexes, [_ | Tickets], Acc) ->
    selectKeys(Indexes, Tickets, Acc).

%% Show details about each ticket
showDetails(false, {I, Ticket}) ->
    Error = ticket:get_error(Ticket),
    ErrorItem = io_lib:format("~p\t~s: ~s\n",
        [I, error:type(Error), error:short(Error)]),
    log:log(ErrorItem);
showDetails(true, {_I, T}=Ticket) ->
    showDetails(false, Ticket),
    %% Disable log event handler while replaying.
    _ = log:detach(?MODULE, []),
    Details = sched:replay(T),
    _ = log:attach(?MODULE, [{no_progress}]),
    lists:foreach(fun(Detail) ->
                D1 = proc_action:to_string(Detail),
                D2 = io_lib:format("  ~s\n", [D1]),
                log:log(D2) end,
        Details),
    log:log("\n\n").



%%%----------------------------------------------------------------------
%%% Log event handler callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {'ok', state()}.

%% @doc: Initialize the event handler.
init(Options) ->
    case lists:keyfind(no_progress, 1, Options) of
        {no_progress} -> {ok, no_progress};
        false -> {ok, {0,0,1,0}}
    end.

-spec terminate(term(), state()) -> 'ok'.
terminate(_Reason, _State) -> ok.

-spec handle_event(log:event(), state()) -> {'ok', state()}.
handle_event({msg, String}, State) ->
    io:format("~s", [String]),
    {ok, State};
handle_event({error, _Ticket}, {Bound,Progress,Total,Errors}) ->
    progress_bar(Progress, Errors+1),
    {ok, {Bound,Progress,Total,Errors+1}};
handle_event({error, _Ticket}, no_progress) ->
    {ok, no_progress};
handle_event({progress_log, Remain}, {Bound,Progress,Total,Errors}=State) ->
    NewProgress = erlang:trunc(100 - Remain*100/Total),
    case NewProgress > Progress of
        true ->
            progress_bar(NewProgress, Errors),
            {ok, {Bound,NewProgress,Total,Errors}};
        false ->
            {ok, State}
    end;
handle_event({progress_log, _Remain}, no_progress) ->
    {ok, no_progress};
handle_event({progress_swap, NewTotal}, {Bound,_Progress,_Total,Errors}) ->
    %% Clear last two lines from screen
    io:format("\r\033[K\033[1A\033[K"),
    NewBound = Bound+1,
    io:format("Preemption: ~p\n", [NewBound]),
    {ok, {NewBound,0,NewTotal,Errors}};
handle_event({progress_swap, _NewTotal}, no_progress) ->
    {ok, no_progress}.

progress_bar(PerCent, Errors) ->
    Bar = string:chars($=, PerCent div 2, ">"),
    StrPerCent = io_lib:format("~p", [PerCent]),
    io:format("\r\033[K ~3s% [~.51s]  ~p errors found",
        [StrPerCent, Bar, Errors]).
