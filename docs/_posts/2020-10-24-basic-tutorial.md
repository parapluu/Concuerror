---
layout: post
category: tutorials
---

Before you launch Concuerror, you need a test that is **terminating**
(ideally in any scheduling of the processes) and **closed** (does not
require any inputs).

You should also keep in mind that systematic testing (unlike
stress-testing) does not encourage (or require) the use of too many
processes!  **All** schedulings of the test will be explored, so "the
simpler, the better"!

Once you have such a test, all you have to do is compile your code as
usual (preferably with `debug_info`) and then invoke Concuerror from
your shell, specifying the module and function that contains your
test:

{% highlight bash %}
$ concuerror -m my_module -t my_test
{% endhighlight %}

You can also invoke `concuerror:run/1` from an Erlang shell:

{% highlight erlang %}
1> concuerror:run([{module, my_module}, {test, my_test}]).
{% endhighlight %}

or:

{% highlight erlang %}
2> concuerror:run([{entry_point, {my_module, my_test, []}]).
{% endhighlight %}

The tool automatically instruments any modules used in the test, using
Erlang's automatic code loading infrastructure, so nothing more is in
principle needed!

Read the [FAQ](/faq) for more help.

## ... is it really that simple?

Well, for many programs that is probably enough!  If your test is
named `test` you can even skip the `-t` option!

If a scheduling leads to one or more processes crashing or
deadlocking, Concuerror will print a detailed trace of all the events
that lead to the error and by default stop the exploration.  You can
then use this trace to debug the detected error.

Otherwise it will keep exploring schedulings, until it has checked
them all. [Will the exploration ever
finish?](/faq/#will-the-exploration-ever-finish)

## Read more

A more detailed introductory tutorial, including sample code is
available [here](/tutorials/poolboy-example.html).

[Check out more tutorials here!](/tutorials)
