-module(driver).
-compile(export_all).

drive(Fun) ->
  Result = scheduler:start([{seed,now()}],Fun),
  io:format("~p~n",[noEvents(Result)]),
  case lists:keysearch(events,1,Result) of
    {value, {events, Events}} ->
      io:format("(generating file schedule.dot ...)~n"),
      dot:dot("schedule.dot", Events);
     
     _ -> ok
  end,
  Result.

drive0(Fun) ->
  drive(Fun),
  ok.

drive2(Fun) ->
  io:format("=== RUN 1 ===~n"),
  Result1 = drive(Fun),
  Sched1  = case lists:keysearch(schedule,1,Result1) of
              {value, {schedule,Sched}} -> Sched;
              _                         -> exit("no schedule")
            end,
  io:format("=== RUN 2 ===~n"),
  Result2 = scheduler:start([{schedule,Sched1}],fun() -> Fun() end),
  io:format("=== RESULT ===~n"),
  diff(noEvents(Result1),noEvents(Result2)).

noEvents(Result) ->
  [ Res || Res <- Result, case Res of {events,_} -> false; _ -> true end ].

diff(X,X) -> X;

diff(X,Y) when is_tuple(X), is_tuple(Y), size(X) == size(Y) ->
  list_to_tuple(diff(tuple_to_list(X), tuple_to_list(Y)));

diff([X|Xs],[Y|Ys]) ->
  [diff(X,Y)|diff(Xs,Ys)];

diff(X,Y) ->
  {X, 'NEQ', Y}.

