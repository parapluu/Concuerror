Concuerror
==========

[![Build Status](https://travis-ci.org/parapluu/Concuerror.svg?branch=master)](https://travis-ci.org/parapluu/Concuerror)

Concuerror is a systematic testing tool for concurrent Erlang programs.

Copyright and License
----------------------
Copyright (c) 2011-2012,    
Alkis Gotovos (<el3ctrologos@hotmail.com>),    
Maria Christakis (<mchrista@softlab.ntua.gr>) and    
Kostis Sagonas (<kostis@cs.ntua.gr>).    
All rights reserved.

Concuerror is distributed under the Simplified BSD License.    
Details can be found in the LICENSE file.

Howto
------

* Build Concuerror   : `make`
* Run Concuerror     : `concuerror --help`
* Run testsuite      : `make THREADS=4 test`
* Dialyze            : `make dialyze`
* Cleanup            : `make clean`
