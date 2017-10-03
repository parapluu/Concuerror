---
layout: page
title: "Concuerror's Homepage"
description: "Concuerror's Homepage"
updated: 2017-10-03
---

<h1 class="download-link"><a href="./download"><img src="./images/button.png" alt="Get Concuerror!"></a></h1>

## What is Concuerror?

Concuerror is a stateless model checking tool for Erlang programs. Such tools are used to systematically test programs for concurrency errors. You can use Concuerror to detect errors that only occur on few, specific schedulings of an Erlang program or **verify** the absence of such errors.

## How do I get Concuerror?

Concuerror's latest stable version is available on [Github](https://github.com/parapluu/Concuerror):

{% highlight bash %}
$ git clone https://github.com/parapluu/Concuerror.git
$ cd Concuerror
$ make -j
{% endhighlight %}

## How do I use Concuerror?

All you have to do is specify the module and function you want to test:

<div style="text-align:center" markdown="1">
`concuerror -m my_module -t my_test`
</div>

## ... is it really that simple?

Well, for most programs that is probably enough!
If your test is named `test` you can even skip the `-t test` option!
The tool automatically instruments any modules used in the test,
using Erlang's automatic code loading infrastructure,
so nothing more is in principle needed!

If a scheduling leads to one or more processes crashing or
deadlocking, Concuerror will print a detailed log of all the events
that lead to the error.

Otherwise it will keep exploring schedulings, [until it has checked them all...](/faq/#will-the-exploration-ever-finish)

## How do I report a bug?

The preferred way is in the repository's [Issues
page](https://github.com/parapluu/Concuerror/issues/new), but you can also [mail us](/contact).

## How does Concuerror work?

Concuerror schedules the Erlang processes spawned in the test as if a single scheduler was available.
During execution, the tool records calls to built-in operations that can behave differently depending on the scheduling (e.g., receive statements, registry operations, ETS operations).
It then analyzes the trace, detecting pairs of operations that are really racing.
Based on this analysis, it explores more schedulings, reversing the order of execution of such pairs. This is a technique known as _stateless model checking with partial order reduction_.

You can find more details [here](/faq/#how-does-concuerror-work-extended).

## Read Further

* [FAQ](./faq)
* [Tutorials](./tutorials)
* [Publications](./publications)

## Latest News

<ul class="post-list">
    {% for post in site.posts limit:10 %}
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
