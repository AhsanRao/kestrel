.PHONY: build run test clean icon deps debug

build:
	./build.sh

debug:
	CONFIG=debug ./build.sh

run: build
	@pkill -x Kestrel 2>/dev/null || true
	open Kestrel.app

test:
	swift test

icon:
	./scripts/make-icon.sh

deps:
	./scripts/check-deps.sh

clean:
	rm -rf .build Kestrel.app assets/AppIcon.iconset assets/AppIcon.icns assets/MenuBarIcon.png
