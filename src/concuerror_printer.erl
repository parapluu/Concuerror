%% -*- erlang-indent-level: 2 -*-

-module(concuerror_printer).

-export([error_s/1, pretty/2, pretty_s/1]).

-include("concuerror.hrl").

-spec error_s(concuerror_warning_info()) -> string().

error_s({Type, Info}) ->
  case Type of
    deadlock ->
      InfoStr =
        [io_lib:format("    ~p ~s~n", [P, location(F, L)]) ||
          {P, [L, {file, F}]} <- Info],
      Format =
        "* Blocked at a 'receive' (when all other processes have exited):~n~s",
      io_lib:format(Format, [InfoStr]);
    crash ->
      {Step, P, Reason, Stacktrace} = Info,
      S1 = io_lib:format("* At step ~w process ~p exited abnormally~n", [Step, P]),
      S2 = io_lib:format("    Reason:~n"
                         "      ~p~n", [Reason]),
      S3 = io_lib:format("    Stacktrace:~n"
                         "      ~p~n", [Stacktrace]),
      [S1,S2,S3];
    sleep_set_block ->
      io_lib:format("* Nobody woke-up: ~p~n", [Info])
  end.

-spec pretty(io:device(), event()) -> ok.

pretty(Output, I) ->
  _ = pretty_aux(I, {fun(P, A) -> io:format(Output, P ++ "~n", A) end, []}),
  ok.

-type indexed_event() :: {index(), event()}.

-spec pretty_s(event() | indexed_event() | [indexed_event()]) -> [string()].

pretty_s(I) ->
  {_, Acc} = pretty_aux(I, {fun io_lib:format/2, []}),
  lists:reverse(Acc).

pretty_aux({I, #event{} = Event}, {F, Acc}) ->
  #event{
     actor = Actor,
     event_info = EventInfo,
     location = Location
    } = Event,
  TraceString =
    case I =/= 0 of
      true -> io_lib:format("~4w: ", [I]);
      false -> ""
    end,
  ActorString =
    case Actor of
      P when is_pid(P) -> io_lib:format("~p: ",[P]);
      {_, _} -> ""
    end,
  EventString = pretty_info(EventInfo),
  LocationString =
    case Location of
      [Line, {file, File}] -> io_lib:format("~n    ~s",[location(File, Line)]);
      exit ->
        case EventInfo of
          #exit_event{} -> "";
          _Other -> io_lib:format("~n    (while exiting)", [])
        end;
      _ -> ""
    end,
  R = F("~s~s~s~s", [TraceString, ActorString, EventString, LocationString]),
  {F, [R|Acc]};
pretty_aux(#event{} = Event, FAcc) ->
  pretty_aux({0, Event}, FAcc);
pretty_aux(List, FAcc) when is_list(List) ->
  lists:foldl(fun pretty_aux/2, FAcc, List).

pretty_info(#builtin_event{mfa = {erlang, '!', [To, Msg]},
                           status = {crashed, Reason}}) ->
  io_lib:format("Exception ~w raised by: ~w ! ~w", [Reason, To, Msg]);
pretty_info(#builtin_event{mfa = {M, F, Args}, status = {crashed, Reason}}) ->
  ArgString = pretty_arg(Args),
  io_lib:format("Exception ~w raised by: ~p:~p(~s)",[Reason, M, F, ArgString]);
pretty_info(#builtin_event{mfa = {erlang, '!', [To, Msg]}, result = Result}) ->
  io_lib:format("~w = ~w ! ~w", [Result, To, Msg]);
pretty_info(#builtin_event{mfa = {M, F, Args}, result = Result}) ->
  ArgString = pretty_arg(Args),
  io_lib:format("~w = ~p:~p(~s)",[Result, M, F, ArgString]);
pretty_info(#exit_event{reason = Reason}) ->
  ReasonStr =
    case Reason =:= normal of
      true -> "normally";
      false -> io_lib:format("abnormally (~w)", [Reason])
    end,
  io_lib:format("exits ~s",[ReasonStr]);
pretty_info(#message_event{} = MessageEvent) ->
  #message_event{
     message = #message{data = Data},
     recipient = Recipient,
     sender = Sender,
     type = Type
    } = MessageEvent,
  MsgString =
    case Type of
      message -> io_lib:format("Message (~w)", [Data]);
      exit_signal ->
        {'EXIT', Sender, Reason} = Data,
        io_lib:format("Exit signal (~w)",[Reason])
    end,
  io_lib:format("~s from ~p reaches ~p", [MsgString, Sender, Recipient]);
pretty_info(#receive_event{message = Message, timeout = Timeout}) ->
  case Message of
    'after' ->
      io_lib:format("receive timeout expired after ~p ms", [Timeout]);
     #message{data = Data} ->
      io_lib:format("receives message (~p)", [Data])
  end.

pretty_arg(Args) ->
  pretty_arg(lists:reverse(Args), "").

pretty_arg([], Acc) -> Acc;
pretty_arg([Arg|Args], "") ->
  pretty_arg(Args, io_lib:format("~w",[Arg]));
pretty_arg([Arg|Args], Acc) ->
  pretty_arg(Args, io_lib:format("~w, ",[Arg]) ++ Acc).

location(F, L) ->
  Basename = filename:basename(F),
  io_lib:format("in ~s line ~w", [Basename, L]).
