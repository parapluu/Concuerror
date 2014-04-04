%% -*- erlang-indent-level: 2 -*-

-module(concuerror_dependencies).

-export([dependent/3, dependent_safe/2, explain_error/1]).

%%------------------------------------------------------------------------------

-define(undefined_dependency(A,B), ?crash({undefined_dependency, A, B})).

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-spec explain_error(term()) -> string().

explain_error({undefined_dependency, A, B}) ->
  io_lib:format(
    "There exists no race info about the following pair of instructions~n~n"
    "1) ~s~n2) ~s~n~n"
    "You can run without --assume_racing=false to treat them as racing.~n"
    "Otherwise please ask the developers to add info about this pair.",
    [concuerror_printer:pretty_s(#event{event_info = I}, 10)
     || I <- [A,B]]).

-spec dependent_safe(event_info(), event_info()) -> boolean() | irreversible.

dependent_safe(E1, E2) ->
  try dependent(E1, E2)
  catch
    _:_ -> true
  end.

-spec dependent(event_info(), event_info(), boolean()) ->
                        boolean() | irreversible.

dependent(E1, E2, AssumeRacing) ->
  try dependent(E1, E2)
  catch
    _:_ ->
      AssumeRacing orelse ?undefined_dependency(E1, E2)
  end.

%% The first event happens before the second.

dependent(#builtin_event{mfargs = {erlang, halt, _}}, _) ->
  true;
dependent(_, #builtin_event{mfargs = {erlang, halt, _}}) ->
  true;

dependent(#builtin_event{mfargs = {erlang, process_info, _}} = PInfo, B) ->
  dependent_process_info(PInfo, B);
dependent(B, #builtin_event{mfargs = {erlang, process_info, _}} = PInfo) ->
  dependent_process_info(PInfo, B);

dependent(#builtin_event{} = BI1, #builtin_event{} = BI2) ->
  dependent_built_in(BI1, BI2);

dependent(#builtin_event{mfargs = MFArgs}, #exit_event{} = Exit) ->
  dependent_exit(Exit, MFArgs);
dependent(#exit_event{} = Exit, #builtin_event{} = Builtin) ->
  dependent(Builtin, Exit);

dependent(#builtin_event{actor = Actor, exiting = false,
                         trapping = Trapping} = Builtin,
          #message_event{message = #message{data = {'EXIT', _, Reason}},
                         recipient = Recipient, type = exit_signal}) ->
  #builtin_event{mfargs = MFArgs, result = Old} = Builtin,
  Actor =:= Recipient
    andalso
      (Reason =:= kill
       orelse
       case MFArgs of
         {erlang,process_flag,[trap_exit,New]} when New =/= Old -> true;
         _ -> not Trapping andalso Reason =/= normal
       end);
dependent(#message_event{} = Message,
          #builtin_event{mfargs = {erlang,process_flag,[trap_exit,_]}} = PFlag) ->
  dependent(PFlag, Message);

dependent(#exit_event{actor = Exiting, status = Status, trapping = Trapping},
          #message_event{message = #message{data = {'EXIT', _, Reason}},
                         recipient = Recipient, type = exit_signal}) ->
  Exiting =:= Recipient
    andalso
    case Status =:= running of
      false -> irreversible;
      true ->
        Reason =:= kill
         orelse
           (not Trapping andalso Reason =/= normal)
    end;
dependent(#message_event{} = Message, #exit_event{} = Exit) ->
  dependent(Exit, Message);

dependent(#exit_event{}, #exit_event{}) ->
  false;

dependent(#message_event{
             patterns = Patterns,
             recipient = Recipient,
             trapping = Trapping},
          #message_event{
             message = #message{data = Data},
             recipient = Recipient,
             type = Type
            }) ->
  is_function(Patterns)
    andalso
    message_could_match(Patterns, Data, Trapping, Type);

dependent(#message_event{
             message = #message{data = Data, message_id = Id},
             recipient = Recipient
            },
          #receive_event{
             message = Message,
             patterns = Patterns,
             recipient = Recipient,
             timeout = Timeout
            }) ->
  Timeout =/= infinity
    andalso
    case Message of
      'after' -> Patterns(Data);
      #message{message_id = Id} -> true;
      _ -> false
    end;
dependent(#receive_event{
             message = 'after',
             patterns = Patterns,
             recipient = Recipient,
             trapping = Trapping},
          #message_event{
             message = #message{data = Data},
             recipient = Recipient,
             type = Type
            }) ->
  message_could_match(Patterns, Data, Trapping, Type);

dependent(#message_event{}, _EventB) ->
  false;
dependent(_EventA, #message_event{}) ->
  false;

dependent(#receive_event{}, _EventB) ->
  false;
dependent(_EventA, #receive_event{}) ->
  false.

%%------------------------------------------------------------------------------

dependent_exit(_Exit, {erlang, exit, _}) -> false;
dependent_exit(_Exit, {erlang, process_flag, _}) -> false;
dependent_exit(_Exit, {erlang, put, _}) -> false;
dependent_exit(_Exit, {erlang, spawn, _}) -> false;
dependent_exit(_Exit, {erlang, spawn_opt, _}) -> false;
dependent_exit(_Exit, {erlang, spawn_link, _}) -> false;
dependent_exit(_Exit, {erlang, group_leader, _}) -> false;
dependent_exit(#exit_event{actor = Exiting},
               {erlang, is_process_alive, [Pid]}) ->
  Exiting =:= Pid;
dependent_exit(#exit_event{actor = Exiting}, {erlang, UnLink, [Linked]})
  when UnLink =:= link; UnLink =:= unlink ->
  Exiting =:= Linked;
dependent_exit(#exit_event{monitors = Monitors}, {erlang, demonitor, [Ref|_]}) ->
  false =/= lists:keyfind(Ref, 1, Monitors);
dependent_exit(#exit_event{actor = Exiting, name = Name},
               {erlang, monitor, [process, PidOrName]}) ->
  Exiting =:= PidOrName orelse Name =:= PidOrName;
dependent_exit(#exit_event{name = Name}, {erlang, NameRelated, [OName|_]})
  when
    NameRelated =:= '!';
    NameRelated =:= send;
    NameRelated =:= whereis ->
  OName =:= Name;
dependent_exit(#exit_event{actor = Exiting, name = Name},
               {erlang,UnRegisterOp,[RName|Rest]})
  when UnRegisterOp =:= register;
       UnRegisterOp =:= unregister ->
  RName =:= Name orelse
    case UnRegisterOp =:= register of
      false -> false;
      true ->
        [Pid] = Rest,
        Exiting =:= Pid
    end;
dependent_exit(#exit_event{actor = Exiting}, {ets, give_away, [_, Pid, _]}) ->
  Exiting =:= Pid;
dependent_exit(_Exit, {ets, _, _}) ->
  false.

%%------------------------------------------------------------------------------

dependent_process_info(#builtin_event{mfargs = {_, _, [Pid, registered_name]}},
                       Other) ->
  case Other of
    #builtin_event{extra = E, mfargs = {Module, Name, Args}} ->
      case Module =:= erlang of
        true when Name =:= register ->
          [_, RPid] = Args,
          Pid =:= RPid;
        true when Name =:= unregister ->
          E =:= Pid;
        _ -> false
      end;
    #exit_event{actor = EPid} ->
      Pid =:= EPid;
    _ -> false
  end;
dependent_process_info(#builtin_event{mfargs = {_,_,[Pid, dictionary]}},
                       Other) ->
  case Other of
    #builtin_event{actor = EPid, mfargs = {Module, Name, _}} ->
      Pid =:= EPid
        andalso
        case Module =:= erlang of
          true when Name =:= put; Name =:= erase ->
            true;
          _ -> false
        end;
    #exit_event{actor = EPid} ->
      Pid =:= EPid;
    _ -> false
  end.

%%------------------------------------------------------------------------------

dependent_built_in(#builtin_event{mfargs = {erlang, make_ref, _}},
                   #builtin_event{mfargs = {erlang, make_ref, _}}) ->
  true;

dependent_built_in(#builtin_event{mfargs = {erlang,group_leader,ArgsA}} = A,
                   #builtin_event{mfargs = {erlang,group_leader,ArgsB}} = B) ->
  case {ArgsA, ArgsB} of
    {[], []} -> false;
    {[New, For], []} ->
      #builtin_event{actor = Actor, result = Result} = B,
      New =/= Result andalso Actor =:= For;
    {[], [_,_]} -> dependent_built_in(B, A);
    {[_, ForA], [_, ForB]} ->
      ForA =:= ForB
  end;

dependent_built_in(#builtin_event{mfargs = {erlang, A, _}},
                   #builtin_event{mfargs = {erlang, B, _}})
  when
    false
    ;A =:= demonitor        %% Depends only with an exit event or proc_info
    ;A =:= exit             %% Sending an exit signal (dependencies are on delivery)
    ;A =:= get_stacktrace   %% Depends with nothing
    ;A =:= group_leader     %% Depends only with another group_leader get/set
    ;A =:= is_process_alive %% Depends only with an exit event
    ;A =:= make_ref         %% Depends with nothing
    ;A =:= monitor          %% Depends only with an exit event or proc_info
    ;A =:= process_flag     %% Depends only with delivery of a signal
    ;A =:= put              %% Depends only with proc_info
    ;A =:= spawn            %% Depends only with proc_info
    ;A =:= spawn_link       %% Depends only with proc_info
    ;A =:= spawn_opt        %% Depends only with proc_info
    
    ;B =:= demonitor
    ;B =:= exit
    ;B =:= get_stacktrace
    ;B =:= group_leader
    ;B =:= is_process_alive
    ;B =:= make_ref
    ;B =:= monitor
    ;B =:= process_flag
    ;B =:= put
    ;B =:= spawn
    ;B =:= spawn_link
    ;B =:= spawn_opt
    ->
  false;

dependent_built_in(#builtin_event{mfargs = {erlang, A, _}},
                   #builtin_event{mfargs = {erlang, B, _}})
  when (A =:= '!' orelse A =:= send orelse A =:= whereis orelse
        A =:= process_flag orelse A =:= link orelse A =:= unlink),
       (B =:= '!' orelse B =:= send orelse B =:= whereis orelse
        B =:= process_flag orelse B =:= link orelse B =:= unlink) ->
  false;

dependent_built_in(#builtin_event{mfargs = {erlang,UnRegisterA,[AName|ARest]}},
                   #builtin_event{mfargs = {erlang,UnRegisterB,[BName|BRest]}})
  when (UnRegisterA =:= register orelse UnRegisterA =:= unregister),
       (UnRegisterB =:= register orelse UnRegisterB =:= unregister) ->
  AName =:= BName
    orelse
      (ARest =/= [] andalso ARest =:= BRest);

dependent_built_in(#builtin_event{mfargs = {erlang,SendOrWhereis,[SName|_]}},
                   #builtin_event{mfargs = {erlang,UnRegisterOp,[RName|_]}})
  when (UnRegisterOp =:= register orelse UnRegisterOp =:= unregister),
       (SendOrWhereis =:= '!' orelse SendOrWhereis =:= send orelse
        SendOrWhereis =:= whereis) ->
  SName =:= RName;
dependent_built_in(#builtin_event{mfargs = {erlang,UnRegisterOp,_}} = R,
                   #builtin_event{mfargs = {erlang,SendOrWhereis,_}} = S)
  when (UnRegisterOp =:= register orelse UnRegisterOp =:= unregister),
       (SendOrWhereis =:= '!' orelse SendOrWhereis =:= send orelse
        SendOrWhereis =:= whereis) ->
  dependent_built_in(S, R);

dependent_built_in(#builtin_event{mfargs = {ets,delete,[Table1]}},
                   #builtin_event{mfargs = {ets,_Any,[Table2|_]}}) ->
  Table1 =:= Table2;
dependent_built_in(#builtin_event{mfargs = {ets,_Any,_}} = EtsAny,
                   #builtin_event{mfargs = {ets,delete,[_]}} = EtsDelete) ->
  dependent_built_in(EtsDelete, EtsAny);

dependent_built_in(#builtin_event{mfargs = {ets,Insert1,[Table1,Tuples1]},
                                  result = Result1, extra = Tid},
                   #builtin_event{mfargs = {ets,Insert2,[Table2,Tuples2]},
                                  result = Result2})
  when (Insert1 =:= insert orelse Insert1 =:= insert_new) andalso
       (Insert2 =:= insert orelse Insert2 =:= insert_new)->
  case Table1 =:= Table2 andalso (Result1 orelse Result2) of
    false -> false;
    true ->
      KeyPos = ets:info(Tid, keypos),
      List1 = case is_list(Tuples1) of true -> Tuples1; false -> [Tuples1] end,
      List2 = case is_list(Tuples2) of true -> Tuples2; false -> [Tuples2] end,
      %% At least one has succeeded. If both succeeded, none is a dangerous
      %% insert_new so ignore insertions of the same tuple. If one has failed it
      %% is an insert_new, and if they insert the same tuple they are dependent.
      OneFailed = Result1 andalso Result2,
      case length(List1) =< length(List2) of
        true -> ets_insert_dep(OneFailed, KeyPos, List1, List2);
        false -> ets_insert_dep(OneFailed, KeyPos, List2, List1)
      end
  end;

dependent_built_in(#builtin_event{mfargs = {ets,LookupA,_}},
                   #builtin_event{mfargs = {ets,LookupB,_}})
  when
    (LookupA =:= lookup orelse LookupA =:= lookup_element),
    (LookupB =:= lookup orelse LookupB =:= lookup_element) ->
  false;

dependent_built_in(#builtin_event{mfargs = {ets,Insert,[Table1,Tuples]},
                                  result = Result, extra = Tid},
                   #builtin_event{mfargs = {ets,Lookup,[Table2,Key|_]}})
  when
    (Insert =:= insert orelse Insert =:= insert_new),
    (Lookup =:= lookup orelse Lookup =:= lookup_element) ->
  case Table1 =:= Table2 andalso Result of
    false -> false;
    true ->
      KeyPos = ets:info(Tid, keypos),
      List = case is_list(Tuples) of true -> Tuples; false -> [Tuples] end,
      lists:keyfind(Key, KeyPos, List) =/= false
  end;
dependent_built_in(#builtin_event{mfargs = {ets,Lookup,_}} = EtsLookup,
                   #builtin_event{mfargs = {ets,Insert,_}} = EtsInsert)
  when
    (Insert =:= insert orelse Insert =:= insert_new),
    (Lookup =:= lookup orelse Lookup =:= lookup_element) ->
  dependent_built_in(EtsInsert, EtsLookup);

dependent_built_in(#builtin_event{mfargs = {ets,new,_}, result = Table1},
                   #builtin_event{mfargs = {ets,_Any,[Table2|_]}}) ->
  Table1 =:= Table2;
dependent_built_in(#builtin_event{mfargs = {ets,_Any,_}} = EtsAny,
                   #builtin_event{mfargs = {ets,new,_}} = EtsNew) ->
  dependent_built_in(EtsNew, EtsAny);

%% XXX: This can probably be refined.
dependent_built_in(#builtin_event{mfargs = {ets,give_away,[Table1|_]}},
                   #builtin_event{mfargs = {ets,_Any,[Table2|_]}}) ->
  Table1 =:= Table2;
dependent_built_in(#builtin_event{mfargs = {ets,_Any,_}} = EtsAny,
                   #builtin_event{mfargs = {ets,give_away,_}} = EtsGiveAway) ->
  dependent_built_in(EtsGiveAway, EtsAny);

dependent_built_in(#builtin_event{mfargs = {erlang,_,_}},
                   #builtin_event{mfargs = {ets,_,_}}) ->
  false;
dependent_built_in(#builtin_event{mfargs = {ets,_,_}} = Ets,
                   #builtin_event{mfargs = {erlang,_,_}} = Erlang) ->
  dependent_built_in(Erlang, Ets).

%%------------------------------------------------------------------------------

message_could_match(Patterns, Data, Trapping, Type) ->
  Patterns(Data)
    andalso
      (Trapping orelse (Type =:= message)).

ets_insert_dep(_IgnoreSame, _KeyPos, [], _List) -> false;
ets_insert_dep(IgnoreSame, KeyPos, [Tuple|Rest], List) ->
  case try_one_tuple(IgnoreSame, Tuple, KeyPos, List) of
    false -> ets_insert_dep(IgnoreSame, KeyPos, Rest, List);
    true -> true
  end.

try_one_tuple(IgnoreSame, Tuple, KeyPos, List) ->
  Key = element(KeyPos, Tuple),
  case lists:keyfind(Key, KeyPos, List) of
    false -> false;
    Tuple2 ->
      case Tuple =/= Tuple2 of
        true -> true;
        false ->
          case IgnoreSame of
            true ->
              NewList = lists:delete(Tuple2, List),
              try_one_tuple(IgnoreSame, Tuple, KeyPos, NewList);
            false -> true
          end
      end
  end.

