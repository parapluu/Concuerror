.PHONY: default
default: build

JEKYLL = bundle exec jekyll
PROOFER = bundle exec htmlproofer ./_site
CONFIG = --config _config.yml,_config_local.yml

.PHONY: jekyll
jekyll: Gemfile
	bundle install

.PHONY: build
build: jekyll
	$(JEKYLL) build $(CONFIG)

.PHONY: serve
serve: jekyll
	$(JEKYLL) serve $(CONFIG)

.PHONY: test
test: build
	$(PROOFER) --disable_external	--checks "Images,Links,Script,Favicon,OpenGraph"

.PHONY: test-external
test-external: build
	$(PROOFER) --external-only --http-status-ignore "302"
