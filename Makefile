OMNI_BLOG ?= ../omni/blog

.PHONY: setup sync build serve

setup:
	bundle config set --local path vendor/bundle
	bundle install

sync:
	ruby scripts/sync_omni_blog.rb "$(OMNI_BLOG)"

build: sync
	bundle exec jekyll build

serve: sync
	bundle exec jekyll serve --host 127.0.0.1 --port 4000 --livereload
