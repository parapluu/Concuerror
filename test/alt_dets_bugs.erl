-module(alt_dets_bugs).

-export([bug3/0, bug5/0]).

-include("ced.hrl").

%% should always print [{0,0}], but sometimes prints []
bug3() ->
    Close = dets:close(dets_table),
    sched:rep_yield(),
    Close,
    Del = file:delete(dets_table),
    sched:rep_yield(),
    Del,
    {ok, T} = dets:open_file(dets_table,[{type,bag}]),
    sched:rep_yield(),
    {ok, T},
    spawn(fun() -> Ret = dets:open_file(dets_table,[{type,bag}]),
                   sched:rep_yield(),
                   Ret
          end),
    spawn(fun() ->
                  Ret = dets:insert(dets_table,[{0,0}]),
                  sched:rep_yield(),
                  Ret,
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
                  sched:rep_yield(),
                  spawn(fun() ->
                                dets:open_file(dets_table,[{type,bag}]),
                                sched:rep_yield(),
                                Parent ! done
                        end),
                  spawn(fun() ->
                                dets:insert(dets_table,[{0,0}]),
                                sched:rep_yield(),
                                ?assertEqual([{0,0}], get_contents(dets_table)),
                                Parent ! done
                        end),
                  receive done -> receive done -> ok end end,
                  Self ! ok
          end),
    receive ok -> ok end.

get_contents(Name) ->
    Ret = dets:traverse(Name, fun(X)-> {continue,X} end),
    sched:rep_yield(),
    Ret.
