CONFIG ?= release
CODESIGN_ID ?= TinyWindow Dev

.PHONY: build app run test icons release doctor clean

build:
	swift build -c $(CONFIG)

app:
	CONFIG=$(CONFIG) CODESIGN_ID="$(CODESIGN_ID)" scripts/bundle.sh

run: app
	-killall TinyWindow 2>/dev/null || true
	open dist/TinyWindow.app

test:
	swift run tinywindow-checks

icons:
	swift scripts/gen-icon.swift
	scripts/make-icns.sh

release:
	scripts/release.sh

dmg:
	scripts/make-dmg.sh

doctor:
	@echo "swift:            $$(swift --version 2>&1 | head -1)"
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "$(CODESIGN_ID)"; then \
		echo "codesign identity: '$(CODESIGN_ID)' found — AX grant survives rebuilds"; \
	else \
		echo "codesign identity: MISSING ('$(CODESIGN_ID)') — ad-hoc fallback, AX grant resets each rebuild (see README)"; \
	fi
	@if pgrep -fq "Window Tidy.app"; then \
		echo "legacy Window Tidy: RUNNING — quit it before testing TinyWindow"; \
	else \
		echo "legacy Window Tidy: not running"; \
	fi

clean:
	rm -rf .build dist Support/AppIcon.icns
