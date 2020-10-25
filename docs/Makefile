.PHONY: default
default: build

HTML_PROOOFER_OPTS = \
	--check-favicon \
	--check-html \
	--check-opengraph \
	--disable-external

.PHONY: jekyll
jekyll: Gemfile
	bundle install

.PHONY: build
build: jekyll
	jekyll build --config _config.yml,_config_local.yml

.PHONY: serve
serve: jekyll
	jekyll serve --config _config.yml,_config_local.yml

.PHONY: test
test: build
	htmlproofer ./_site $(HTML_PROOOFER_OPTS)

.PHONY: test-external
test-external: build
	htmlproofer ./_site --external-only

.PHONY: test-external-travis
test-external-travis: build
	htmlproofer ./_site \
		--external-only \
		--url-ignore '/http://vimeo.com*/,/https://vimeo.com*/' \
		--http-status-ignore "302"
