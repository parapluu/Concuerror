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
-export([gui/1, cli/0, analyze/1, export/2, stop/0]).
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

-type analysis_ret() ::
      sched:analysis_ret()
    | {'ok', 'gui'}
    | {'error', 'arguments', string()}.

%% Log event handler internal state.
%% The state (if we want have progress bar) contains
%% the current preemption number,
%% the progress in per cent,
%% the number of interleaving contained in this preemption number,
%% the number of errors we have found so far.
-type progress() :: {non_neg_integer(), -1..100,
                     non_neg_integer(), non_neg_integer()}.

-type state() :: {progress() | 'noprogress',
                  'log' | 'nolog'}.

%% Command line options
-type option() ::
      {'target',  sched:analysis_target()}
    | {'files',   [file()]}
    | {'output',  file()}
    | {'include', [file()]}
    | {'noprogress'}
    | {'nolog'}
    | {'preb',    sched:bound()}
    | {'gui'}
    | {'help'}.

-type options() :: [option()].

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

%% @spec gui(options()) -> 'true'
%% @doc: Start the CED GUI.
-spec gui(options()) -> 'true'.
gui(_Options) ->
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
    %% There should be no plain_arguments
    case init:get_plain_arguments() of
        [Arg|_] ->
            io:format("~s: unrecognised argument: ~s", [?APP_STRING, Arg]),
            init:stop(1);
        [] -> continue
    end,
    Options =
        case parse(Args2, []) of
            {'error', 'arguments', Msg1} ->
                io:format("~s: ~s\n", [?APP_STRING, Msg1]),
                init:stop(1);
            Opts -> Opts
        end,
    case cliAux(Options) of
        {'ok', 'gui'} ->
            true;
        {'error', 'arguments', Msg2} ->
            io:format("~s: ~s\n", [?APP_STRING, Msg2]),
            init:stop(1);
        Result ->
            %% Set output file
            Output =
                case lists:keyfind(output, 1, Options) of
                    {output, O} -> O;
                    false -> "results.txt"
                end,
            case export(Result, Output) of
                {'error', Msg3} ->
                    io:format("~s: ~s\n",
                        [?APP_STRING, file:format_error(Msg3)]),
                    init:stop(1);
                ok -> true
            end
    end.

cliAux(Options) ->
    case lists:keyfind('gui', 1, Options) of
        {'gui'} -> gui(Options), {'ok', 'gui'};
        false ->
            %% Start the log manager and attach the event handler below.
            _ = log:start(),
            _ = log:attach(?MODULE, Options),
            %% Run analysis
            Res = analyzeAux(Options),
            %% Stop event handler
            log:stop(),
            Res
    end.

%% Parse command line arguments
parse([{Opt, [Module,Func|Params]} | Args], Options)
        when (Opt =:= 't') orelse (Opt =:= '-target') ->
    %% Found --target option
    AtomModule = erlang:list_to_atom(Module),
    AtomFunc   = erlang:list_to_atom(Func),
    AtomParams = validateParams(Params, []),
    Target = {AtomModule, AtomFunc, AtomParams},
    NewOptions = lists:keystore(target, 1, Options, {target, Target}),
    parse(Args, NewOptions);
parse([{Opt, _} | _Args], _Options)
        when (Opt =:= 't') orelse (Opt =:= '-target') ->
    %% Found --target option with wrong parameters
    wrongArgument('number', Opt);
parse([{Opt, []} | _Args], _Options)
        when (Opt =:= 'f') orelse (Opt =:= '-files') ->
    %% Found --files options without parameters
    wrongArgument('number', Opt);
parse([{Opt, Files} | Args], Options)
        when (Opt =:= 'f') orelse (Opt =:= '-files') ->
    %% Found --files option
    NewOptions = keyAppend(files, 1, Options, Files),
    parse(Args, NewOptions);
parse([{Opt, [File]} | Args], Options)
        when (Opt =:= 'o') orelse (Opt =:= '-output') ->
    %% Found --output option
    NewOptions = lists:keystore(output, 1, Options, {output, File}),
    parse(Args, NewOptions);
parse([{Opt, _Files} | _Args], _Options)
        when (Opt =:= 'o') orelse (Opt =:= '-output') ->
    %% Found --output option with wrong parameters
    wrongArgument('number', Opt);
parse([{Opt, [Preb]} | Args], Options)
        when (Opt =:= 'p') orelse (Opt =:= '-preb') ->
    %% Found --preb option
    NewPreb =
        case string:to_integer(Preb) of
            {P, []} when P>=0 -> P;
            _ when (Preb=:="inf") orelse (Preb=:="off") -> inf;
            _ -> wrongArgument('type', Opt)
        end,
    NewOptions = lists:keystore(preb, 1, Options, {preb, NewPreb}),
    parse(Args, NewOptions);
