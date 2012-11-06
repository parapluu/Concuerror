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
    | {'error', 'arguments', string()}.

%% Log event handler internal state.
%% The state (if we want to have progress bar) contains
%% the current preemption number,
%% the progress in per cent,
%% the number of interleaving contained in this preemption number,
%% the number of errors we have found so far.
-type progress() :: {non_neg_integer(), -1..100,
                     non_neg_integer(), non_neg_integer()}.

-type state() :: progress() | 'noprogress'.

%% Command line options
-type option() ::
      {'target',  sched:analysis_target()}
    | {'files',   [file:filename()]}
    | {'output',  file:filename()}
    | {'include', [file:name()]}
    | {'define',  instr:macros()}
    | {'noprogress'}
    | {'quiet'}
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
            spawn(Node, fun() -> ?RP_SCHED ! stop_analysis end),
            ok;
        _ ->
            %% Well some times we could not connect with the
            %% first try so for now just repeat
            stop()
    end.

%% @spec gui(options()) -> 'true'
%% @doc: Start the CED GUI.
-spec gui(options()) -> 'true'.
gui(Options) ->
    %% Disable error logging messages.
    ?tty(),
    gui:start(Options).

%% @spec cli() -> 'true'
%% @doc: Parse the command line arguments and start Concuerror.
-spec cli() -> 'true'.
cli() ->
    %% Disable error logging messages.
    ?tty(),
    %% First get the command line options
    Args = init:get_arguments(),
    %% There should be no plain_arguments
    case init:get_plain_arguments() of
        [PlArg|_] ->
            io:format("~s: unrecognised argument: ~s\n", [?APP_STRING, PlArg]);
        [] ->
            case parse(Args, []) of
                {'error', 'arguments', Msg1} ->
                    io:format("~s: ~s\n", [?APP_STRING, Msg1]);
                Opts -> cliAux(Opts)
            end
    end.

cliAux(Options) ->
    %% Start the log manager.
    _ = log:start(),
    case lists:keyfind('gui', 1, Options) of
        {'gui'} -> gui(Options);
        false ->
            %% Attach the event handler below.
            case lists:keyfind('quiet', 1, Options) of
                false ->
                    _ = log:attach(?MODULE, Options),
                    ok;
                {'quiet'} -> ok
            end,
            %% Run analysis
            case analyzeAux(Options) of
                {'error', 'arguments', Msg1} ->
                    io:format("~s: ~s\n", [?APP_STRING, Msg1]);
                Result ->
                    %% Set output file
                    Output =
                        case lists:keyfind(output, 1, Options) of
                            {output, O} -> O;
                            false -> ?EXPORT_FILE
                        end,
                    log:log("Writing output to file ~s..", [Output]),
                    case export(Result, Output) of
                        {'error', Msg2} ->
                            log:log("~s\n", [file:format_error(Msg2)]);
                        ok ->
                            log:log("done\n")
                    end
            end
    end,
    %% Stop event handler
    log:stop(),
    'true'.

%% Parse command line arguments
parse([], Options) ->
    Options;
