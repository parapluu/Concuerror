-module(dets_bugs).

-export([bug1/0, bug2/0, bug3/0, bug4/0, bug5/0, bug6/0]).

%% should always print a boolean, but sometimes prints 'ok'
bug1() ->
    {ok,T} = dets:open_file(dets_table,[{type,bag}]),
    spawn(fun()->dets:insert(T,[]) end),
    spawn(fun()->io:format("~p\n",[dets:insert_new(T,[])]) end). 

%% causes a bug message to appear
bug2() ->
    file:delete(dets_table),
    T = dets:open_file(dets_table,[{type,set}]),
    spawn(fun() -> dets:delete(T,0) end),
    spawn(fun() -> dets:insert_new(T,{0,0}) end),
    ok.

%% should always print [{0,0}], but sometimes prints []
bug3() ->
    dets:close(dets_table),
    file:delete(dets_table),
    {ok,_T} = dets:open_file(dets_table,[{type,bag}]),
    spawn(fun() -> dets:open_file(dets_table,[{type,bag}]) end),
    spawn(fun() ->
                  dets:insert(dets_table,[{0,0}]),
                  io:format("~p\n",[get_contents(dets_table)])
          end).

%% should always print [], but sometimes prints [{7,0}]
bug4() ->
    dets:close(dets_table),
    file:delete(dets_table),
    {ok,_T} = dets:open_file(dets_table,[{type,bag}]),
    dets:insert(dets_table,{7,0}),
    spawn(fun() -> dets:open_file(dets_table,[{type,bag}]) end),
    spawn(fun() ->
                  dets:delete(dets_table,7),
                  io:format("~p\n",[get_contents(dets_table)])
          end).

%% should always print [{0,0}], but sometimes prints []
bug5() ->
    Self = self(),
    spawn(fun() ->
                  [dets:close(dets_table) || _ <- "abcdefghijkl"],
                  file:delete(dets_table),
                  Parent = self(),
                  {ok,_T} = dets:open_file(dets_table,[{type,bag}]),
                  spawn(fun() -> dets:open_file(dets_table,[{type,bag}]),
                                 Parent ! done
                        end),
                  spawn(fun() ->
                                dets:insert(dets_table,[{0,0}]),
                                io:format("~p\n",[get_contents(dets_table)]),
                                Parent ! done
                        end),
                  receive done -> receive done -> ok end end,
                  Self ! ok
          end),
    receive ok -> ok end.

bug6() ->
    dets:open_file(dets_table,[{type,bag}]), 
    dets:close(dets_table), 
    dets:open_file(dets_table,[{type,bag}]), 
    spawn(fun() -> dets:lookup(dets_table,0)
          end),
    spawn(fun() -> dets:insert(dets_table,{0,0})
          end),
    dets:insert(dets_table,{0,0}),
    dets:match_object(dets_table,'_').
    

get_contents(Name) ->
    dets:traverse(Name,fun(X)->{continue,X}end).