parse([{Opt, _Prebs} | _Args], _Options)
        when (Opt =:= 'p') orelse (Opt =:= '-preb') ->
    %% Found --preb option with wrong parameters
    wrongArgument('number', Opt);
parse([{'I', Includes} | Args], Options) ->
    %% Found -I option
    NewOptions = keyAppend(include, 1, Options, Includes),
    parse(Args, NewOptions);
parse([{'-noprogress', []} | Args], Options) ->
    %% Found --noprogress option
    NewOptions = lists:keystore(noprogress, 1, Options, {noprogress}),
    parse(Args, NewOptions);
parse([{'-noprogress', _} | _Args], _Options) ->
    %% Found --noprogress option with wrong parameters
    wrongArgument('number', '-noprogress');
parse([{'-nolog', []} | Args], Options) ->
    %% Found --nolog option
    NewOptions = lists:keystore(nolog, 1, Options, {nolog}),
    parse(Args, NewOptions);
parse([{'-nolog', _} | _Args], _Options) ->
    %% Found --nolog option with wrong parameters
    wrongArgument('number', '-nolog');
parse([{'-help', _} | _Args], _Options) ->
    %% Found --help option
    help(),
    init:stop();
parse([], Options) ->
    Options;
parse([Arg | _Args], _Options) ->
    Msg = io_lib:format("unrecognised concuerror flag: ~p", [Arg]),
    {'error', 'arguments', Msg}.

%% Validate user provided function parameters.
validateParams([], Params) ->
    lists:reverse(Params);
validateParams([String|Strings], Params) ->
    case erl_scan:string(String ++ ".") of
        {ok, T, _} ->
            case erl_parse:parse_term(T) of
                {ok, Param} -> validateParams(Strings, [Param|Params]);
                {error, {_, _, Info}} ->
                    Msg = io_lib:format("arg ~s - ~s", [String, Info]),
                    {'error', 'arguments', Msg}
            end;
        {error, {_, _, Info}, _} ->
            Msg = io_lib:format("info ~s", [Info]),
            {'error', 'arguments', Msg}
    end.

keyAppend(Key, Pos, TupleList, Value) ->
    case lists:keytake(Key, Pos, TupleList) of
        {value, {Key, PrevValue}, TupleList2} ->
            [{Key, Value ++ PrevValue} | TupleList2];
        false ->
            [{Key, Value} | TupleList]
    end.

wrongArgument('number', Option) ->
    Msg = io_lib:format("wrong number of arguments for option -~s", [Option]),
    {'error', 'arguments', Msg};
wrongArgument('type', Option) ->
    Msg = io_lib:format("wrong type of argument for option -~s", [Option]),
    {'error', 'arguments', Msg}.

help() ->
    io:format(
     "usage: concuerror [<args>]\n"
     "A Systematic Testing Framework for detecting\n"
     "Concurrency Errors in Erlang Programs\n"
     "\n"
     "Arguments:\n"
     "  -t|--target module function [args]\n"
     "                          Specify the function to execute\n"
     "  -f|--files  modules     Specify the files (modules) to instrument\n"
     "  -o|--output file        Specify the output file (default results.txt)\n"
     "  -p|--preb   number|inf  Set preemption bound (default is 2)\n"
     "  -I          include_dir Pass the include_dir to concuerror\n"
     "  --no-progress           Disable progress bar\n"
     "  --help                  Show this help message\n"
     "\n"
     "Examples:\n"
     "  concuerror --target foo bar arg1 arg2 "
        "--files \"temp/foo.erl\" -o out.txt\n\n").


%%%----------------------------------------------------------------------
%%% Analyze Commnad
%%%----------------------------------------------------------------------

%% @spec analyze(options()) -> 'true'
%% @doc: Run Concuerror analysis with the given options.
-spec analyze(options()) -> analysis_ret().
analyze(Options) ->
    %% Disable error logging messages.
    ?tty(),
    %% Start the log manager.
    _ = log:start(),
    Res = analyzeAux(Options),
    %% Stop event handler
    log:stop(),
    Res.

analyzeAux(Options) ->
    %% Get target
    Target =
        case lists:keyfind(target, 1, Options) of
            {target, T} -> T;
            false ->
                Msg1 = "no target specified",
                {'error', 'arguments', Msg1}
        end,
    %% Get input files
    Files =
        case lists:keyfind(files, 1, Options) of
            {files, F} -> F;
            false ->
                Msg2 = "no input files specified",
                {'error', 'arguments', Msg2}
        end,
    %% Set include dirs
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
    %% Start the analysis
    sched:analyze(Target, Files, AnalysisOptions).


