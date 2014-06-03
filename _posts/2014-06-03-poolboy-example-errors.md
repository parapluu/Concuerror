---
layout: post
title: "Testing Poolboy, Part 2: Concuerror errors"
category: tutorials
---

We continue our tutorial on Concuerror, explaining the errors it can detect and
the options that you can use to filter out those that are not important for your
application.

Make sure that you have read the [first part]({% post_url 2014-06-02-poolboy-example %})!

{:.no_toc}
Index
-----
1. This text will be replaced by the ToC, excluding the previous header (WOW!)
{:toc}

Symbolic names
--------------

Concuerror makes an effort to replace every Erlang PID that appears in its
report with a symbolic name. The first process spawned is labelled `P` and
every other process is named after the process that spawned it, with an integer
denoting the order in which it was spawned i.e. `P`'s first "child" is named
`P.1`, `P.1`'s third child is named `P.1.3` and so on.

If you prefer to see the raw PIDs you can use
`--symbolic_names false`. Concuerror is reusing the same processes, so the
results should be consistent across different interleavings.

Abnormal exits
--------------

Every time a process exits abnormally, Concuerror will mark the interleaving as
erroneous. This means that any exception that escapes to the top-level will
trigger a warning. In our example processes `P`, `P.1.1` and `P.1.1.1` exited
abnormally.

{% highlight text %}
{% raw %}
Erroneous interleaving 1:
* At step 52 process P exited abnormally
    Reason:
      {timeout,{gen_server,call,[P.1,stop]}}
    Stacktrace:
      [{gen_server,call,2,[{file,"gen_server.erl"},{line,182}]},
       {poolboy_tests_1,pool_startup,0,
                        [{file,"poolboy_tests_1.erl"},{line,8}]}]
* At step 76 process P.1.1.1 exited abnormally
    Reason:
      shutdown
    Stacktrace:
      []
* At step 85 process P.1.1 exited abnormally
    Reason:
      shutdown
    Stacktrace:
      [{proc_lib,exit_p,2,[{file,"proc_lib.erl"},{line,260}]}]
{% endraw %}
{% endhighlight %}

### Ignoring high "after" timeouts

If we take a look at the trace we can see that `P` triggered the standard
timeout clause of any `gen` call:

{% highlight text %}
  50: P: receive timeout expired after 5000 ms
    in gen.erl line 213
  51: P: true = erlang:demonitor(#Ref<0.0.0.319>, [flush])
    in gen.erl line 223
  52: P: exits abnormally ({timeout,{gen_server,call,[P.1,stop]}})
{% endhighlight %}

As explained
[here](/faq/#how-does-concuerror-handle-timeouts-and-other-time-related-functions),
Concuerror by default assumes that any `receive` statement may trigger the
`after` clause, unless it is impossible for a matching message not to have
arrived.

However, let's assume that we don't care about such timeouts. We can use the
`--after_timeout 1000` to treat any timeout higher than 1000ms as
`infinity`. Notice that the one of the tips we got earlier suggests the same
course of action:

{% highlight text %}
Tip: A process crashed with reason '{timeout, ...}'. This may happen when a call
  to a gen_server (or similar) does not receive a reply within some standard
  timeout. Use the --after_timeout option to treat after clauses that exceed some
  threshold as 'impossible'.  
{% endhighlight %}

### Treating abnormal exit reasons as normal

The other two processes exited abnormally because they were terminated by the
`stop` message. Again, we may want to assume that this is acceptable behaviour
in our context: we can do so by using `--treat_as_normal shutdown` (also
suggested by a tip).

{% highlight text %}
Tip: A process crashed with reason 'shutdown'. This may happen when a supervisor
  is terminating its children. You can use --treat_as_normal shutdown if this is
  expected behavior.
{% endhighlight %}

A report without problems
-------------------------

Lets run Concuerror again, adding the new options.

{% highlight bash %}
poolboy $ concuerror -f poolboy_tests_1.erl -m poolboy_tests_1 -t pool_startup \
  --pa .eunit --after_timeout 1000 --treat_as_normal shutdown
{% endhighlight %}

This time the output finishes in:

{% highlight text %}
[...]
Done! (Exit status: completed)
  Summary: 0 errors, 96/96 interleavings explored
{% endhighlight %}

*In progress...*