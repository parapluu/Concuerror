---
layout: page
title: "Concuerror's Homepage"
description: "Concuerror's Homepage"
updated: 2017-10-03
---

<h1 class="download-link"><a href="./download"><img src="./images/button.png" alt="Get Concuerror!"></a></h1>

What is Concuerror?
-------------------

Concuerror is a tool for systematically testing Erlang programs for concurrency errors. You can use it to detect errors that only occur on few, specific schedulings of your program or verify the absence of such errors.

How do I get it?
----------------

Concuerror's latest stable version is available on [Github](https://github.com/parapluu/Concuerror):

{% highlight bash %}
$ git clone https://github.com/parapluu/Concuerror.git
$ cd Concuerror
$ make -j
{% endhighlight %}

How do I use it?
----------------

All you have to do is specify the module and function you want to test:

<div style="text-align:center" markdown="1">
`concuerror -m my_module -t my_test`
</div>

How does it work?
-----------------

Concuerror schedules the Erlang processes spawned in the test as if a single scheduler was available.
During execution, the tool automatically instruments the modules used and intercepts and records calls to primitive Erlang operations that can behave differently depending on the scheduling (e.g., receive statements, registry operations, ETS operations).
It then analyzes the trace, detecting pairs of operations that are really racing.
Based on this analysis, it explores more schedulings, reversing the order of execution of such pairs. This is a procedure also known as _stateless model checking_.

How are errors shown?
---------------------

If a scheduling leads to a process crashing or deadlocking, Concuerror gives a detailed log of all the events that lead to the error.

How do I make testing more effective?
-------------------------------------

Concuerror prints hints and tips during its execution.
It may advice e.g. to refactor a test, if too many operations are racing.

A large number of options are also available.
You can find out more about them by running `concuerror -h`.

Read Further
------------

* [Tutorials](./tutorials)
* [FAQ](./faq)
* [Publications](./publications)

Latest News
-----------

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
