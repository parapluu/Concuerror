---
layout: page
permalink: /news/index.html
title: News
description: "An archive of all posts sorted by date."
---

# News

<ul class="post-list">
    {% for post in site.posts %}
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
