---
layout: page
---

<h1 class="download-link"><a href="/download">Get Concuerror!</a></h1>

What is Concuerror?
-------------------

Concuerror is a tool for systematically testing concurrent Erlang programs. You can use it to detect errors that only occur on few, specific schedulings of your program or verify the absense of such errors.

Resources
---------

* [FAQ](/faq/)
* [Tutorials](/tutorials/)
* [Publications](/publications/)

Latest News
-----------

<ul class="post-list">
{% for post in site.posts limit:10 %} 
  <li><article><a href="{{ site.url }}{{ post.url }}">{{ post.title }}<span class="entry-date"><time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: "%B, %Y" }}</time></span></a></article></li>
{% endfor %}
</ul>
