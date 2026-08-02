SHELL := /bin/bash

.PHONY: build dev start test check lint format package install release appcast power-check power-test-screen power-test-lid

build:
	swift build

dev start:
	./Scripts/compile_and_run.sh

test:
	swift test

check: format lint test

lint:
	./Scripts/lint.sh lint

format:
	./Scripts/lint.sh format

package:
	./Scripts/package_app.sh release

install:
	./Scripts/install_local.sh

release:
	./Scripts/sign-and-notarize.sh

appcast:
	./Scripts/make_appcast.sh $(ZIP)

power-check:
	./Scripts/check_power_state.sh

power-test-screen:
	./Scripts/power_test.sh screen

power-test-lid:
	./Scripts/power_test.sh lid
