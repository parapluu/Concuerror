-module(percept).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{instant_delivery, false}]).

-record(activity, {
        timestamp       ,%:: timestamp() ,
        id          ,%:: pid() | port() | scheduler_id(),
        state = undefined   ,%:: state() | 'undefined',
        where = undefined   ,%:: true_mfa() | 'undefined',
        runnable_count = 0   %:: non_neg_integer()
    }).

-record(information, {
        id         ,%:: pid() | port(),
        name = undefined   ,%:: atom() | string() | 'undefined',
        entry = undefined   ,%:: true_mfa() | 'undefined',
        start = undefined    ,%:: timestamp() | 'undefined',
        stop = undefined   ,%:: timestamp() | 'undefined',
        parent = undefined    ,%:: pid() | 'undefined',
        children = []      %:: [pid()]
    }).

%%%---------------------------------------
%%% Tests scenarios
%%%
scenarios() -> [{test, inf, dpor}].

test() -> spawn(fun start/0), spawn(fun start/0).

start() ->
    case erlang:whereis(percept_db) of
        undefined ->
            Pid = spawn( fun() -> init_percept_db() end),
            erlang:register(percept_db, Pid),
            {started, Pid};
        PerceptDB ->
            erlang:unregister(percept_db),
            PerceptDB ! {action, stop},
            Pid = spawn( fun() -> init_percept_db() end),
            erlang:register(percept_db, Pid),
            {restarted, Pid}
    end.

init_percept_db() ->
    % Proc and Port information
    ets:new(pdb_info, [named_table, private, {keypos, #information.id}, set]),

    % Scheduler runnability
    ets:new(pdb_scheduler, [named_table, private, {keypos, #activity.timestamp}, ordered_set]),

    % Process and Port runnability
    ets:new(pdb_activity, [named_table, private, {keypos, #activity.timestamp}, ordered_set]),

    % System status
    ets:new(pdb_system, [named_table, private, {keypos, 1}, set]),

    % System warnings
    ets:new(pdb_warnings, [named_table, private, {keypos, 1}, ordered_set]),
    put(debug, 0),
    loop_percept_db(1).

loop_percept_db(0) -> stopped;
loop_percept_db(N) ->
    receive
        {action, stop} ->
            stopped
    after 0 ->
            loop_percept_db(N-1)
    end.
