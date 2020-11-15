.PHONY: publish
publish: docs/index.html
	git checkout gh-pages
	git add docs -f
	git commit -m "auto build"
	git push origin gh-pages
docs/index.html: $(shell find . -name '*.md' -print)
	git checkout gh-pages
	mdnote build
	cp init.js docs/