parse([{Opt, Param} | Args], Options) ->
    case atom_to_list(Opt) of
        T when T=:="t"; T=:="-target" ->
            case Param of
                [Module,Func|Pars] ->
                    AtomModule = erlang:list_to_atom(Module),
                    AtomFunc   = erlang:list_to_atom(Func),
                    case validateTerms(Pars, []) of
                        {'error',_,_}=Error -> Error;
                        AtomParams ->
                            Target = {AtomModule, AtomFunc, AtomParams},
                            NewOptions = lists:keystore(target, 1,
                                Options, {target, Target}),
                            parse(Args, NewOptions)
                    end;
                _Other -> wrongArgument('number', Opt)
            end;

        F when F=:="f"; F=:="-files" ->
            case Param of
                [] -> wrongArgument('number', Opt);
                Files ->
                    NewOptions = keyAppend(files, 1, Options, Files),
                    parse(Args, NewOptions)
            end;

        O when O=:="o"; O=:="-output" ->
            case Param of
                [File] ->
                    NewOptions = lists:keystore(output, 1,
                        Options, {output, File}),
                    parse(Args, NewOptions);
                _Other -> wrongArgument('number', Opt)
            end;

        "I" ->
            case Param of
                [Par] ->
                    NewOptions = keyAppend('include', 1,
                        Options, [Par]),
                    parse(Args, NewOptions);
                _Other -> wrongArgument('number', Opt)
            end;
        [$I | Include] ->
            case Param of
                [] -> parse([{'I', [Include]} | Args], Options);
                _Other -> wrongArgument('number', Opt)
            end;

        "D" ->
            case Param of
                [Par] ->
                    case string:tokens(Par, "=") of
                        [Name, Term] ->
                            AtomName = erlang:list_to_atom(Name),
                            case validateTerms([Term], []) of
                                {'error',_,_}=Error -> Error;
                                [AtomTerm] ->
                                    NewOptions = keyAppend('define', 1,
                                        Options, [{AtomName, AtomTerm}]),
                                    parse(Args, NewOptions)
                            end;
                        [Name] ->
                            AtomName = erlang:list_to_atom(Name),
                            case validateTerms(["true"], []) of
                                {'error',_,_}=Error -> Error;
                                [AtomTerm] ->
                                    NewOptions = keyAppend('define', 1,
                                        Options, [{AtomName, AtomTerm}]),
                                    parse(Args, NewOptions)
                            end;
                        _Other -> wrongArgument('type', Opt)
                    end;
                _Other -> wrongArgument('number', Opt)
            end;
        [$D | Define] ->
            case Param of
                [] -> parse([{'D', [Define]} | Args], Options);
                _Other -> wrongArgument('number', Opt)
            end;

        "-noprogress" ->
            case Param of
                [] ->
                    NewOptions = lists:keystore(noprogress, 1,
                        Options, {noprogress}),
                    parse(Args, NewOptions);
                _Other -> wrongArgument('number', Opt)
            end;

        Q when Q=:="q"; Q=:="-quiet" ->
            case Param of
                [] ->
                    NewOptions = lists:keystore(quiet, 1,
                        Options, {quiet}),
                    parse(Args, NewOptions);
                _Other -> wrongArgument('number', Opt)
            end;

        P when P=:="p"; P=:="-preb" ->
            case Param of
                [Preb] ->
                    case string:to_integer(Preb) of
                        {I, []} when I>=0 ->
                            NewOptions = lists:keystore(preb, 1, Options,
                                {preb, I}),
                            parse(Args, NewOptions);
                        _ when Preb=:="inf"; Preb=:="off" ->
                            NewOptions = lists:keystore(preb, 1, Options,
                                {preb, inf}),
                            parse(Args, NewOptions);
                        _Other -> wrongArgument('type', Opt)
                    end;
                _Other -> wrongArgument('number', Opt)
            end;

        "-gui" ->
            case Param of
                [] ->
                    NewOptions = lists:keystore(gui, 1,
                        Options, {gui}),
                    parse(Args, NewOptions);
                _Other -> wrongArgument('number', Opt)
            end;

        "-help" ->
            help(),
            erlang:halt();
        "-dpor" ->
            NewOptions = lists:keystore(dpor, 1, Options, {dpor, full}),
            parse([{'-noprogress',[]}|Args], NewOptions);
        "-dpor_fake" ->
            NewOptions = lists:keystore(dpor, 1, Options, {dpor, fake}),
            parse([{'-noprogress',[]}|Args], NewOptions);
        "-dpor_flanagan" ->
            NewOptions = lists:keystore(dpor, 1, Options, {dpor, flanagan}),
            parse([{'-noprogress',[]}|Args], NewOptions);
        EF when EF=:="root"; EF=:="progname"; EF=:="home"; EF=:="smp";
            EF=:="noshell"; EF=:="noinput"; EF=:="sname"; EF=:="pa" ->
                %% erl flag (ignore it)
                parse(Args, Options);

        Other ->
            Msg = io_lib:format("unrecognised concuerror flag: -~s", [Other]),
            {'error', 'arguments', Msg}
    end.


%% Validate user provided terms.
validateTerms([], Terms) ->
    lists:reverse(Terms);
validateTerms([String|Strings], Terms) ->
    case erl_scan:string(String ++ ".") of
        {ok, T, _} ->
            case erl_parse:parse_term(T) of
                {ok, Term} -> validateTerms(Strings, [Term|Terms]);
                {error, {_, _, Info}} ->
                    Msg1 = io_lib:format("arg ~s - ~s", [String, Info]),
                    {'error', 'arguments', Msg1}
            end;
        {error, {_, _, Info}, _} ->
            Msg2 = io_lib:format("info ~s", [Info]),
            {'error', 'arguments', Msg2}
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
     ?INFO_MSG
     "\n"
     "usage: concuerror [<args>]\n"
     "Arguments:\n"
     "  -t|--target module function [args]\n"
     "                          Specify the function to execute\n"
     "  -f|--files  modules     Specify the files (modules) to instrument\n"
     "  -o|--output file        Specify the output file (default results.txt)\n"
     "  -p|--preb   number|inf  Set preemption bound (default is 2)\n"
     "  -I          include_dir Pass the include_dir to concuerror\n"
     "  -D          name=value  Define a macro\n"
     "  --noprogress            Disable progress bar\n"
     "  -q|--quiet              Disable logging (implies --noprogress)\n"
     "  --gui                   Run concuerror with graphics\n"
     "  --help                  Show this help message\n"
     "\n"
     "Examples:\n"
     "  concuerror -DVSN=\\\"1.0\\\" --target foo bar arg1 arg2 "
        "--files \"foo.erl\" -o out.txt\n"
     "  concuerror --gui -I./include --files foo.erl --preb inf\n\n").


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
    case lists:keyfind(target, 1, Options) of
        false ->
            Msg1 = "no target specified",
            {'error', 'arguments', Msg1};
        {target, Target} ->
            %% Get input files
            case lists:keyfind(files, 1, Options) of
                false ->
                    Msg2 = "no input files specified",
                    {'error', 'arguments', Msg2};
                {files, Files} ->
                    %% Start the analysis
                    sched:analyze(Target, Files, Options)
            end
    end.


