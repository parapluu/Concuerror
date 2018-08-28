.PHONY: default
default: build

Gemfile.lock: Gemfile
	bundle install
	touch $@

.PHONY: build
build:
	make -C .. edoc

.PHONY: test
test: build Gemfile.lock
	htmlproofer . --disable-external

.PHONY: clean
clean:
	$(RM) *_option.edoc *.html *.css erlang.png edoc-info Gemfile.lock
