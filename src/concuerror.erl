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
-export([gui/1, cli/0, analyze/1, export/2, stop/0, stop/1]).
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
      concuerror_sched:analysis_ret()
    | {'error', 'arguments', string()}.

%% Command line options
-type option() ::
      {'target',  concuerror_sched:analysis_target()}
    | {'files',   [file:filename()]}
    | {'output',  file:filename()}
    | {'include', [file:name()]}
    | {'define',  concuerror_instr:macros()}
    | {'dpor', 'full' | 'flanagan'}
    | {'noprogress'}
    | {'quiet'}
    | {'preb',    concuerror_sched:bound()}
    | {'gui'}
    | {'verbose', non_neg_integer()}
    | {'keep_temp'}
    | {'help'}.

-type options() :: [option()].

%%%----------------------------------------------------------------------
%%% UI functions
%%%----------------------------------------------------------------------

%% @spec stop() -> ok
%% @doc: Stop the Concuerror analysis
-spec stop() -> ok.
stop() ->
    try ?RP_SCHED ! stop_analysis
    catch
        error:badarg ->
            init:stop()
    end,
    ok.

%% @spec stop_node([string(),...]) -> ok
%% @doc: Stop the Concuerror analysis
-spec stop([string(),...]) -> ok.
stop([Name]) ->
    %% Disable error logging messages.
    ?tty(),
    Node = list_to_atom(Name ++ ?HOST),
    case rpc:call(Node, ?MODULE, stop, []) of
        {badrpc, _Reason} ->
            %% Retry
            stop([Name]);
        _Res ->
            ok
    end.

%% @spec gui(options()) -> 'true'
%% @doc: Start the Concuerror GUI.
-spec gui(options()) -> 'true'.
gui(Options) ->
    %% Disable error logging messages.
    ?tty(),
    concuerror_gui:start(Options).

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
            case parse(Args, [{'verbose', 0}]) of
                {'error', 'arguments', Msg1} ->
                    io:format("~s: ~s\n", [?APP_STRING, Msg1]);
                Opts -> cliAux(Opts)
            end
    end.

cliAux(Options) ->
    %% Initialize timer table.
    concuerror_util:timer_init(),
    %% Start the log manager.
    _ = concuerror_log:start(),
    %% Parse options
    case lists:keyfind('gui', 1, Options) of
        {'gui'} -> gui(Options);
        false ->
            %% Attach the event handler below.
            case lists:keyfind('quiet', 1, Options) of
                false ->
                    _ = concuerror_log:attach(?MODULE, Options),
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
                    concuerror_log:log(0,
                        "\nWriting output to file ~s..", [Output]),
                    case export(Result, Output) of
                        {'error', Msg2} ->
                            concuerror_log:log(0,
                                "~s\n", [file:format_error(Msg2)]);
                        ok ->
                            concuerror_log:log(0, "done\n")
                    end
            end
    end,
    %% Stop event handler
    concuerror_log:stop(),
    %% Destroy timer table.
    concuerror_util:timer_destroy(),
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
                %% Run Eunit tests for specific module
                [Module] ->
                    AtomModule = 'eunit',
                    AtomFunc   = 'test',
                    Pars = ["[{module, " ++ Module ++ "}]", "[verbose]"],
                    case validateTerms(Pars, []) of
                        {'error',_,_}=Error -> Error;
                        AtomParams ->
                            Target = {AtomModule, AtomFunc, AtomParams},
                            NewOptions = lists:keystore(target, 1,
                                Options, {target, Target}),
                            NewArgs = [{'D',["TEST"]} | Args],
                            parse(NewArgs, NewOptions)
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
        "I" ++ Include ->
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
        "D" ++ Define ->
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

        "v" ->
            case Param of
                [] ->
                    NewOptions = keyIncrease('verbose', 1, Options),
                    parse(Args, NewOptions);
                _Other -> wrongArgument('number', Opt)
            end;

        "-keep-tmp-files" ->
            case Param of
                [] ->
                    NewOptions = lists:keystore('keep_temp', 1,
                        Options, {'keep_temp'}),
                    parse(Args, NewOptions);
                _Other -> wrongArgument('number', Opt)
            end;

        "-help" ->
            help(),
            erlang:halt();

        "-dpor" ->
            NewOptions = lists:keystore(dpor, 1, Options, {dpor, full}),
            parse(Args, NewOptions);

        "-dpor_flanagan" ->
            NewOptions = lists:keystore(dpor, 1, Options, {dpor, flanagan}),
            parse(Args, NewOptions);

        EF when EF=:="root"; EF=:="progname"; EF=:="home"; EF=:="smp";
            EF=:="noshell"; EF=:="noinput"; EF=:="sname"; EF=:="pa";
            EF=:="cookie" ->
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

