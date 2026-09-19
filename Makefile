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
#   make garmin-package  the three .iq files (needs the developer key, see below)
#   make all             everything a clean checkout can run unattended
#
# make -n <target> prints the command without running it. That is the fastest way to see
# what a target really does.

SHELL := /bin/bash

.PHONY: all lab-test kit-test ios-build ios-project web-verify web-bundle garmin-package help

# `all` is deliberately the set that needs nothing private. garmin-package is not in it:
# it signs with garmin/developer_key.der, which is Jan's and is not in the repo, so a
# clean checkout would fail on it through no fault of the checkout.
all: lab-test kit-test web-verify ios-build

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

# The browser runs lab/src/wingfoil_lab unchanged. This copies it and rewrites the two
# manifests. Run it in the same change as any engine edit, or web-verify fails.
web-bundle:
	python3 web/tools/bundle_lab.py

# ----------------------------------------------------------------------------- the watch
# release, beta and dev .iq from one manifest version, into garmin/bin/. Needs the CIQ SDK
# installed and garmin/developer_key.der present.
garmin-package:
	garmin/tools/package.sh

help:
	@grep -E '^#   make ' $(MAKEFILE_LIST) | sed 's/^#   //'
