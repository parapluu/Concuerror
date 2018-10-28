---
layout: page
updated: 2018-10-28
title: "Concuerror Homepage"
description: "Homepage of the Concuerror, a tool for debugging, testing and verifying concurrent Erlang programs."
---

<div class="download-link">
<a href="./download"><img src="./images/get_concuerror_button.png" alt="Get Concuerror!"></a>
</div>

## Latest News

<ul class="post-list">
    {% for post in site.posts limit:3 %}
    <li>
    <article>
    <a href="{{ post.url }}">
        {{ post.title }}
        <span class="entry-date">
            <time datetime="{{ post.date | date_to_xmlschema }}">
                {{ post.date | date: "%B %d, %Y" }}
            </time>
        </span>
    </a>
    </article>
    </li>
    {% endfor %}
</ul>

[Read more news...](/news)

## What is Concuerror?

Concuerror is a stateless model checking tool for Erlang programs.
It can be used to detect and debug concurrency errors,
such as deadlocks and errors due to race conditions.
The key property of such errors is that
they only occur on few, specific schedulings of the program.
Moreover,
unlike tools based on randomisation,
Concuerror can **verify** the absence of such errors,
because it tests the program systematically.

## How can you get Concuerror?

Read the [Download](/download) page.

## How can you use Concuerror?

You might find one of the [Tutorials](/tutorials) useful!

In short, you need a test that is **terminating** (ideally in any scheduling of the processes) and **closed** (does not require any inputs).

Systematic testing (unlike stress-testing) does not encourage (or require) the use of too many processes!
**All** schedulings of the test will be explored, so "the simpler, the better"!

Once you have such a test,
all you have to do is compile your code as usual (preferably with `debug_info`)
and then invoke Concuerror from your shell,
specifying the module and function that contains your test:

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

The tool automatically instruments any modules used in the test,
using Erlang's automatic code loading infrastructure,
so nothing more is in principle needed!

Read the [FAQ](/faq) for more help.

## ... is it really that simple?

Well, for many programs that is probably enough!
If your test is named `test` you can even skip the `-t` option!

If a scheduling leads to one or more processes crashing or
deadlocking, Concuerror will print a detailed trace of all the events
that lead to the error and by default stop the exploration.
You can then use this trace to debug the detected error.

Otherwise it will keep exploring schedulings, until it has checked them all. [Will the exploration ever finish?](/faq/#will-the-exploration-ever-finish)

## What are race conditions?

Concuerror's operation is based on detecting pairs of operations that are racing,
i.e. could have a different result if scheduled in the opposite order.
You can see some of these pairs by using the [`--show_races` option](https://hexdocs.pm/concuerror/concuerror_options.html#show_races_option-0).

Remember, however, that not all race conditions are necessarily bad!
An example of benign racing
is when worker processes report their progress
by sending messages to a work managing process.
These messages are racing,
as they may reach (and be received) by the managing process in different orders.

Race conditions become can lead to errors
when the program expects certain events to occur in a particular order,
but that order is not always guaranteed.
Such errors are often hard to reproduce,
when they require rare, particular schedulings.

Concuerror systematically explores all "meaningfully different" schedulings,
detecting all such errors or verifying their absence.

## How does Concuerror work?

Concuerror schedules the Erlang processes spawned in the test as if only a single scheduler was available.
During execution, the tool records a trace of any calls to built-in operations that can behave differently depending on the scheduling (e.g., receive statements, registry operations, ETS operations).
It then analyzes the trace, detecting pairs of operations that are really racing.
Based on this analysis, it explores more schedulings, reversing the order of execution of such pairs. This is a technique known as _stateless model checking with dynamic partial order reduction_.

[More details about how Concuerror works](/faq/#how-does-concuerror-work-extended).

## Continue reading...

<ul style="list-style: none;">
  {% for link in site.links %}
    <li>
      <a href="{{ link.url }}">{{ link.title }}</a>
    </li>
  {% endfor %}
</ul>
