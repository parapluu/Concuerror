.PHONY: default
default: build

JEKYLL = bundle exec jekyll
PROOFER = bundle exec htmlproofer ./_site

.PHONY: jekyll
jekyll: Gemfile
	bundle install

.PHONY: build
build: jekyll
	$(JEKYLL) build --config _config.yml,_config_local.yml

.PHONY: serve
serve: jekyll
	$(JEKYLL) serve --config _config.yml,_config_local.yml

.PHONY: test
test: build
	$(PROOFER) --disable_external \
	--check-favicon \
	--check-html \
	--check-opengraph

.PHONY: test-external
test-external: build
	$(PROOFER) --external-only

.PHONY: test-external-travis
test-external-travis: build
	$(PROOFER) --external-only \
		--url-ignore '/http://vimeo.com*/,/https://vimeo.com*/' \
		--http-status-ignore "302"
