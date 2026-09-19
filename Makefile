# CleanJibe — one entry point per implementation.
#
# Every recipe here is a command that is already written down somewhere else: CLAUDE.md for
# the builds, web/README.md "Verification" for the site, garmin/tools/package.sh for the
# watch. This file adds no knowledge. It exists so a second machine, and one day a CI job,
# can run them without reading four documents first (docs/engineering.md, item 3).
#
#   make lab-test        the Python engine, which is the authoritative one
#   make kit-test        its Swift twin
#   make ios-build       the three channels from this one commit, no signing
#   make web-verify      the site: links, copy, voice, and a bundle that is not stale
#   make web-bundle      regenerate web/lab_bundle from lab/ after an engine change
#   make release-check   the version sites agree, and each channel is what it claims to be
#   make garmin-package  the three .iq files (needs the developer key, see below)
#   make all             everything a clean checkout can run unattended
#   make tag-ios         tag this commit ios/<version>-<build>, from ios/project.yml
#   make tag-garmin      tag this commit garmin/<version>, from garmin/manifest.xml
#   make tag-web         tag this commit web/<VERSION>, from web/sw.js
#
# make -n <target> prints the command without running it. That is the fastest way to see
# what a target really does.

SHELL := /bin/bash

.PHONY: all lab-test kit-test ios-build ios-project web-verify web-bundle release-check \
        garmin-package tag-ios tag-garmin tag-web help

# `all` is deliberately the set that needs nothing private. garmin-package is not in it:
# it signs with garmin/developer_key.der, which is Jan's and is not in the repo, so a
# clean checkout would fail on it through no fault of the checkout.
all: release-check lab-test kit-test web-verify ios-build

# ------------------------------------------------------------------- lab (authoritative)
# uv creates and syncs .venv itself on first run. ~1,000 tests, about a minute.
lab-test:
	cd lab && uv run pytest -q

# ------------------------------------------------------------------------------- the kit
# The Swift twin of the engine plus the presentation rules. No Xcode project needed.
kit-test:
	cd ios/WingFoilKit && swift test

# ------------------------------------------------------------------------------ the apps
# The project is generated, never committed: project.yml is the source of truth.
ios-project:
	cd ios && xcodegen generate

# Three channels from one commit (docs/channels.md). Signing is off because this target
# proves the code compiles, not that it can be shipped; shipping is testflight_publish.py.
ios-build: ios-project
	cd ios && xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Release" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
	cd ios && xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Beta" -configuration "Beta Debug" -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
	cd ios && xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Dev" -configuration "Dev Debug" -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# ------------------------------------------------------------------------------ the site
# Four checks, stdlib only, all of them instant. verify_links.py additionally runs
# make_start.py, make_devices.py, verify_copy.py, make_copy_js.py and verify_unique.py,
# so the four lines below are the eleven checks in web/README.md "Verification" minus the
# three that need the lab venv and a corpus (verify_web_entry, verify_library,
# verify_presentation — run those from lab/.venv/bin/python when the engine moves).
web-verify:
	python3 web/tools/bundle_lab.py --check
	python3 web/tools/verify_links.py
	python3 docs/copy/check_release_copy.py
	python3 docs/copy/check_voice.py
	python3 docs/copy/check_duplicates.py

# The browser runs lab/src/wingfoil_lab unchanged. This copies it and rewrites the two
# manifests. Run it in the same change as any engine edit, or web-verify fails.
web-bundle:
	python3 web/tools/bundle_lab.py

# --------------------------------------------------------------------------- the release
# The version is stamped in eight places across four implementations, and the four greps
# that prove a release binary carries no beta or dev door were prose in docs/testing.md.
# Both are this script now. It is stdlib-only and instant, so it is first in `all`: a
# disagreement here makes every test below it a test of the wrong thing.
#
# Add BINARY=<path to a built app's executable> to run the strings check over it too:
#     make release-check BINARY=ios/build/exportRelease/WingFoil.app/WingFoil
release-check:
	python3 tools/check_release.py $(if $(BINARY),--binary $(BINARY))

# ----------------------------------------------------------------------------- the watch
# release, beta and dev .iq from one manifest version, into garmin/bin/. Needs the CIQ SDK
# installed and garmin/developer_key.der present.
garmin-package:
	garmin/tools/package.sh

# ------------------------------------------------------------------------------- the tags
# One tag per shipped thing, so a store build maps to a commit (docs/engineering.md, "Tags").
# The version is read from the file that produced the build, never typed: ios/project.yml,
# garmin/manifest.xml, web/sw.js. Each target refuses on a dirty tree — a tag on a commit
# that is not what was uploaded is worse than no tag, because it will be believed.
#
# They create a local annotated tag and stop. Pushing is `git push origin <tag>`, and is
# Jan's to run, like every other push in this repo.
# The default is the shared marketing line every target but the release channel carries
# (0.15.0 today), because the build number is what identifies an upload and the release
# channel's own 1.0.x line is a store label. Pass VERSION= to tag a release-channel upload:
#     make tag-ios VERSION=1.0.0
tag-ios:
	@git diff --quiet && git diff --cached --quiet || { echo "refusing: the tree is dirty"; exit 1; }
	@v="$(VERSION)"; [ -n "$$v" ] || v=$$(grep -m1 -o 'MARKETING_VERSION: "[^"]*"' ios/project.yml | cut -d'"' -f2); \
	 b=$$(grep -m1 -o 'CURRENT_PROJECT_VERSION: "[^"]*"' ios/project.yml | cut -d'"' -f2); \
	 python3 tools/check_release.py >/dev/null && \
	 git tag -a "ios/$$v-$$b" -m "ios $$v build $$b" && echo "tagged ios/$$v-$$b (not pushed)"

tag-garmin:
	@git diff --quiet && git diff --cached --quiet || { echo "refusing: the tree is dirty"; exit 1; }
	@v=$$(grep -m1 -o 'version="[0-9][^"]*"' garmin/manifest.xml | cut -d'"' -f2); \
	 python3 tools/check_release.py >/dev/null && \
	 git tag -a "garmin/$$v" -m "watch app $$v" && echo "tagged garmin/$$v (not pushed)"

tag-web:
	@git diff --quiet && git diff --cached --quiet || { echo "refusing: the tree is dirty"; exit 1; }
	@v=$$(grep -m1 -o 'const VERSION = "v[0-9]*"' web/sw.js | cut -d'"' -f2); \
	 git tag -a "web/$$v" -m "site $$v" && echo "tagged web/$$v (not pushed)"

help:
	@grep -E '^#   make ' $(MAKEFILE_LIST) | sed 's/^#   //'
