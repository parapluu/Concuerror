---
layout: page
permalink: /faq/index.html
---

# Frequently Asked Questions
{:.no_toc}

1. This text will be replaced by the ToC, excluding the previous header (WOW!)
{:toc}

## General

### How does Concuerror work?

Concuerror begins by running the program under test in a controlled way so that
only one process runs at a time. During this run it logs any operations that
affect shared state, such as sending and delivery of messages, operations on ETS
tables etc. Afterwards it analyses this log, finding pairs of events that could
have different results if they were to happen in the reverse order (e.g. a
message being delivered before a receive statement triggers its after
clause). Finally it plans new runs of the test that will force this reverse
order for each such pair.

### How does Concuerror control the scheduling of processes?

Concuerror automatically adds instrumentation code and reloads any module that
is used by the test. It then forces any process involved in the test to stop and
report any operation that affects shared state.

### What subset of Erlang does Concuerror support?

Concuerror supports the complete Erlang language and can instrument programs of
any size. There are however certain limitations regarding
[timeouts](#how-does-concuerror-handle-timeouts-and-other-time-related-functions)
and [non-deterministic
functions](#how-does-concuerror-handle-non-deterministic-functions)

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
    anytime until cancelled.

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