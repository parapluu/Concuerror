%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
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

%% Log event handler internal state.
-type state() :: [].

%% Command line options
-type options() ::
    [ {'target',  sched:analysis_target()}
    | {'files',   [file()]}
    | {'output',  file()}
    | {'include', [file()]}
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
    gui:start().

%% @spec cli() -> 'true'
%% @doc: Parse the command line arguments and start Concuerror.
-spec cli() -> 'true'.
cli() ->
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
            halt(1);
        [] -> help()
    end,
    true.

%% We don't allow any options for action `gui'
action_gui([]) -> gui();
action_gui([Op|_]) ->
    io:format("~s: unrecognised flag: ~s\n", [?APP_STRING, Op]),
    halt(1).

%% Parse options for analyze command and call `analyze/1'
action_analyze([{Opt, [Module,Func|Params]} | Args], Options)
        when (Opt =:= 't') orelse (Opt =:= '-target') ->
    %% Found --target option
    AtomModule = erlang:list_to_atom(Module),
    AtomFunc   = erlang:list_to_atom(Func),
    AtomParams = lists:map(fun erlang:list_to_atom/1, Params),
    Target = {AtomModule, AtomFunc, AtomParams},
    NewOptions = lists:keystore(target, 1, Options, {target, Target}),
    action_analyze(Args, NewOptions);
action_analyze([{Opt, _} | _Args], _Options)
        when (Opt =:= 't') orelse (Opt =:= '-target') ->
    %% Found --target option with wrong parameters
    io:format("~s: wrong number of arguments for option -~s\n",
        [?APP_STRING, Opt]),
    halt(1);
action_analyze([{Opt, []} | _Args], _Options)
        when (Opt =:= 'f') orelse (Opt =:= '-files') ->
    %% Found --files options without parameters
    io:format("~s: wrong number of arguments for option -~s\n",
        [?APP_STRING, Opt]),
    halt(1);
action_analyze([{Opt, Files} | Args], Options)
        when (Opt =:= 'f') orelse (Opt =:= '-files') ->
    %% Found --files option
    NewOptions =
        case lists:keytake(files, 1, Options) of
            {value, {files, PrevFiles}, Options2} ->
                [{files, Files++PrevFiles} | Options2];
            false ->
                [{files, Files} | Options]
        end,
    action_analyze(Args, NewOptions);
action_analyze([{Opt, [File]} | Args], Options)
        when (Opt =:= 'o') orelse (Opt =:= '-output') ->
    %% Found --output option
    NewOptions = lists:keystore(output, 1, Options, {output, File}),
    action_analyze(Args, NewOptions);
action_analyze([{Opt, _Files} | _Args], _Options)
        when (Opt =:= 'o') orelse (Opt =:= '-output') ->
    %% Found --output option with wrong parameters
    io:format("~s: wrong number of arguments for option -~s\n",
        [?APP_STRING, Opt]),
    halt(1);
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
                halt(1)
        end,
    NewOptions = lists:keystore(preb, 1, Options, {preb, NewPreb}),
    action_analyze(Args, NewOptions);
action_analyze([{Opt, _Prebs} | _Args], _Options)
        when (Opt =:= 'p') orelse (Opt =:= '-preb') ->
    %% Found --preb option with wrong parameters
    io:format("~s: wrong number of arguments for option -~s\n",
        [?APP_STRING, Opt]),
    halt(1);
action_analyze([{'I', Includes} | Args], Options) ->
    %% Found -I option
    NewOptions =
        case lists:keytake(include, 1, Options) of
            {value, {include, PrevIncludes}, Options2} ->
                [{include, Includes++PrevIncludes} | Options2];
            false ->
                [{include, Includes} | Options]
        end,
    action_analyze(Args, NewOptions);
action_analyze([], Options) ->
    analyze(Options);
action_analyze([Arg | _Args], _Options) ->
    io:format("~s: unrecognised concuerror flag: ~p\n", [?APP_STRING, Arg]),
    halt(1).


%% Parse options for show command and call `show/1'
action_show(_Options, []) -> ok.

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
     "\n"
     "Show options:\n"
     "  -s|--snapshot  file     Specify input (snapshot) file\n"
     "  -n   from..to           Specify which errors we want (default -all)\n"
     "  --all                   Show all errors\n"
     "  -d|--details            Show details about each error\n"
     "\n"
     "Examples:\n"
     "  concuerror analyze --target foo bar arg1 arg2 "
            "--files \"temp/foo.erl\" -o out.ced\n"
     "  concuerror show --snapshot out.ced --all\n"
     "  concuerror show -snapshot out.ced -n 1 4..end --details\n\n").


%%%----------------------------------------------------------------------
%%% Analyze Commnad
%%%----------------------------------------------------------------------

%% @spec analyze(options()) -> 'true'
%% @doc: Run Concuerror analysis with the given options.
-spec analyze(options()) -> 'true'.
analyze(Options) ->
    %% Get target
    Target =
        case lists:keyfind(target, 1, Options) of
            {target, T} -> T;
            false ->
                io:format("~s: no target specified\n", [?APP_STRING]),
                halt(1)
        end,
    %% Get input files
    Files =
        case lists:keyfind(files, 1, Options) of
            {files, F} -> F;
            false ->
                io:format("~s: no input files specified\n", [?APP_STRING]),
                halt(1)
        end,
    %% Set output file
    Output =
        case lists:keyfind(output, 1, Options) of
            {output, O} -> O;
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
    AnalysisOptions = [{files, Files}, {preb, Preb}, {include, Include}],
    %% Start the log manager and attach the event handler below.
    _ = log:start(),
    _ = log:attach(?MODULE, []),
    %% Start the analysis
    AnalysisRet = sched:analyze(Target, AnalysisOptions),
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
    io:format("~p\n", [Options]),
    true.


%%%----------------------------------------------------------------------
%%% Log event handler callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {'ok', state()}.

%% @doc: Initialize the event handler.
init(_Env) -> {ok, []}.

-spec terminate(term(), state()) -> 'ok'.
terminate(_Reason, _State) -> ok.

-spec handle_event(log:event(), state()) -> {'ok', state()}.
handle_event({msg, String}, State) ->
    io:format("~s", [String]),
    {ok, State};
handle_event({error, _Ticket}, State) ->
    {ok, State}.