%%%----------------------------------------------------------------------
%%% Export Analysis results into a file
%%%----------------------------------------------------------------------

%% @spec export(sched:analysis_ret(), file:filename()) ->
%%              'ok' | {'error', file:posix() | badarg | system_limit}
%% @doc: Export the analysis results into a text file.
-spec export(sched:analysis_ret(), file:filename()) ->
    'ok' | {'error', file:posix() | badarg | system_limit | terminated}.
export(Results, File) ->
    case file:open(File, ['write']) of
        {ok, IoDevice} ->
            case exportAux(Results, IoDevice) of
                ok -> file:close(IoDevice);
                Error -> Error
            end;
        Error -> Error
    end.

exportAux({'ok', {_Target, RunCount}}, IoDevice) ->
    Msg = io_lib:format("Checked ~w interleaving(s). No errors found.\n",
        [RunCount]),
    file:write(IoDevice, Msg);
exportAux({error, instr, {_Target, _RunCount}}, IoDevice) ->
    Msg = "Instrumentation error.\n",
    file:write(IoDevice, Msg);
exportAux({error, analysis, {_Target, RunCount}, Tickets}, IoDevice) ->
    TickLen = length(Tickets),
    Msg = io_lib:format("Checked ~w interleaving(s). ~w errors found.\n\n",
        [RunCount, TickLen]),
    case file:write(IoDevice, Msg) of
        ok ->
            case lists:foldl(fun writeDetails/2, {1, IoDevice},
                    ticket:sort(Tickets)) of
                {'error', _Reason}=Error -> Error;
                _Ok -> ok
            end;
        Error -> Error
    end.

%% Write details about each ticket
writeDetails(_Ticket, {'error', _Reason}=Error) ->
    Error;
writeDetails(Ticket, {Count, IoDevice}) ->
    Error = ticket:get_error(Ticket),
    Description =
        io_lib:format("~p\n~s\n", [erlang:phash2(Ticket), error:long(Error)]),
    Details = lists:map(fun(M) -> "  " ++ M ++ "\n" end,
                    ticket:details_to_strings(Ticket)),
    Msg = lists:flatten([Description | Details]),
    case file:write(IoDevice, Msg ++ "\n\n") of
        ok -> {Count+1, IoDevice};
        WriteError -> WriteError
    end.


%%%----------------------------------------------------------------------
%%% Log event handler callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {'ok', state()}.

%% @doc: Initialize the event handler.
init(Options) ->
    Progress =
        case lists:keyfind(noprogress, 1, Options) of
            {noprogress} -> noprogress;
            false -> {0,-1,1,0}
        end,
    {ok, Progress}.

-spec terminate(term(), state()) -> 'ok'.
terminate(_Reason, _State) -> ok.

-spec handle_event(log:event(), state()) -> {'ok', state()}.
handle_event({msg, String}, State) ->
    io:format("~s", [String]),
    {ok, State};
handle_event({error, _Ticket}, {CurrPreb,Progress,Total,Errors}) ->
    progress_bar(CurrPreb, Progress, Errors+1),
    {ok, {CurrPreb,Progress,Total,Errors+1}};
handle_event({error, _Ticket}, 'noprogress') ->
    {ok, 'noprogress'};
handle_event({progress_log, Remain}, {CurrPreb,Progress,Total,Errors}=State) ->
    NewProgress = erlang:trunc(100 - Remain*100/Total),
    case NewProgress > Progress of
        true ->
            progress_bar(CurrPreb, NewProgress, Errors),
            {ok, {CurrPreb,NewProgress,Total,Errors}};
        false ->
            {ok, State}
    end;
handle_event({progress_log, _Remain}, 'noprogress') ->
    {ok, 'noprogress'};
handle_event({progress_swap, NewTotal}, {CurrPreb,_Progress,_Total,Errors}) ->
    %% Clear last two lines from screen
    io:format("\033[J"),
    NextPreb = CurrPreb + 1,
    {ok, {NextPreb,-1,NewTotal,Errors}};
handle_event({progress_swap, _NewTotal}, 'noprogress') ->
    {ok, 'noprogress'}.

progress_bar(CurrPreb, PerCent, Errors) ->
    Bar = string:chars($=, PerCent div 2, ">"),
    StrPerCent = io_lib:format("~p", [PerCent]),
    io:format("Preemption: ~p\n"
        " ~3s% [~.51s]  ~p errors found"
        "\033[1A\r",
        [CurrPreb, StrPerCent, Bar, Errors]).
