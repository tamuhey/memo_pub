.PHONY: publish
publish: docs/index.html
	git checkout gh-pages
	git add docs -f
	git push origin gh-pages
docs/index.html:
	git checkout gh-pages
	mdnote build
	cp init.js docs/