keyIncrease(Key, Pos, TupleList) ->
    case lists:keytake(Key, Pos, TupleList) of
        {value, {Key, PrevValue}, TupleList2} ->
            [{Key, PrevValue+1} | TupleList2];
        false ->
            [{Key, ?DEFAULT_VERBOSITY + 1} | TupleList]
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
     "  -t|--target module      Run eunit tests for this module\n"
     "  -t|--target module function [args]\n"
     "                          Specify the function to execute\n"
     "  -f|--files  modules     Specify the files (modules) to instrument\n"
     "  -o|--output file        Specify the output file (default results.txt)\n"
     "  -p|--preb   number|inf  Set preemption bound (default is 2)\n"
     "  -I          include_dir Pass the include_dir to concuerror\n"
     "  -D          name=value  Define a macro\n"
     "  --noprogress            Disable progress bar\n"
     "  -q|--quiet              Disable logging (implies --noprogress)\n"
     "  -v                      Verbose [use twice to be more verbose]\n"
     "  --keep-tmp-files        Retain all intermediate temporary files\n"
     "  --gui                   Run concuerror with graphics\n"
     "  --dpor                  Runs the experimental optimal DPOR version\n"
     "  --dpor_flanagan         Runs an experimental reference DPOR version\n"
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
    _ = concuerror_log:start(),
    Res = analyzeAux(Options),
    %% Stop event handler
    concuerror_log:stop(),
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
                    concuerror_sched:analyze(Target, Files, Options)
            end
    end.


%%%----------------------------------------------------------------------
%%% Export Analysis results into a file
%%%----------------------------------------------------------------------

%% @spec export(concuerror_sched:analysis_ret(), file:filename()) ->
%%              'ok' | {'error', file:posix() | badarg | system_limit}
%% @doc: Export the analysis results into a text file.
-spec export(concuerror_sched:analysis_ret(), file:filename()) ->
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

exportAux({'ok', {_Target, RunCount, _SBlocked}}, IoDevice) ->
    Msg = io_lib:format("Checked ~w interleaving(s). No errors found.\n",
        [RunCount]),
    file:write(IoDevice, Msg);
exportAux({error, instr,
        {_Target, _RunCount, _SBlocked}}, IoDevice) ->
    Msg = "Instrumentation error.\n",
    file:write(IoDevice, Msg);
exportAux({error, analysis,
        {_Target, RunCount, _Sblocked}, Tickets}, IoDevice) ->
    TickLen = length(Tickets),
    Msg = io_lib:format("Checked ~w interleaving(s). ~w errors found.\n\n",
        [RunCount, TickLen]),
    case file:write(IoDevice, Msg) of
        ok ->
            case lists:foldl(fun writeDetails/2, {1, IoDevice},
                             concuerror_ticket:sort(Tickets)) of
                {'error', _Reason}=Error -> Error;
                _Ok -> ok
            end;
        Error -> Error
    end.

%% Write details about each ticket
writeDetails(_Ticket, {'error', _Reason}=Error) ->
    Error;
writeDetails(Ticket, {Count, IoDevice}) ->
    Error = concuerror_ticket:get_error(Ticket),
    Description = io_lib:format("~p\n~s\n",
        [Count, concuerror_error:long(Error)]),
    Details = ["  " ++ M ++ "\n"
            || M <- concuerror_ticket:details_to_strings(Ticket)],
    Msg = lists:flatten([Description | Details]),
    case file:write(IoDevice, Msg ++ "\n\n") of
        ok -> {Count+1, IoDevice};
        WriteError -> WriteError
    end.


%%%----------------------------------------------------------------------
%%% Log event handler callback functions
%%%----------------------------------------------------------------------

-type state() :: {non_neg_integer(), %% Verbose level
                  concuerror_util:progress() | 'noprogress'}.

-spec init(term()) -> {'ok', state()}.

%% @doc: Initialize the event handler.
init(Options) ->
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
terminate(_Reason, {_Verb, {_RunCnt, _Errors, _Elapsed, Timer}}) ->
    concuerror_util:timer_stop(Timer),
    ok.

-spec handle_event(concuerror_log:event(), state()) -> {'ok', state()}.
handle_event({msg, String, MsgVerb}, {Verb, _Progress}=State) ->
    if
        Verb >= MsgVerb ->
            io:format("~s", [String]);
        true ->
            ok
    end,
    {ok, State};

handle_event({progress, _Type}, {_Verb, 'noprogress'}=State) ->
    {ok, State};
handle_event({progress, Type}, {Verb, Progress}) ->
    case concuerror_util:progress_bar(Type, Progress) of
        {NewProgress, ""} ->
            {ok, {Verb, NewProgress}};
        {NewProgress, Msg} ->
            io:fwrite("\r\033[K" ++ Msg),
            {ok, {Verb, NewProgress}}
    end;

handle_event('reset', {_Verb, 'noprogress'}=State) ->
    {ok, State};
handle_event('reset', {Verb, _Progress}) ->
    {ok, {Verb, concuerror_util:init_state()}}.
