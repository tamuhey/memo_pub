.PHONY: publish
publish: docs/index.html
	git push origin gh-pages
docs/index.html:
	git checkout gh-pages
	mdnote build
	cp init.js docs/