.PHONY: default
default: build

HTML_PROOOFER_OPTS = \
	--check-favicon \
	--check-html \
	--check-opengraph \
	--disable-external

Gemfile.lock: Gemfile
	bundle install
	touch $@

.PHONY: build
build: Gemfile.lock
	jekyll build

.PHONY: serve
serve: Gemfile.lock
	jekyll serve

.PHONY: test
test: build
	htmlproofer ./_site $(HTML_PROOOFER_OPTS)

.PHONY: test-external
test-external: build
	htmlproofer ./_site --external-only
