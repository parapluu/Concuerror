---
layout: page
updated: 2020-11-07
description: "Homepage of the Concuerror, a tool for debugging, testing and verifying concurrent Erlang programs."
---

**Concuerror** is a **stateless model checking tool** for **Erlang**
programs.  It can be used to **detect** and **debug** concurrency
errors, such as **deadlocks** and errors due to **race conditions**.
Moreover it can **verify** the absence of such errors, because it
tests programs **systematically**, unlike techniques based on
randomness.

<div class="animated fadeInDown text-center" markdown="1">
  [Get Concuerror!](/download){: .btn .btn--success .btn--large }
</div>

## Latest News

[Read the latest news here](/news).

## How to use Concuerror?

[Read the basic tutorial here]({% post_url 2020-10-24-basic-tutorial %}).

## What are race conditions?

Concuerror's operation is based on detecting pairs of operations that
are racing, i.e. could have a different result if scheduled in the
opposite order.  You can see some of these pairs by using the
[`--show_races`
option](https://hexdocs.pm/concuerror/concuerror_options.html#show_races_option-0).

Remember, however, that not all race conditions are necessarily bad!
An example of benign racing is when worker processes report their
progress by sending messages to a work managing process.  These
messages are racing, as they may reach (and be received) by the
managing process in different orders.

Race conditions become can lead to errors when the program expects
certain events to occur in a particular order, but that order is not
always guaranteed.  Such errors are often hard to reproduce, when they
require rare, particular schedulings.

Concuerror systematically explores all "meaningfully different"
schedulings, detecting all such errors or verifying their absence.

## How does Concuerror work?

Concuerror schedules the Erlang processes spawned in the test as if
only a single scheduler was available.  During execution, the tool
records a trace of any calls to built-in operations that can behave
differently depending on the scheduling (e.g., receive statements,
registry operations, ETS operations).  It then analyzes the trace,
detecting pairs of operations that are really racing.  Based on this
analysis, it explores more schedulings, reversing the order of
execution of such pairs.  This is a technique known as _stateless
model checking with dynamic partial order reduction_.

[Read more details about how Concuerror works here](/faq/#how-does-concuerror-work-extended).
