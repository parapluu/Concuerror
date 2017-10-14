---
layout: post
title: "Concuerring Concuerror"
---

### ... and some useful lessons for testing complex applications.

Developers learn the term 'heisenbug' when they run their concurrent
code and see it succeeding and failing 'randomly'. Concurrent
programming is hard and errors in concurrent programs are difficult to
trigger and debug. Changing the program makes the bug go away. Tools
that can detect such errors are complex, usually have limited
abilities and are difficult to use.

Concuerror, a stateless model checking tool capable of detecting
concurrency errors in Erlang programs, recently started showing
symptoms of suffering from a heisenbug itself. Some of the continuous
integration jobs on
[Travis CI](https://travis-ci.org/parapluu/Concuerror) would timeout
due to inactivity
([here](https://travis-ci.org/parapluu/Concuerror/builds/286063501)
[are](https://travis-ci.org/parapluu/Concuerror/builds/286108892)
[a](https://travis-ci.org/parapluu/Concuerror/builds/286510470)
[few](https://travis-ci.org/parapluu/Concuerror/builds/286544528)).
Starting those jobs again would sometimes make them succeed. Other,
local runs of the test suite, would sometimes crash with Concuerror's
own timeout message ('a process did not respond...'). These crashes
would notably show up on different points within Concuerror's
exploration of program schedulings.

These are both symptoms of heisenbugs.

A fairly common challenge for a program whose input is some other
program (e.g. compilers, code analyzers, etc) is to run such program
with themselves as inputs. Especially for analysis tools, such as
Concuerror, the goal is to assert that the program does not suffer
from the errors it can detect.

This is also known as
"[eating one's own dog food](https://en.wikipedia.org/wiki/Eating_your_own_dog_food)".

Could Concuerror find the concurrency bug it had? As its main
developer I wanted the answer to be an easy "yes". Sadly, the
complexity of the tool itself was initially too high for such a task.

Thus begun project
[`dogfood`](https://github.com/aronisstav/Concuerror/tree/dogfood). The
Concuerror under test would still need an input and the simplest
Erlang function was picked: `test() -> ok.`. Then begun the actual
problems...

## Instrumentation and Code loading

One of Concuerror's most useful features is its ability to find source
code, instrument it, recompile and reload it on an Erlang VM
[in a totally automatic and seamless way](/#-is-it-really-that-simple). Handling
files is however very hard in stateless model checking. In Erlang,
this could entail unloads, resets and other similar horrors.

Fortunately, Concuerror lets programs communicate with existing
registered Erlang processes and allows them to read public ETS
tables. Concuerror is using such an ETS table to mark code that has
been already instrumented and loaded. By appending a run of the simple
test input before the run of 'Concuerror under test' on that input,
any code that needed instrumentation would be readily instrumented
when inspected by the inner Concuerror.

It is unclear how this step can be generalized. Using files or ports
is still hard in code under stateless model checking.

## Unsupported operations

The next challenge was in the use of several Erlang builtin operations
whose handling has not yet been implemented in Concuerror. Examples
include operations that are
[fairly problematic to begin with (e.g. `os:timestamp`)](/faq/#limitations)
and others that are simply not yet implemented
(e.g. `ets:update_element`). Such operations were either simplified in
the tool or minimal support for them was added. The last approach was
easy as Concuerror tries to simulate as little parts of Erlang as
possible.

## Full sequentialization

An early goal of the self-analysis was to convert Concuerror into a
fully sequential tool: only one process could run at anytime, enforced
with synchronous message passing. This approach was abandoned early as
full sequentialization of the communication with the logger component
was deemed too silly.

Concurrent operations were allowed, but racing operations would still
be eliminated.

## Looking at the magic

Once the first issues were handled, tests started showing a trace of
events before getting stuck here or crashing there. This was the first
time I could see how much is going on in a run of Concuerror. ETS
tables were written and read, messages and signals were flying. I was
dazzled.

A number of simplifications were done using this info. At the end,
processes can be
[gently signaled to exit](https://github.com/parapluu/Concuerror/commit/cd55afb)
(Concuerror used to kill them, something which is discouraged in tests
as such kill signals race with almost every other operation). Some
synchronization was
[added](https://github.com/parapluu/Concuerror/commit/c20def7) in
places where it would retain simplicity in the code.

## Improving the user experience

Eating one's own dogfood reveals small frustrating details that can
ruin user experience. Badly formed options that are ignored. Unclear
messages to the user. Sanding those hard edges is trivial once they
are detected. Using the tool for real is the only way to do so.

## Simplifying the code

In the end solving a tricky knot involving the marking of 'processes
under Concuerror' and the handling of `receive` statements split the
commit history of the 'dog food' branch into two parts:

* Before the
  [fix](https://github.com/parapluu/Concuerror/commit/c1c641e),
  Concuerror could not analyze itself: messages would be mysteriously
  lost between the top and bottom instance and the analysis would get
  stuck. This was expected: recursive use of the tool is (still) an
  esoteric endeavor.
* After the fix, Concuerror with any simple input program would
  terminate correctly, showing no errors.
  
Was it the case that the bug was still there, but could only be
triggered with more complex input? That's what I initially
thought. Stateless model checking is practical, but does not cover all
inputs of a program.

The fix was just preventing a send operation from being instrumented
and moving it elsewhere. To avoid introducing a race **due** to the
movement, another send operation was also moved. Their order remained
the same. Or so I thought.

## Fixing the bug

When a process under Concuerror receives a message, Concuerror
intercepts it and places it in a queue maintained by itself. This is
done because Concuerror's scheduler itself communicates with processes
via messages and this interception keeps channels of communication
clean.
 
When a process under Concuerror is about to execute a receive
statement, the instrumentation inspects the patterns, the existence of
an after clause and the messages in the queue. If a matching message
is found it's "sent" again, for real, so that the actual receive
statement can be executed. If no intercepted message matches but an
after statement should be executed, no message should be placed in the
mailbox.

In either case, the process used to notify Concuerror's scheduler
*before* executing the actual receive statement. This opened up the
possibility that the scheduler would send to the process a message of
its own, asking for the next event, before the receive statement was
really executed.

This was fine and well if a message should be received (the message
would already be in the mailbox), but if the process was supposed to
execute the after clause, it could 'accidentally' receive Concuerror's
scheduler message.

The process might then crash. Or it might ignore the message and reach
the point before the next operation for which it would have to notify
the scheduler. It would then wait forever for the scheduler's prompt.

The scheduler would also either crash, blaming the process for not
responding within reasonable time to its request for a next event, or
wait forever.

Having to do the possible "send again" as the absolutely last thing,
forced the notification to be moved after the receive statement (with
the timeout) was completed. The scheduler's message could no longer be
lost. The test had only one interleaving.

The bug was fixed.

## ... and a philosophical question

In the version before the fix, Concuerror could not cleanly find this
bug, but was also prevented from running correctly: there was too much
instrumentation on the "actual delivery" of a message. After a partial
fix the bug could still not really be found: the `receive` statement
whose after clause was vulnerable would be uninstrumented (all the
inspection would have happened beforehand).

Yet, in the version after the fix, Concuerror did not have the bug.

Did Concuerror find the bug, or was it me? :-)
