.PHONY: test

test:
	./tests/syntax.sh
	./tests/cli.sh
	./tests/layout.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck bin/aws-metadata libexec/aws-metadata-server \
			libexec/aws-metadata-forwarder libexec/aws-metadata-network bootstrap.sh \
			install.sh uninstall.sh tests/syntax.sh tests/cli.sh tests/layout.sh \
			tests/fixtures/curl; \
	else \
		echo "shellcheck not installed; skipped"; \
	fi
