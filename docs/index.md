---
layout: page
updated: 2017-10-16
---

<div class="download-link">
<a href="./download"><img src="./images/button.png" alt="Get Concuerror!"></a>
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

Concuerror is a stateless model checking tool for Erlang programs. It can be used to systematically test programs for concurrency errors, detect and report errors that only occur on few, specific schedulings or **verify** their absence.

## How do I get Concuerror?

Read the [Download](/download) page.

## How do I use Concuerror?

First you need to come up with a test that is **terminating** (ideally in any scheduling of the processes) and **closed** (does not require any inputs).

Keep in mind that systematic testing (unlike stress-testing) does not encourage (or require) the use of a ton of processes! **All** schedulings of the test will be explored, so "the simpler, the better"!

Once you have such a test, all you have to do is compile your code and invoke Concuerror from your shell, specifying the module and function that contains your test:

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

## ... is it really that simple?

Well, for many programs that is probably enough!
If your test is named `test` you can even skip the `-t test` option!
The tool automatically instruments any modules used in the test,
using Erlang's automatic code loading infrastructure,
so nothing more is in principle needed!

If a scheduling leads to one or more processes crashing or
deadlocking, Concuerror will print a detailed log of all the events
that lead to the error and by default stop the exporation at that error.

Otherwise it will keep exploring schedulings, until it has checked them all. [Will the exploration ever finish?](/faq/#will-the-exploration-ever-finish)

## How does Concuerror work?

Concuerror schedules the Erlang processes spawned in the test as if only a single scheduler was available.
During execution, the tool records a trace of any calls to built-in operations that can behave differently depending on the scheduling (e.g., receive statements, registry operations, ETS operations).
It then analyzes the trace, detecting pairs of operations that are really racing.
Based on this analysis, it explores more schedulings, reversing the order of execution of such pairs. This is a technique known as _stateless model checking with dynamic partial order reduction_.

You can find more details [here](/faq/#how-does-concuerror-work-extended).

## Further Reads

* [News](/news)
* [Download](/download)
* [FAQ](/faq)
* [Mailing List](/mailing-list)
* [Tutorials](/tutorials)
* [Publications](/publications)
* [Contact](/contact)
