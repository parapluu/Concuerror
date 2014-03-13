%% -*- erlang-indent-level: 2 -*-

-module(concuerror_dependencies).

-export([dependent/2]).

%%------------------------------------------------------------------------------

-define(DEBUG, true).
% -define(UNDEFINED_ERROR, true).
-ifdef(UNDEFINED_ERROR).
-define(undefined_error, error(undefined_dependency)).
-else.
-define(undefined_error, ok).
-endif.
-include("concuerror.hrl").

%%------------------------------------------------------------------------------

%% The first event happens before the second.

-spec dependent(event_info(), event_info()) -> boolean().

dependent(#builtin_event{mfa = {erlang, halt, _}}, _) ->
  true;
dependent(_, #builtin_event{mfa = {erlang, halt, _}}) ->
  true;

dependent(#builtin_event{mfa = {erlang, process_info, _}} = PInfo, B) ->
  dependent_process_info(PInfo, B);
dependent(B, #builtin_event{mfa = {erlang, process_info, _}} = PInfo) ->
  dependent_process_info(PInfo, B);

dependent(#builtin_event{} = BI1, #builtin_event{} = BI2) ->
  dependent_built_in(BI1, BI2);

dependent(#builtin_event{mfa = MFA}, #exit_event{} = Exit) ->
  dependent_exit(Exit, MFA);
dependent(#exit_event{} = Exit, #builtin_event{} = Builtin) ->
  dependent(Builtin, Exit);

dependent(#builtin_event{mfa = {erlang,process_flag,[trap_exit,New]}} = Builtin,
          #message_event{message = #message{data = Data},
                         recipient = Recipient, type = Type}) ->
  #builtin_event{actor = Actor, result = Old} = Builtin,
  New =/= Old andalso
    Type =:= exit_signal andalso
    Actor =:= Recipient andalso
    begin
      {'EXIT', _, Reason} = Data,
      Reason =/= kill
    end;
dependent(#message_event{} = Message,
          #builtin_event{mfa = {erlang,process_flag,[trap_exit,_]}} = PFlag) ->
  dependent(PFlag, Message);

dependent(#exit_event{actor = Exiting, reason = Reason, trapping = Trapping},
          #message_event{message = #message{data = Data},
                         recipient = Recipient, type = Type}) ->
  Type =:= exit_signal
    andalso
    (not Trapping orelse Reason =:= kill)
    andalso
    Exiting =:= Recipient
    andalso
    case Data of
      {'EXIT', _, NewReason} ->
        NewReason =/= normal andalso Reason =/= NewReason
          andalso not (Reason =:= killed andalso NewReason =:= kill)
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
  case is_function(Patterns) of
    true -> message_could_match(Patterns, Data, Trapping, Type);
    false -> false
  end;

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
  false;

%% XXX: Event may be undefined in a wakeup tree.
dependent(_EventA, _EventB) ->
  ?debug("UNSPECIFIED DEPENDENCY!\n~p\n~p\n", [_EventA, _EventB]),
  ?undefined_error,
  true.

%%------------------------------------------------------------------------------

dependent_exit(_Exit, {erlang, A, _})
  when
    false
    ;A =:= exit
    ;A =:= process_flag
    ;A =:= put
    ;A =:= spawn
    ;A =:= spawn_opt
    ;A =:= spawn_link
    ;A =:= group_leader
    ->
  false;
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
  false;
dependent_exit(_Exit, _MFA) ->
  ?debug("UNSPECIFIED EXIT DEPENDENCY!\n~p\n", [_MFA]),
  ?undefined_error,
  true.

%%------------------------------------------------------------------------------

dependent_process_info(#builtin_event{mfa = {_,_,[Pid, registered_name]}},
                       Other) ->
  case Other of
    #builtin_event{extra = E, mfa = {Module, Name, Args}} ->
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
dependent_process_info(#builtin_event{mfa = {_,_,[Pid, dictionary]}},
                       Other) ->
  case Other of
    #builtin_event{actor = EPid, mfa = {Module, Name, _}} ->
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
  end;
dependent_process_info(_Pinfo, _B) ->
  ?debug("UNSPECIFIED PINFO DEPENDENCY!\n~p\n", [{_Pinfo, _B}]),
  ?undefined_error,
  true.

%%------------------------------------------------------------------------------

dependent_built_in(#builtin_event{mfa = {erlang, make_ref, _}},
                   #builtin_event{mfa = {erlang, make_ref, _}}) ->
  true;

dependent_built_in(#builtin_event{mfa = {erlang,group_leader,ArgsA}} = A,
                   #builtin_event{mfa = {erlang,group_leader,ArgsB}} = B) ->
  case {ArgsA, ArgsB} of
    {[], []} -> false;
    {[New, For], []} ->
      #builtin_event{actor = Actor, result = Result} = B,
      New =/= Result andalso Actor =:= For;
    {[], [_,_]} -> dependent_built_in(B, A);
    {[_, ForA], [_, ForB]} ->
      ForA =:= ForB
  end;

dependent_built_in(#builtin_event{mfa = {erlang, A,_}},
                   #builtin_event{mfa = {erlang, B,_}})
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

dependent_built_in(#builtin_event{mfa = {erlang, A, _}},
                   #builtin_event{mfa = {erlang, B, _}})
  when (A =:= '!' orelse A =:= send orelse A =:= whereis orelse
        A =:= process_flag orelse A =:= link orelse A =:= unlink),
       (B =:= '!' orelse B =:= send orelse B =:= whereis orelse
        B =:= process_flag orelse B =:= link orelse B =:= unlink) ->
  false;

dependent_built_in(#builtin_event{mfa = {erlang,UnRegisterA,[AName|ARest]}},
                   #builtin_event{mfa = {erlang,UnRegisterB,[BName|BRest]}})
  when (UnRegisterA =:= register orelse UnRegisterA =:= unregister),
       (UnRegisterB =:= register orelse UnRegisterB =:= unregister) ->
  AName =:= BName
    orelse
      (ARest =/= [] andalso ARest =:= BRest);

dependent_built_in(#builtin_event{mfa = {erlang,SendOrWhereis,[SName|_]}},
                   #builtin_event{mfa = {erlang,UnRegisterOp,[RName|_]}})
  when (UnRegisterOp =:= register orelse UnRegisterOp =:= unregister),
       (SendOrWhereis =:= '!' orelse SendOrWhereis =:= send orelse
        SendOrWhereis =:= whereis) ->
  SName =:= RName;
dependent_built_in(#builtin_event{mfa = {erlang,UnRegisterOp,_}} = R,
                   #builtin_event{mfa = {erlang,SendOrWhereis,_}} = S)
  when (UnRegisterOp =:= register orelse UnRegisterOp =:= unregister),
       (SendOrWhereis =:= '!' orelse SendOrWhereis =:= send orelse
        SendOrWhereis =:= whereis) ->
  dependent_built_in(S, R);

dependent_built_in(#builtin_event{mfa = {ets,delete,[Table1]}},
                   #builtin_event{mfa = {ets,_Any,[Table2|_]}}) ->
  Table1 =:= Table2;
dependent_built_in(#builtin_event{mfa = {ets,_Any,_}} = EtsAny,
                   #builtin_event{mfa = {ets,delete,[_]}} = EtsDelete) ->
  dependent_built_in(EtsDelete, EtsAny);

dependent_built_in(#builtin_event{mfa = {ets,Insert1,[Table1,Tuples1]},
                                  result = Result1, extra = Tid},
                   #builtin_event{mfa = {ets,Insert2,[Table2,Tuples2]},
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

dependent_built_in(#builtin_event{mfa = {ets,lookup,_}},
                   #builtin_event{mfa = {ets,lookup,_}}) ->
  false;

dependent_built_in(#builtin_event{mfa = {ets,Insert,[Table1,Tuples]},
                                  result = Result, extra = Tid},
                   #builtin_event{mfa = {ets,lookup,[Table2,Key]}})
  when Insert =:= insert; Insert =:= insert_new ->
  case Table1 =:= Table2 andalso Result of
    false -> false;
    true ->
      KeyPos = ets:info(Tid, keypos),
      List = case is_list(Tuples) of true -> Tuples; false -> [Tuples] end,
      lists:keyfind(Key, KeyPos, List) =/= false
  end;
dependent_built_in(#builtin_event{mfa = {ets,lookup,_}} = EtsLookup,
                   #builtin_event{mfa = {ets,Insert,_}} = EtsInsert)
  when Insert =:= insert; Insert =:= insert_new ->
  dependent_built_in(EtsInsert, EtsLookup);

dependent_built_in(#builtin_event{mfa = {ets,new,_}, result = Table1},
                   #builtin_event{mfa = {ets,_Any,[Table2|_]}}) ->
  Table1 =:= Table2;
dependent_built_in(#builtin_event{mfa = {ets,_Any,_}} = EtsAny,
                   #builtin_event{mfa = {ets,new,_}} = EtsNew) ->
  dependent_built_in(EtsNew, EtsAny);

dependent_built_in(#builtin_event{mfa = {erlang,_,_}},
                   #builtin_event{mfa = {ets,_,_}}) ->
  false;
dependent_built_in(#builtin_event{mfa = {ets,_,_}} = Ets,
                   #builtin_event{mfa = {erlang,_,_}} = Erlang) ->
  dependent_built_in(Erlang, Ets);

dependent_built_in(#builtin_event{mfa = {M1,_,_}} = _MFA1,
                   #builtin_event{mfa = {M2,_,_}} = _MFA2) ->
  ?debug("UNSPECIFIED DEPENDENCY!\n~p\n~p\n", [_MFA1, _MFA2]),
  ?undefined_error,
  M1 =:= M2.

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

