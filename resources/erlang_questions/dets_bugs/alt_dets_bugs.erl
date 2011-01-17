-module(alt_dets_bugs).

-export([bug3/0, bug5/0, bug6/0]).

-include_lib("eunit/include/eunit.hrl").

%% should always print [{0,0}], but sometimes prints []
bug3() ->
    dets:close(dets_table),
    sched:yield(),
    file:delete(dets_table),
    sched:yield(),
    dets:open_file(dets_table,[{type,bag}]),
    sched:yield(),
    spawn(fun() -> dets:open_file(dets_table,[{type,bag}]),
                   sched:yield()
          end),
    spawn(fun() ->
                  dets:insert(dets_table,[{0,0}]),
                  sched:yield(),
                  ?assertEqual([{0,0}], get_contents(dets_table))
          end).

%% should always print [{0,0}], but sometimes prints []
bug5() ->    
    Self = self(),
    spawn(fun() ->
                  [dets:close(dets_table) || _ <- "abcdefghijkl"],
                  file:delete(dets_table),
                  Parent = self(),
                  {ok, _T} = dets:open_file(dets_table,[{type,bag}]),
                  sched:yield(),
                  spawn(fun() ->
                                dets:open_file(dets_table,[{type,bag}]),
                                sched:yield(),
                                Parent ! done
                        end),
                  spawn(fun() ->
                                dets:insert(dets_table,[{0,0}]),
                                sched:yield(),
                                ?assertEqual([{0,0}], get_contents(dets_table)),
                                Parent ! done
                        end),
                  receive done -> receive done -> ok end end,
                  Self ! ok
          end),
    receive ok -> ok end.

bug6() ->
    dets:open_file(dets_table,[{type,bag}]),
    sched:yield(),
    dets:close(dets_table),
    sched:yield(),
    dets:open_file(dets_table,[{type,bag}]),
    sched:yield(),
    spawn(fun() -> dets:lookup(dets_table,0),
                   sched:yield()
          end),
    spawn(fun() -> dets:insert(dets_table,{0,0}),
                   sched:yield()
          end),
    dets:insert(dets_table,{0,0}),
    sched:yield(),
    ?assertEqual([{0,0}], match_object(dets_table)).

get_contents(Name) ->
    Ret = dets:traverse(Name, fun(X)-> {continue,X} end),
    sched:yield(),
    Ret.

match_object(Name) ->
    Ret = dets:match_object(Name,'_'),
    sched:yield(),
    Ret.
