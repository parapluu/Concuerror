-module(search).

-export([bfs/4, worker/2]).
%% CAUTION: worker needs to be exported if it is to be called from the shell

-type state() :: _.
-type environment() :: _.
-type comp_state() :: _.
-type any_state() :: state() | comp_state().
-type decomp_key() :: _.
-type backstep() :: _.
-type imm_hashentry() :: {state(),backstep()}.
-type imm_hashentry_S() :: {state()}.
-type any_imm_hashentry() :: imm_hashentry() | imm_hashentry_S().
-type hashentry() :: {comp_state(),backstep()}.
-type hashentry_S() :: {comp_state()}.
-type any_hashentry() :: hashentry() | hashentry_S().
-type any_entry() :: any_imm_hashentry() | any_hashentry().
-type answer_S() :: non_neg_integer() | -1.
-type answer() :: {answer_S(),[state()]}.

-type option() :: {'parallel',boolean()}
		| {'comp_level',non_neg_integer()}
		| {'comp_comm',boolean()}
		| {'precheck',boolean()}
		| {'solution',boolean()}
		| {'workers',pos_integer()}
		| {'balancing',boolean()}
		| {'buffer',pos_integer()}
		| {'limit',non_neg_integer()}.
-record(opts, {module               :: atom(),
	       parallel   = 'true'  :: boolean(),
	       comp_level = 1       :: non_neg_integer(),
	       comp_comm  = 'true'  :: boolean(),
	       decomp_key           :: decomp_key(),
	       precheck   = 'true'  :: boolean(),
	       solution   = 'false' :: boolean(),
	       workers    = 2       :: pos_integer(),
	       balancing  = 'true'  :: boolean(),
	       buffer     = 10      :: pos_integer(),
	       limit      = -1      :: -1 | non_neg_integer()}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% General Invocation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc Breadth-First Search. Searches breadth-first.
-spec bfs(environment(), state(), atom(), [option()]) -> answer() | answer_S().
bfs(Env0, State0, Mod, Opts) ->
    ParsedOpts = parse_options(State0, Mod, Opts),
    hash_init(),
    case ParsedOpts#opts.solution of
	true  -> hash_insert([{compress(State0, ParsedOpts),none}]);
	false -> hash_insert([{compress(State0, ParsedOpts)}])
    end,
    Ans = case ParsedOpts#opts.parallel of
	      true  -> bfs_paral(Env0, State0, ParsedOpts);
	      false -> bfs_serial(Env0, State0, ParsedOpts)
	  end,
    hash_destroy(),
    Ans.

-spec parse_options(state(), atom(), [option()]) -> #opts{}.
parse_options(State, Mod, Opts) ->
    ParsedOpts = parse_options_tr(Opts, #opts{module = Mod}),
    ParsedOpts#opts{decomp_key = get_decomp_key(State, ParsedOpts)}.

-spec parse_options_tr([option()], #opts{}) -> #opts{}.
parse_options_tr([], Opts) ->
    Opts;
parse_options_tr([Opt | Rest], Opts) ->
    NewOpts = case Opt of
		  {parallel,B}   -> Opts#opts{parallel = B};
		  {comp_level,N} -> Opts#opts{comp_level = N};
		  {comp_comm,B}  -> Opts#opts{comp_comm = B};
		  {precheck,B}   -> Opts#opts{precheck = B};
		  {solution,B}   -> Opts#opts{solution = B};
		  {workers,N}    -> Opts#opts{workers = N};
		  {balancing,B}  -> Opts#opts{balancing = B};
		  {buffer,N}     -> Opts#opts{buffer = N};
		  {limit,N}      -> Opts#opts{limit = N}
	      end,
    parse_options_tr(Rest, NewOpts).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Hashtable functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec hash_init() -> 'ok'.
hash_init() ->
    closed_set = ets:new(closed_set, [named_table]),
    ok.

-spec hash_destroy() -> 'true'.
hash_destroy() ->
    true = ets:delete(closed_set).

-spec hash_lookup(comp_state()) -> [any_hashentry()].
hash_lookup(CompState) ->
    ets:lookup(closed_set, CompState).

-spec hash_exists(comp_state()) -> boolean().
hash_exists(CompState) ->
    hash_lookup(CompState) =/= [].

-spec hash_insert([any_hashentry()]) -> 'ok'.
hash_insert(Entries) ->
    ets:insert(closed_set, Entries),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Compression functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec compress(state(), #opts{}) -> comp_state().
compress(State, Opts) ->
    (Opts#opts.module):compress(State, Opts#opts.comp_level).

-spec get_decomp_key(state(), #opts{}) -> decomp_key().
get_decomp_key(State, Opts) ->
    (Opts#opts.module):get_decomp_key(State, Opts#opts.comp_level).

-spec decompress(comp_state(), #opts{}) -> state().
decompress(CompState, Opts) ->
    (Opts#opts.module):decompress(CompState, Opts#opts.decomp_key,
				  Opts#opts.comp_level).

-spec compress_entry(any_imm_hashentry(), #opts{}) -> any_hashentry().
compress_entry({State,BackStep}, Opts) ->
    {compress(State, Opts), BackStep};
compress_entry({State}, Opts) ->
    {compress(State, Opts)}.

-spec get_state(any_entry()) -> state() | comp_state().
get_state({State,_BackStep}) -> State;
get_state({State})           -> State.

-spec trim_backstep(any_entry()) -> hashentry_S() | imm_hashentry_S().
trim_backstep(Entry) -> {get_state(Entry)}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Utility functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec worker_prep(imm_hashentry(), #opts{}) -> any_entry().
worker_prep({State,BackStep}, Opts) ->
    case {Opts#opts.solution, Opts#opts.comp_comm} of
	{true, false}  -> {State,BackStep};
	{true, true}   -> {compress(State, Opts),BackStep};
	{false, false} -> {State};
	{false, true}  -> {compress(State, Opts)}
    end.

-spec is_new(any_entry(), #opts{}) -> boolean().
is_new({State,_BackStep}, Opts) ->
    is_new({State}, Opts);
is_new({State}, Opts) ->
    case Opts#opts.comp_comm of
	true  -> not hash_exists(State);
	false -> not hash_exists(compress(State, Opts))
    end.

-spec coord_prep(any_entry(), #opts{}) -> any_hashentry().
coord_prep(Entry, Opts) ->
    case Opts#opts.comp_comm of
	true  -> Entry;
	false -> compress_entry(Entry, Opts)
    end.

-spec worker_filter(any_state(), #opts{}) -> state().
worker_filter(State, Opts) ->
    case Opts#opts.comp_comm of
	true  -> decompress(State, Opts);
	false -> State
    end.

-spec next_entries(environment(), state(), #opts{}) -> [imm_hashentry()].
next_entries(Env, State, Opts) ->
    (Opts#opts.module):next_entries(Env, State).

-spec winning(environment(), state(), #opts{}) -> boolean().
winning(Env, State, Opts) ->
    (Opts#opts.module):winning(Env, State).

-spec reverse_path(state(), #opts{}) -> [state(),...].
reverse_path(State, Opts) ->
    reverse_path(State, [], Opts).

-spec reverse_path(state(), [state()], #opts{}) -> [state(),...].
reverse_path(State, Path, Opts) ->
    case hash_lookup(compress(State, Opts)) of
	[{_S,none}] ->
	    [State | Path];
	[{_S,BackStep}] ->
	    PrevState = (Opts#opts.module):reverse_step(State, BackStep),
	    reverse_path(PrevState, [State | Path], Opts)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Serial Run
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec bfs_serial(environment(), state(), #opts{}) -> answer() | answer_S().
bfs_serial(Env, State, Opts) ->
    SerialOpts = Opts#opts{comp_comm = false},
    bfs_serial(0, Env, [State], [], SerialOpts).

-spec bfs_serial(non_neg_integer(), environment(), [state()], [state()],
		 #opts{}) ->
	  answer() | answer_S().
bfs_serial(_Moves, _Env, [], [], Opts) ->
    case Opts#opts.solution of
	true  -> {-1,[]};
	false -> -1
    end;
bfs_serial(Moves, Env, [], NextOpen, Opts) ->
    NewMoves = Moves + 1,
    case Opts#opts.limit == NewMoves of
	true  -> bfs_serial(NewMoves, Env, [], [], Opts);
	false -> bfs_serial(NewMoves, Env, NextOpen, [], Opts)
    end;
bfs_serial(Moves, Env, [State | Rest], NextOpen, Opts) ->
    case winning(Env, State, Opts) of
	true ->
	    case Opts#opts.solution of
		true  -> {Moves,reverse_path(State, Opts)};
		false -> Moves
	    end;
	false ->
	    Entries = next_entries(Env, State, Opts),
	    Entries2 = case Opts#opts.solution of
			   true  -> Entries;
			   false -> [trim_backstep(E) || E <- Entries]
		       end,
	    NewEntries = [E || E <- Entries2, is_new(E, Opts)],
	    CompNewEntries = [compress_entry(E, Opts) || E <- NewEntries],
	    hash_insert(CompNewEntries),
	    NewStates = [get_state(E) || E <- NewEntries],
	    bfs_serial(Moves, Env, Rest, NewStates ++ NextOpen, Opts)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parallel Run
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec bfs_paral(environment(), state(), #opts{}) -> answer() | answer_S().
bfs_paral(Env, State, Opts) ->
    coordinator(Env, State, Opts).

-spec coordinator(environment(), state(), #opts{}) -> answer() | answer_S().
coordinator(Env, State, Opts) ->
    register(coordinator, self()),
    process_flag(trap_exit, true),
    Workers = spawn_link_n(Opts#opts.workers, ?MODULE, worker, [Env,Opts]),
    StateToSend = case Opts#opts.comp_comm of
		      true  -> compress(State, Opts);
		      false -> State
		  end,
    Ans = case Opts#opts.balancing of
	      true ->
		  coordinator_outer(1, [StateToSend], 0, Workers, Opts);
	      false ->
		  lists:nth(1, Workers) ! {state, StateToSend},
		  coordinator_outer(1, [], 0, Workers, Opts)
	  end,
    %% There are still messages left in the message queue - we need to wait for
    %% the children to exit, then clean the mailbox just to be sure.
    wait_for_children(Opts#opts.workers),
    empty_mailbox(),
    process_flag(trap_exit, false),
    unregister(coordinator),
    Ans.

-spec coordinator_outer(non_neg_integer(), [any_state()], non_neg_integer(),
			[pid()], #opts{}) ->
	  answer() | answer_S().
coordinator_outer(0, [], _Moves, Workers, Opts) ->
    stop_workers(Workers),
    case Opts#opts.solution of
	true  -> {-1,[]};
	false -> -1
    end;
coordinator_outer(NextLeft, NextStates, Moves, Workers, Opts) ->
    %% io:format("~b~n", [Moves]),
    case Opts#opts.limit == Moves of
	true ->
	    coordinator_outer(0, [], Moves, Workers, Opts);
	false ->
	    case Opts#opts.balancing of
		true ->
		    NextStates2 = fill_buffers(NextStates, Workers, Opts),
		    coordinator_loop(NextLeft, NextStates2, 0, [], 0, Moves,
				     Workers, Opts);
		false ->
		    wake_workers(NextLeft, Workers, Opts),
		    coordinator_loop(NextLeft, [], 0, [], 0, Moves, Workers,
				     Opts)
	    end
    end.

-spec coordinator_loop(non_neg_integer(), [any_state()], non_neg_integer(),
		       [any_state()], non_neg_integer(), non_neg_integer(),
		       [pid()], #opts{}) ->
	  answer() | answer_S().
coordinator_loop(0, [], NextLeft, NextStates, _NextWorker, Moves, Workers,
		 Opts) ->
    coordinator_outer(NextLeft, NextStates, Moves + 1, Workers, Opts);
coordinator_loop(Left, States, NextLeft, NextStates, NextWorker, Moves, Workers,
		 Opts) ->
   receive
	{winning, State} ->
	    stop_workers(Workers),
	    case Opts#opts.solution of
		true  -> {Moves,reverse_path(State, Opts)};
		false -> Moves
	    end;
	{entries, Entries, From} ->
	    States2 =
		case {Opts#opts.balancing,States} of
		    {true,[State | Rest]} ->
			From ! {state, State},
			Rest;
		    _ ->
			States
		end,
	    NewEntries = [E || E <- Entries, is_new(E, Opts)],
	    PrepedNewEntries = [coord_prep(E, Opts) || E <- NewEntries],
	    hash_insert(PrepedNewEntries),
	    NewStates = [get_state(E) || E <- NewEntries],
	    NumNewStates = length(NewStates),
	    case Opts#opts.balancing of
		true ->
		    coordinator_loop(Left - 1, States2, NextLeft + NumNewStates,
				     NewStates ++ NextStates, NextWorker, Moves,
				     Workers, Opts);
		false ->
		    NewNextWorker = send_states(NewStates, NextWorker, Workers),
		    coordinator_loop(Left - 1, States2, NextLeft + NumNewStates,
				     NextStates, NewNextWorker, Moves, Workers,
				     Opts)
	    end
   end.

%% @private
-spec worker(environment(), #opts{}) -> no_return().
worker(Env, Opts) ->
    worker_wait(Env, Opts).

-spec worker_wait(environment(), #opts{}) -> no_return().
worker_wait(Env, Opts) ->
    case Opts#opts.balancing of
	true ->
	    worker_loop(-1, Env, Opts);
	false ->
	    receive
		stop             -> exit(normal);
		{continue, Load} -> worker_loop(Load, Env, Opts)
	    end
    end.

-spec worker_loop(integer(), environment(), #opts{}) -> no_return().
worker_loop(0, Env, Opts) ->
    worker_wait(Env, Opts);
worker_loop(Load, Env, Opts) ->
    receive
	stop -> exit(normal)
    after
	0 -> ok
    end,
    receive
	stop ->
	    exit(normal);
	{state, State} ->
	    FilteredState = worker_filter(State, Opts),
	    case winning(Env, FilteredState, Opts) of
		true ->
		    coordinator ! {winning, FilteredState},
		    receive
			stop -> exit(normal)
		    end;
		false ->
		    NextEntries = next_entries(Env, FilteredState, Opts),
		    PrepedEntries = [worker_prep(E, Opts) || E <- NextEntries],
		    NewEntries =
			case Opts#opts.precheck of
			    true  -> [E || E <- PrepedEntries, is_new(E, Opts)];
			    false -> PrepedEntries
			end,
		    coordinator ! {entries, NewEntries, self()},
		    worker_loop(Load - 1, Env, Opts)
	    end
    end.

-spec fill_buffers([any_state()], [pid()], #opts{}) -> [any_state()].
fill_buffers(States, Workers, Opts) ->
    fill_buffers_tr(States, Workers, Workers, Opts#opts.buffer).

-spec fill_buffers_tr([any_state()], [pid()], [pid()], non_neg_integer()) ->
	  [any_state()].
fill_buffers_tr([], _Workers, _AllWorkers, _Space) ->
    [];
fill_buffers_tr(States, _Workers, _AllWorkers, 0) ->
    States;
fill_buffers_tr(States, [], AllWorkers, Space) ->
    fill_buffers_tr(States, AllWorkers, AllWorkers, Space - 1);
fill_buffers_tr([State | States], [Worker | Workers], AllWorkers, Space) ->
    Worker ! {state, State},
    fill_buffers_tr(States, Workers, AllWorkers, Space).

-spec wake_workers(non_neg_integer(), [pid()], #opts{}) -> 'ok'.
wake_workers(Sent, Workers, Opts) ->
    Load = Sent div Opts#opts.workers,
    Overflow = Sent rem Opts#opts.workers,
    wake_workers_tr(Load, Overflow, Workers).

-spec wake_workers_tr(non_neg_integer(), non_neg_integer(), [pid()]) -> 'ok'.
wake_workers_tr(_Load, _Overflow, []) ->
    ok;
wake_workers_tr(Load, 0, [Pid | Rest]) ->
    Pid ! {continue, Load},
    wake_workers_tr(Load, 0, Rest);
wake_workers_tr(Load, Overflow, [Pid | Rest]) ->
    Pid ! {continue, Load + 1},
    wake_workers_tr(Load, Overflow - 1, Rest).

-spec stop_workers([pid()]) -> 'ok'.
stop_workers(Workers) ->
    lists:foreach(fun(Pid) -> Pid ! stop end, Workers).

-spec send_states([any_state()], non_neg_integer(), [pid(),...]) ->
	  non_neg_integer().
send_states(States, Next, Workers) ->
    send_states_tr(States, lists:nthtail(Next, Workers), Workers).

-spec send_states_tr([any_state()], [pid()], [pid()]) -> non_neg_integer().
send_states_tr([], [], _AllWorkers) ->
    0;
send_states_tr([], [NextWorker | _Rest], AllWorkers) ->
    length(lists:takewhile(fun(W) -> W =/= NextWorker end, AllWorkers));
send_states_tr(States, [], AllWorkers) ->
    send_states_tr(States, AllWorkers, AllWorkers);
send_states_tr([State | States], [Worker | Workers], AllWorkers) ->
    Worker ! {state, State},
    send_states_tr(States, Workers, AllWorkers).

-spec spawn_link_n(non_neg_integer(), atom(), atom(), [_,...]) -> [pid()].
spawn_link_n(N, Module, Name, Args) ->
    spawn_link_n_tr(N, Module, Name, Args, []).

-spec spawn_link_n_tr(non_neg_integer(), atom(), atom(), [_,...], [pid()]) ->
	  [pid()].
spawn_link_n_tr(0, _Module, _Name, _Args, Pids) ->
    Pids;
spawn_link_n_tr(N, Module, Name, Args, Pids) ->
    Pid = spawn_link(Module, Name, Args),
    spawn_link_n_tr(N - 1, Module, Name, Args, [Pid | Pids]).

-spec wait_for_children(non_neg_integer()) -> 'ok'.
wait_for_children(0) ->
    ok;
wait_for_children(N) ->
    receive
	{'EXIT', _FromPid, _Reason} ->
	    wait_for_children(N - 1);
	_ ->
	    wait_for_children(N)
    end.

-spec empty_mailbox() -> 'ok'.
empty_mailbox() ->
    receive
	_ -> empty_mailbox()
    after
	0 -> ok
    end.
