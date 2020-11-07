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
	bundle exec htmlproofer . --disable-external --file_ignore "/vendor*/" --log_level debug

.PHONY: clean
clean:
	$(RM) *_option.edoc *.html *.css erlang.png edoc-info Gemfile.lock
