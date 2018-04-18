-module(stacktrace).

%% API

-export([ start_link/0
        , stop/0
        , call/0
        , test/0
        ]).

%% gen_server callbacks

-behaviour(gen_server).

-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

%%%===================================================================

-type state() :: none.

%%%===================================================================

-define(SERVER, ?MODULE).

%%%===================================================================
%%% TEST
%%%===================================================================

-spec test() -> 'ok'.
test() ->
  start_link(),
  call().

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Starts the server
%% @end
%%--------------------------------------------------------------------

-spec start_link() -> {'ok', pid()}.
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, no_args, []).

%%--------------------------------------------------------------------
%% @doc Stops the server
%% @end
%%--------------------------------------------------------------------

-spec stop() -> ok.
stop() ->
  gen_server:stop(?SERVER).

%%--------------------------------------------------------------------
%% @doc Makes a call
%% @end
%%--------------------------------------------------------------------

-spec call() -> 'ok'.
call() ->
  gen_server:call(?SERVER, call, infinity).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Initializes the server
%% @end
%%--------------------------------------------------------------------

-spec init(_Args) -> {ok, state()}.
init(_) ->
  {ok, none}.

%%--------------------------------------------------------------------
%% @private
%% @doc Handling call messages
%% @end
%%--------------------------------------------------------------------

-spec handle_call(term(), term(), state()) -> {reply, ok, state()}.
handle_call(call, _From, State) ->
  _ = dict:erase(call),
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc Handling cast messages
%% @end
%%--------------------------------------------------------------------

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Message, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc Cleanup
%% @end
%%--------------------------------------------------------------------

-spec terminate(term(), state()) -> 'ok'.
terminate(_Reason, _State) ->
  ok.


%%--------------------------------------------------------------------
%% @private
%% @doc Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------

-spec code_change(_, State, _) -> {ok, State} when State :: state().
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
