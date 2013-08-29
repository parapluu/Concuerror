---
layout: page
permalink: /faq/index.html
---

# Frequently Asked Questions
{:.no_toc}

1. This text will be replaced by the ToC, excluding the previous header (WOW!)
{:toc}

## General

### What is Concuerror?

Concuerror is a testing tool for finding concurrency errors in Erlang programs or verifying their absence.

### How does Concuerror work?

Given a program and a test to run, Concuerror uses a stateless search algorithm to systematically explore the execution of the test under conceptually all process interleavings which are possible for the given program. To achieve this, the tool employs a source-to-source transformation that inserts instrumentation at preemption points (i.e. points where a context switch is allowed to occur) in the code under execution. This instrumentation allows Concuerror to take control of the scheduler when the program is run, and do so without having to modify the Erlang VM in any way. In the current VM, a context switch may occur at any function call. However, to avoid generating redundant interleaving sequences that lead to the same state, instrumentation in Concuerror inserts preemption points only at process actions that interact with (i.e. inspect or update) this shared state.

### What subset of Erlang does Concuerror support?

Concuerror supports the complete Erlang language and can instrument programs of any size. There are however certain limitations regarding [timeouts](#how-does-concuerror-handle-timeouts-and-other-time-related-functions) and [non-deterministic functions](#how-does-concuerror-handle-non-deterministic-functions)

## Limitations

### How does Concuerror handle timeouts and other time-related functions?

#### Timeouts

Timeouts may appear as part of an Erlang [`receive`](http://erlang.org/doc/reference_manual/expressions.html#id77242) statement or calls to [`erlang:send_after/3`](http://erlang.org/doc/man/erlang.html#send_after-3) and [`erlang:start_timer/3`](http://erlang.org/doc/man/erlang.html#start_timer-3). Due to the fact that Concuerror's instrumentation has an overhead on the execution time of the program, Concuerror normally disregards the actual timeout values and assumes:

* **For** `receive` **timeouts**:
 the `after` clause is always assumed to be possible to reach. Concuerror *will* explore interleavings that trigger the `after` clause, unless it is impossible for a matching message to not have arrived by the time the `receive` statement is reached.

* **For** `send_after`**-like timeouts**: (*Not yet implemented*) The timeout message may arrive at anytime until cancelled.

(*Not yet implemented*) Concuerror can be configured to treat timeouts in two additional ways:

* `--ignore-unless-deadlock N`: (*Preferred*) Timeouts higher than `N` are regarded as infinity, unless the process would block forever.
* `--ignore-timeout N`: Timeouts higher than `N` are regarded as infinity, unconditionally.

#### Time-related functions (E.g. `erlang:time/0`)

Concuerror handles such functions together with other [non-deterministic functions](#how-does-concuerror-handle-non-deterministic-functions).

### How does Concuerror handle non-deterministic functions?

(*Not yet implemented*) The first time Concuerror encounters a non-deterministic function it records the returned result. In every subsequent interleaving that is supposed to 'branch-out' *after* the point where the non-deterministic function was called, the recorded result will be supplied, to ensure consistent exploration of the interleavings.

This may result in unexpected effects, as for example measuring elapsed time by calling `erlang:time/0` twice may use a recorded result for the first call and an updated result for the second call (if it after the branching-out point), with the difference between the two increasing in every interleaving.