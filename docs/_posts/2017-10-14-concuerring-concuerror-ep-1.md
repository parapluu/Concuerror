---
layout: post
title: "Concuerring Concuerror"
category: tutorials
redirect_from: /concuerring-concuerror-ep-1.html
---

### ... and some useful lessons for testing complex applications.

Developers learn the term 'heisenbug' when they run their concurrent
code and see it succeeding and failing 'randomly'. Concurrent
programming is hard and errors in concurrent programs are difficult to
trigger and debug. Changing the program makes the bug go away. Tools
that can detect such errors are complex, usually have limited
abilities and are difficult to use. Hope must be abandoned.

Concuerror, a stateless model checking tool capable of detecting
concurrency errors in Erlang programs, recently started showing
symptoms of suffering from a heisenbug itself. Some of the continuous
integration jobs on
[Travis CI](https://travis-ci.org/parapluu/Concuerror) would get stuck
and timeout due to inactivity
([here](https://travis-ci.org/parapluu/Concuerror/builds/286063501)
[are](https://travis-ci.org/parapluu/Concuerror/builds/286108892)
[a](https://travis-ci.org/parapluu/Concuerror/builds/286510470)
[few](https://travis-ci.org/parapluu/Concuerror/builds/286544528)).
Starting those jobs again would sometimes make them succeed. Other,
local runs of the test suite, would sometimes crash with Concuerror's
own timeout message ('a process did not respond...'). These crashes
would notably show up at different points within Concuerror's
exploration of program schedulings.

These are all symptoms of heisenbugs.

A fairly common challenge for a program whose input is some other
program (e.g. compilers, code analyzers, etc) is to run such program
with itself as input. Especially for analysis tools, such as
Concuerror, the goal is to assert that the program does not suffer
from the errors it can detect.

This is also known as
"[eating one's own dog food](https://en.wikipedia.org/wiki/Eating_your_own_dog_food)".

Could Concuerror find the concurrency bug it had? As its main
developer I wanted the answer to be an easy "yes". Sadly, the
complexity of the tool itself was initially too high for such a task.

Thus began project
[`dogfood`](https://github.com/aronisstav/Concuerror/tree/dogfood).
Concuerror should be able to analyze itself, either by supporting more
features or by not using them at all. As the 'Concuerror under test'
would still need an
[input](https://en.wikipedia.org/wiki/Turtles_all_the_way_down), the
simplest Erlang function was picked: `test() -> ok.`.

The stage was set for a (very nerdy) action film!

## Instrumentation and Code loading

One of Concuerror's most useful features is its ability to find source
code, instrument it, recompile and reload it on an Erlang VM
[in a totally automatic and seamless way](/tutorials/basic-tutorial.html/#-is-it-really-that-simple).
Doing this as part of a test, however, would require handling files
and this is a very hard task in stateless model checking. In Erlang,
this could entail unloads, resets and other similar horrors.

Fortunately, Concuerror lets programs communicate with existing
registered Erlang processes and allows them to read public ETS
tables. Concuerror is using such an ETS table to mark code that has
been already instrumented and loaded. By appending a run of the simple
test input before the run of 'Concuerror under test' on that input,
any code that needed instrumentation would be readily instrumented
when inspected by the inner Concuerror.

It is unclear how this trick can be generalized. Using files or ports
is still hard in code under stateless model checking.

## Unsupported operations

The next challenge was in the use of several Erlang builtin operations
whose handling has not yet been implemented in Concuerror. Examples
include operations that are
[fairly problematic to begin with (e.g. `os:timestamp`)](/faq/#limitations)
and others that are simply not yet implemented
(e.g. `ets:update_element`). Such operations were either simplified in
the tool or minimal support for them was added. The last approach was
easy, as Concuerror simulates very few parts of Erlang; letting the
tool 'just run' the operations (and consider them racing with
everything else) is a good first approximation.

## Full sequentialization

An early goal of the self-analysis was to assert that Concuerror would
be a fully sequential tool: only one process could run at anytime, a
constraint that could be enforced by synchronous requests between the
components of the application. This approach was abandoned early as
full sequentialization of the communication with the logger component
was deemed too silly.

Concurrent operations would instead be allowed, but any racing
operations would be eliminated.

## Looking at the magic

Once the first issues were handled, tests started showing a trace of
events before getting stuck here or crashing there. This was the first
time I saw how much is going on in a run of Concuerror. ETS tables
were written and read, messages and signals were flying. I was
dazzled.

A number of simplifications were done using this info. When the
analysis is over, processes can be
[gently signaled to exit](https://github.com/parapluu/Concuerror/commit/cd55afb)
(Concuerror used to kill them, something which is discouraged in
systematic testing, as such kill signals race with almost every other
operation). Some synchronization was
[added](https://github.com/parapluu/Concuerror/commit/c20def7) in
places where it would retain simplicity in the code.

## Improving the user experience

Eating one's own dog food reveals small frustrating details that can
ruin user experience. Badly formed options that are ignored. Unclear
messages to the user. Sanding those hard edges is trivial once they
are detected. Using the tool for real is the only way to do so.

## Simplifying the code

In the end, solving a tricky knot involving the marking of 'processes
under Concuerror' and the handling of `receive` statements split the
commit history of the 'dog food' branch into two parts:

* Before the
  [fix](https://github.com/parapluu/Concuerror/commit/c1c641e),
  Concuerror could not analyze itself: messages would be mysteriously
  lost between the outer and inner instances and the outer instance
  would get always stuck. This was not surprising: recursive use of
  the tool is (still) an esoteric endeavor and getting the
  instrumentation right is tricky.
* After the fix, Concuerror **could analyze itself!** However, the
  analysis would terminate after exploring just one scheduling, which
  was correct. No races existed.
  
Was it the case that the bug was still there, but could only be
triggered with more complex input? That's what I initially
thought. Stateless model checking is a very practical technique for
finding concurrency errors, but cannot cover all inputs of a program
under test.

The reason to believe that the bug had not been fixed was that the fix
was just preventing a send operation from being instrumented by moving
it elsewhere. To avoid introducing a race **due** to the movement,
another send operation was also moved. Their order remained the
same. Or so I thought.

## Fixing the bug

Concuerror instruments and reloads code in a way that is completely
transparent, unless a process has been 'marked' by the tool. Marked
processes mostly execute their original code, but wait for permission
from Concuerror's scheduler before performing any operations that
could be involved in races and also notify the scheduler about the
result of any such operation.

When a process under Concuerror receives a message, Concuerror's
instrumentation intercepts it and places it in a separate queue. This
is done because Concuerror's scheduler itself communicates with
processes via messages and this interception keeps channels of
communication clean.
 
When a process under Concuerror is about to execute a receive
statement, the instrumentation inspects the patterns, the existence of
an after clause and the messages in the queue. If a matching message
is found it's "sent again" (the first send in the story above), so
that the actual receive statement can then be executed, finding the
message in the mailbox. If no intercepted message matches but an after
statement should be executed, no message should be placed in the
mailbox.

In either case, the process would notify Concuerror's scheduler,
sending a message to it (the second send in the story above) *before*
executing the actual receive statement.

This opened up the possibility that the scheduler would send a message
of its own, asking for the next event, before the receive statement
was really executed. This was fine and well if a message was about to
be received (the message would already be in the mailbox), but if the
process was supposed to execute the after clause, it could
'accidentally' receive Concuerror's scheduler message.

The process might then crash. Or it might ignore the message and reach
the point before the next operation for which it would have to notify
the scheduler. It would then wait forever for the scheduler's message
(which was already accidentally consumed).

The scheduler would also either crash, blaming the process for not
responding within reasonable time to its request for a next event, or
wait forever (depending on the `--timeout` option used).

Having to do the possible "send again" as the absolutely last thing
(as this was the operation moved into uninstrumented code), forced the
notification to also be moved after the receive statement (with the
timeout) was completed. The scheduler's message could no longer be
lost. The test had only one interleaving.

The bug was fixed.

## ... and a philosophical question

In the version before the fix, Concuerror could **not** cleanly find
this bug, but was also prevented from running correctly: there was too
much instrumentation on the "sent again" handling of a message. After
a partial fix the bug could still not really be found: the `receive`
statement whose after clause was vulnerable would be uninstrumented
(all the inspection would have happened beforehand).

Yet, in the version after the fix, Concuerror did not have the bug.

So, at the end of the day, did Concuerror find the bug, or was it me?
:-)
