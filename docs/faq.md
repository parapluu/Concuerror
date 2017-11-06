---
layout: page
permalink: /faq/index.html
title: "Concuerror's FAQ"
description: "Concuerror's Frequently Asked Questions"
updated: 2017-10-16
---

# Frequently Asked Questions
{:.no_toc}

1. This text will be replaced by the ToC, excluding the previous header (WOW!)
{:toc}

## How do I report a bug?

The preferred way is to use the repository's [Issues
page](https://github.com/parapluu/Concuerror/issues/new), but you can also [mail us](/contact).

## Will the exploration ever finish?

Complex concurrent programs can have a LOT of schedulings!  Concuerror
uses a technique called Optimal Dynamic Partial Order Reduction to
filter through them and has special knowledge about the interferences
of Erlang/OTP built-ins (see the relevant [Publications](/publications)).
Still, all this reduction power may sometimes not be enough.

If Concuerror keeps running for a while, you may want to limit the exploration
(using e.g. the `--interleaving_bound` option)
and visualize the explored schedulings
via the `--graph` option (the [dot](http://www.graphviz.org/) tool
is needed to produce an image).
You can then see which operations the tool considers as racing
using the `--show_races` option and possibly simplify the test.

Concuerror may also print tips during its execution,
suggesting ways to improve the effectiveness of testing.
A large number of options are available to fine tune the tool.
You can find out more about them by using `--help all`.

## Can Concuerror do 'random testing'?

A 'random testing' mode has not yet been implemented in Concuerror (add
your voice to the related
[Issue page](https://github.com/parapluu/Concuerror/issues/16)).

If your goal is not verification, Concuerror has its own way to sample
the interleavings in a less systematic way: schedule bounding. You can
read more about it by `--help bound`.

## How does Concuerror work? (extended)

Concuerror runs the program under test in a controlled way so that only one
process runs at a time.

1. It begins with an arbitrary initial run, during which it logs any operations
   that affect shared state, such as sending and delivery of messages,
   operations on ETS tables etc. The result is a sequence of such events, called
   an *interleaving*.
2. Afterwards it analyses this interleaving, finding pairs of events that could
   have different results if they were to happen in the reverse order (e.g. a
   message being delivered before the receiving process could have executed an
   after clause instead).
3. Then it "plans" new interleavings of the program that will force this reverse
   order for each such pair. Any such interleavings "replay" some events from
   the one currently analyzed up to some instruction and then diverge, in order
   to execute other events before those involved in a race.
4. Finally it checks for the "latest" place where it has made such a "plan",
   actually replays all events up to that point and continues as described in
   the plan. At some point in this new interleaving new behaviours may emerge.
5. It repeats this approach from step 2, until no other such plans remain.

This is a technique known as _stateless model checking with dynamic
partial order reduction_ ([read more](/publications)).

## How does Concuerror control the scheduling of processes?

Concuerror automatically adds instrumentation code and reloads any module that
is used by the test. The instrumentation forces any process involved in the test
to stop and report any operation that affects shared state.

## Does Concuerror support all of Erlang's operations/libraries?

Concuerror supports the complete Erlang language and can instrument programs of
any size. It can be the case that support for some built-in operations is not complete
but this is a matter of prioritization of tasks.
There are however certain limitations regarding e.g.
[timeouts](#how-does-concuerror-handle-timeouts-and-other-time-related-functions)
and [non-deterministic
functions](#how-does-concuerror-handle-non-deterministic-functions).

## How can I get rid of '...' in output files?

Use a higher `--print_depth`.

## Limitations

### How does Concuerror handle timeouts and other time-related functions?

#### Timeouts

Timeouts may appear as part of an Erlang
[`receive`](http://erlang.org/doc/reference_manual/expressions.html#id77242)
statement or calls to
[`erlang:send_after/3`](http://erlang.org/doc/man/erlang.html#send_after-3) and
[`erlang:start_timer/3`](http://erlang.org/doc/man/erlang.html#start_timer-3). Due
to the fact that Concuerror's instrumentation has an overhead on the execution
time of the program, Concuerror normally disregards the actual timeout values
and assumes:

* **For** `receive` **timeouts**: the `after` clause is always assumed to be
 possible to reach. Concuerror *will* explore interleavings that trigger the
 `after` clause, unless it is impossible for a matching message to not have
 arrived by the time the `receive` statement is reached.

* **For** `send_after`**-like timeouts**: The timeout message may arrive at
    anytime until canceled.

You can use `-- after-timeout N` to make Concuerror regard timeouts higher than
`N` as infinity.

#### Time-related functions (E.g. `erlang:time/0`)

Concuerror handles such functions together with other [non-deterministic
functions](#how-does-concuerror-handle-non-deterministic-functions).

### How does Concuerror handle non-deterministic functions?

The first time Concuerror encounters a non-deterministic function it records the
returned result. In every subsequent interleaving that is supposed to
'branch-out' *after* the point where the non-deterministic function was called,
the recorded result will be supplied, to ensure consistent exploration of the
interleavings.

This may result in unexpected effects, as for example measuring elapsed time by
calling `erlang:time/0` twice may use a recorded result for the first call and
an updated result for the second call (if it after the branching-out point),
with the difference between the two increasing in every interleaving.

### How does Concuerror handle NIFs?

Concuerror cannot intercept, instrument or perform race analysis in modules using NIFs and is very likely to crash if such modules are used. Better support may be included in the future.
