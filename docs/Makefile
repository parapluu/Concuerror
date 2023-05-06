.PHONY: default
default: build

JEKYLL = bundle exec jekyll
PROOFER = bundle exec htmlproofer ./_site --checks "Images,Links,Script,Favicon,OpenGraph"

.PHONY: jekyll
jekyll: Gemfile
	bundle install

.PHONY: build
build: jekyll
	$(JEKYLL) build

.PHONY: serve
serve: jekyll
	$(JEKYLL) serve --config _config.yml,_config_local.yml

.PHONY: test
test: build
	$(PROOFER) --disable_external

.PHONY: test-external
test-external: build
	$(PROOFER) --ignore-status-codes "302"
