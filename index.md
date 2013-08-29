---
layout: page
---

What is Concuerror
==================

Concuerror is a tool for systematic testing of concurrent Erlang programs. You can read more in the [FAQ](/faq/) section.

Where can I get Concuerror
==========================

Concuerror's source code is available on [Github](https://github.com/mariachris/Concuerror). You can read more on the [Downloads](/download/) page.

Where to go from here?
======================

* You can take a look at some [tutorials](/tutorials/) regarding the use of Concuerror.
* You can find a list of all [publications](/publications/) regarding Concuerror


Latest News
===========

<ul class="post-list">
{% for post in site.posts limit:10 %} 
  <li><article><a href="{{ site.url }}{{ post.url }}">{{ post.title }} <span class="entry-date"><time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: "%B, %Y" }}</time></span></a></article></li>
{% endfor %}
</ul>
