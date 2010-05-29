%%%----------------------------------------------------------------------
%%% File    : replay_server.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Replay Server
%%%
%%% Created : 1 Jun 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%
%%% @doc: Replay server
%%% @end
%%%----------------------------------------------------------------------

-module(replay_server).

%% API exports
-export([start/0, stop/0, lookup/1, register_errors/4]).
%% Callback exports
-export([init/1, terminate/2, handle_cast/2, handle_call/3,
	 code_change/3, handle_info/2]).

-behavior(gen_server).

-include("gen.hrl").

%% Internal server state record.
-record(state, {module   :: module(),
		function :: function(),
		args     :: [term()]}).

-type(state() :: #state{}).
		
%%%----------------------------------------------------------------------
%%% Eunit related
%%%----------------------------------------------------------------------

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

%%%----------------------------------------------------------------------
%%% API functions
%%%----------------------------------------------------------------------

-spec start() -> term().

start() ->
    gen_server:start({local, ?RP_REPLAY_SERVER}, ?MODULE, [], []).

-spec stop() -> 'ok'.

stop() ->
    gen_server:cast(?RP_REPLAY_SERVER, stop).

-spec register_errors(module(), function(), [term()], [term()]) -> 'ok'.

register_errors(Mod, Fun, Args, ErrorStates) ->
    gen_server:cast(?RP_REPLAY_SERVER, {register, Mod, Fun, Args, ErrorStates}).

-spec lookup(integer()) -> [proc_action()].

lookup(Id) when is_integer(Id) ->
    gen_server:call(?RP_REPLAY_SERVER, {lookup_by_id, Id}).
    
%%%----------------------------------------------------------------------
%%% Callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {ok, state()}.

init(_Args) ->
    ets:new(?NT_ERROR, [named_table]),
    {ok, #state{}}.

-spec terminate(term(), state()) -> 'true'.

terminate(_Reason, _State) ->
    ets:delete(?NT_ERROR).

-spec handle_cast({register, module(), function(),
		   [term()], [term()]}, state()) ->
			 {noreply, state()}.

handle_cast({register, Mod, Fun, Args, ErrorStates}, State) ->
    ets:delete_all_objects(?NT_ERROR),
    TupleList = create_list(ErrorStates),
    ets:insert(?NT_ERROR, TupleList),
    {noreply, State#state{module = Mod, function = Fun, args = Args}}.

-spec handle_call({lookup_by_id, integer()}, {pid(), term()}, state()) ->
			 {reply, [proc_action()], state()}.

handle_call({lookup_by_id, Id}, _From,
	    #state{module = Mod, function = Fun, args = Args} = State) ->
    [{Id, Ileaving, _Error, Details}] = ets:lookup(?NT_ERROR, Id),
    case Details of
	[] ->
	    NewDetails = sched:replay(Mod, Fun, Args, Ileaving),
	    ets:update_element(?NT_ERROR, Id, {4, NewDetails}),
	    {reply, NewDetails, State};
	Any -> {reply, Any, State}
    end.

-spec code_change(term(), term(), term()) -> no_return().

code_change(_OldVsn, _State, _Extra) ->
    log:internal("~p:~p: code_change~n", [?MODULE, ?LINE]).

-spec handle_info(term(), term()) -> no_return().

handle_info(_Info, _State) ->
    log:internal("~p:~p: handle_info~n", [?MODULE, ?LINE]).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

create_list(ErrorStates) ->
    create_list_aux(1, ErrorStates, []).

create_list_aux(_Id, [], Result) ->
    Result;
create_list_aux(Id, [{Error, Ileaving}|Rest], Result) ->
    Details = [],
    Tuple = {Id, Ileaving, Error, Details},
    create_list_aux(Id + 1, Rest, [Tuple|Result]).


%%%----------------------------------------------------------------------
%%% Unit tests
%%%----------------------------------------------------------------------

-spec replay_test_() -> term().

replay_test_() ->
    [{"test1",
      ?_test(begin
		 log:start(log, []),
		 replay_server:start(),
		 replay_logger:start(),
		 {error, analysis, _, [{deadlock, ReplayState}|_Whatever]} = 
		     sched:analyze(test, test4, [],
				   [{files, ["./test/test.erl"]}]),
		 Result = sched:replay(test, test4, [], ReplayState),
		 ?assertEqual(Result,
			      [{spawn,"P1", "P1.1"},
			       {block, "P1.1"}, {block, "P1"}]),
		 replay_logger:stop(),
		 replay_server:stop(),
		 log:stop()
	     end)}
    ].
