[![Travis][travis badge]][travis]
[![Codecov][codecov badge]][codecov]
[![Erlang Versions][erlang versions badge]][travis]

# Concuerror

Concuerror is a stateless model checking tool for Erlang programs. It can be used to systematically test programs for concurrency errors, detect and report errors that only occur on few, specific schedulings or **verify** their absence.

[Visit the website][website] for documentation, examples, tutorials, publications, and many more!

## How to build

* Compile             : `make`
* Build documentation : `make edoc`
* Run the testsuites  : `make tests tests-real tests-unit`
* Run Dialyzer        : `make dialyzer`
* Run Elvis           : `make lint`
* Check code coverage : `make cover`
* Cleanup             : `make clean`

The preferred way to start concuerror is via the `bin/concuerror` escript.

## Using the bash_completion

You can optionally install concuerror's bash_completion file from https://github.com/parapluu/Concuerror/raw/master/resources/bash_completion/concuerror

To use it, you can either:

- Move the file to `/etc/bash_completion.d`
- Write `. /path-to-the-file`, if you want to use it only for the current shell session
- Edit your `.bashrc` file and add `[ -s "/path-to-the-file" ] && \. "/path-to-the-file"`

## Is there a changelog?

[Yes!][changelog]

## Copyright and License

Copyright (c) 2014-2020,
Stavros Aronis (<aronisstav@gmail.com>) and
Kostis Sagonas (<kostis@cs.ntua.gr>).
All rights reserved

Copyright (c) 2011-2013,
Alkis Gotovos (<el3ctrologos@hotmail.com>),
Maria Christakis (<mchrista@softlab.ntua.gr>) and
Kostis Sagonas (<kostis@cs.ntua.gr>).
All rights reserved.

Concuerror is distributed under the Simplified BSD License.
Details can be found in the [LICENSE][license] file.

<!-- Links -->
[changelog]: ./CHANGELOG.md
[codecov]: https://codecov.io/gh/parapluu/Concuerror
[license]: ./LICENSE
[travis]: https://travis-ci.org/parapluu/Concuerror
[website]: http://parapluu.github.io/Concuerror

<!-- Badges -->
[codecov badge]: https://codecov.io/gh/parapluu/Concuerror/branch/master/graph/badge.svg
[erlang versions badge]: https://img.shields.io/badge/erlang-R16B03%20to%2022.3-blue.svg
[travis badge]: https://travis-ci.org/parapluu/Concuerror.svg?branch=master
