.PHONY: test check-release stage-release release-assets

PYTHON ?= python3
BUMP ?= patch

test:
	$(PYTHON) scripts/check_release.py
	./tests/syntax.sh
	./tests/bootstrap.sh
	./tests/cli.sh
	./tests/layout.sh
	./tests/release-installer.sh
	./tests/release.sh
	./tests/pr-check-wait.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck bin/aws-metadata libexec/aws-metadata-server \
			libexec/aws-metadata-forwarder libexec/aws-metadata-network bootstrap.sh \
		install-release.sh install.sh uninstall.sh tests/syntax.sh tests/cli.sh \
		tests/bootstrap.sh tests/layout.sh tests/release-installer.sh tests/release.sh \
		tests/pr-check-wait.sh tests/fixtures/curl tests/fixtures/gh-pr-check \
		tests/fixtures/journalctl \
		scripts/build_release_assets.sh scripts/wait_for_pr_check.sh; \
	else \
		echo "shellcheck not installed; skipped"; \
	fi

check-release:
	$(PYTHON) scripts/check_release.py

stage-release:
	$(PYTHON) scripts/stage_release.py --bump $(BUMP)

release-assets:
	./scripts/build_release_assets.sh "v$$(cat VERSION)"
