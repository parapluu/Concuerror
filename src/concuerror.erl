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
-export([gui/0, cli/0, run/1]).
%% Log server callback exports.
-export([init/1, terminate/2, handle_event/2]).

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
    | {'number', {pos_integer(), pos_integer()}}
    | {'details'}
    ].


%%%----------------------------------------------------------------------
%%% UI functions
%%%----------------------------------------------------------------------

%% @spec gui() -> 'true'
%% @doc: Start the CED GUI.
-spec gui() -> 'true'.
gui() ->
    gui:start().

%% @spec cli() -> 'true'
%% @doc: Parse the command line arguments and start Concuerror.
-spec cli() -> 'true'.
cli() ->
    help(),
    true.

%% @spec run(options()) -> 'true'
%% @doc: Run Concuerror with the given options.
-spec run(options()) -> 'true'.
run(_Options) ->
    true.

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
     "  -t|-target  module function [args]\n"
     "                          Specify the function to execute\n"
     "  -f|-files   modules     Specify the files (modules) to instrument\n"
     "  -o|-output  file        Specify the output file (default results.ced)\n"
     "  -p|-preb    number|inf  Set preemption bound (default is 2)\n"
     "\n"
     "Show options:\n"
     "  -s|-snapshot  file      Specify input (snapshot) file\n"
     "  -n   from..to           Specify which errors we want (default -all)\n"
     "  -all                    Show all errors\n"
     "  -details                Show more details about each error\n"
     "\n"
     "Examples:\n"
     "  concuerror analyze -target foo bar arg1 arg2 "
            "-files \"temp/foo.erl\" -o out.ced\n"
     "  concuerror show -snapshot out.ced -all\n"
     "  concuerror show -snapshot out.ced -n 4..end -details\n\n").


%%%----------------------------------------------------------------------
%%% Log event handler callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {'ok', state()}.

%% @doc: Initialize the event handler.
init(_Env) -> {ok, []}.

-spec terminate(term(), state()) -> 'ok'.
terminate(_Reason, _State) -> ok.

-spec handle_event(log:event(), state()) -> {'ok', state()}.
handle_event({msg, _String}, State) ->
    {ok, State};
handle_event({error, _Ticket}, State) ->
    {ok, State}.
