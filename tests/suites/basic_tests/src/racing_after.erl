%% When a process under Concuerror receive a message, Concuerror
%% intercepts it and places it in a queue maintained by itself. This
%% is done because Concuerror's scheduler itself communicates with
%% processes via messages and this interception keeps channels of
%% communication clean.

%% When a process under Concuerror is about to execute a receive
%% statement, the instrumentation inspects the patterns, the existence
%% of an after clause and the messages in the queue. If a matching
%% message is found it's "sent" again, for real, so that the actual
%% receive statement can be executed. If no intercepted message
%% matches but an after statement can be executed, no message needs to
%% be placed in the mailbox.

%% In either case, the process used to notify Concuerror's scheduler
%% *before* executing the actual receive statement. This opened up the
%% possibility that the scheduler would send a message of its own
%% asking for the next event, before the receive statement was really
%% executed.

%% This was fine and well if a message could be received (the message
%% would already be in the queue so it would be received), but if the
%% process was supposed to execute the after clause, it could
%% 'accidentally' receive concuerror's scheduler message.

%% The process might crash. Or it might ignore the message and reach
%% the point before the next operation for which it would have to
%% notify the scheduler. It would then wait forever for scheduler's
%% prompt.

%% The scheduler would crash, blaming the process for not responding
%% within reasonable time to its request for a next event, or wait
%% forever.

%% The fix is to simply notify the scheduler after the receive
%% statement has been completed.

-module(racing_after).

-export([test/0]).
-export([scenarios/0]).

scenarios() ->
  [{test, inf, dpor}].

test() ->
  cleanup_mailbox().

cleanup_mailbox() ->
  receive
    _ -> cleanup_mailbox()
  after
    0 -> ok
  end.