%%%----------------------------------------------------------------------
%%% Export Analysis results into a file
%%%----------------------------------------------------------------------

%% @spec export(sched:analysis_ret(), file()) ->
%%              'ok' | {'error', file:posix() | badarg | system_limit}
%% @doc: Export the analysis results into a text file.
-spec export(sched:analysis_ret(), file()) ->
    'ok' | {'error', file:posix() | badarg | system_limit}.
export(Results, File) ->
    case file:open(File, ['write']) of
        {ok, IoDevice} ->
            exportAux(Results, IoDevice),
            file:close(IoDevice);
        Error -> Error
    end.

exportAux({'ok', {_Target, RunCount}}, IoDevice) ->
    Msg = io_lib:format("Checked ~w interleaving(s). No errors found.\n",
        [RunCount]),
    file:write(IoDevice, Msg);
exportAux({error, instr, {_Target, _RunCount}}, IoDevice) ->
    Msg = io_lib:format("Instrumentation error.\n"),
    file:write(IoDevice, Msg);
exportAux({error, analysis, {_Target, RunCount}, Tickets}, IoDevice) ->
    TickLen = length(Tickets),
    Msg1 = io_lib:format("Checked ~w interleaving(s). ~w errors found.\n\n",
        [RunCount, TickLen]),
    file:write(IoDevice, Msg1),
    showDetails(1, ticket:sort(Tickets), IoDevice).

%% Show details about each ticket
showDetails(Count, [Ticket|Tickets], IoDevice) ->
    Error = ticket:get_error(Ticket),
    Msg1 = io_lib:format("~p\n~s\n", [Count, error:long(Error)]),
    file:write(IoDevice, Msg1),
    Details = ticket:get_state(Ticket),
    lists:foreach(fun(Detail) ->
                D = proc_action:to_string(Detail),
                Msg2 = io_lib:format("  ~s\n", [D]),
                file:write(IoDevice, Msg2) end,
        Details),
    file:write(IoDevice, "\n\n"),
    showDetails(Count+1, Tickets, IoDevice);
showDetails(_Count, [], _IoDevice) -> ok.


%%%----------------------------------------------------------------------
%%% Log event handler callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {'ok', state()}.

%% @doc: Initialize the event handler.
init(Options) ->
    Log =
        case lists:keyfind(nolog, 1, Options) of
            {nolog} -> nolog;
            false -> log
        end,
    Progress =
        case lists:keyfind(noprogress, 1, Options) of
            {noprogress} -> noprogress;
            false -> {0,-1,1,0}
        end,
    {ok, {Log, Progress}}.

-spec terminate(term(), state()) -> 'ok'.
terminate(_Reason, _State) -> ok.

-spec handle_event(log:event(), state()) -> {'ok', state()}.
handle_event({msg, String}, {log,_Prog}=State) ->
    io:format("~s", [String]),
    {ok, State};
handle_event({msg, _String}, {nolog,_Prog}=State) ->
    {ok, State};
handle_event({error, _Ticket}, {Log, {CurrPreb,Progress,Total,Errors}}) ->
    progress_bar(CurrPreb, Progress, Errors+1),
    {ok, {Log, {CurrPreb,Progress,Total,Errors+1}}};
handle_event({error, _Ticket}, {_Log, noprogress}=State) ->
    {ok, State};
handle_event({progress_log, Remain},
        {Log, {CurrPreb,Progress,Total,Errors}}=State) ->
    NewProgress = erlang:trunc(100 - Remain*100/Total),
    case NewProgress > Progress of
        true ->
            progress_bar(CurrPreb, NewProgress, Errors),
            {ok, {Log, {CurrPreb,NewProgress,Total,Errors}}};
        false ->
            {ok, State}
    end;
handle_event({progress_log, _Remain}, {_Log, noprogress}=State) ->
    {ok, State};
handle_event({progress_swap, NewTotal},
        {Log, {CurrPreb,_Progress,_Total,Errors}}) ->
    %% Clear last two lines from screen
    io:format("\033[J"),
    NextPreb = CurrPreb + 1,
    {ok, {Log, {NextPreb,-1,NewTotal,Errors}}};
handle_event({progress_swap, _NewTotal}, {_Log, noprogress}=State) ->
    {ok, State}.

progress_bar(CurrPreb, PerCent, Errors) ->
    Bar = string:chars($=, PerCent div 2, ">"),
    StrPerCent = io_lib:format("~p", [PerCent]),
    io:format("Preemption: ~p\n"
        " ~3s% [~.51s]  ~p errors found"
        "\033[1A\r",
        [CurrPreb, StrPerCent, Bar, Errors]).
