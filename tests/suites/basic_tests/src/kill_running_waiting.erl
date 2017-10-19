-module(kill_running_waiting).

-export([test/0]).
-export([scenarios/0]).

scenarios() ->
  [{test, inf, dpor}].

%% Sender can:
%% *  exit normally,
%% *  be killed after the message has been sent, or
%% *  be killed before the message has been sent.

%% Receiver can:
%% * exit normally, if Sender:
%%   - has also exited normally,
%%   - has been killed after the message has been sent
%% * killed after receiving the message in the same 2 cases.
%% * killed before receiving the message regardless of what Sender does.

%% This results in 7 distinct interleavings.

%% Due to how we compute dependencies, it is for the time being safer
%% to explore 2 more interleavings (9 in total), depending on whether
%% the Sender sends before or after Receiver is killed before
%% receiving the message (end either exits normally, or is killed
%% after the send).

%% In other words, the kill signal races with send operations, even
%% though the kill signal should really race only with the receive
%% operation in the receiver.

%% If kills and deliveries are independent, in an interleaving where
%% the send is completed but the receiver is killed when it could
%% receive, reversing the sender kill and the send gives an
%% interleaving where the receiver is killed **without** being able to
%% do a receive. This is not captured by the dependencies and suddenly
%% a 'runnable' process becomes 'blocked' and Concuerror crashes.

test() ->
  Receiver =
    spawn(fun() -> receive ok -> ok end end),
  Sender =
    spawn(fun() -> Receiver ! ok end),
  _KillReceiver =
    spawn(fun() -> exit(Receiver, abnormal) end),
  _KillSender =
    spawn(fun() -> exit(Sender, abnormal) end).
