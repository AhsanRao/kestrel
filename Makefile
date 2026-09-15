.PHONY: build run test clean icon deps debug

# Same SDK pin as build.sh, for `swift test`: the 27 SDK the Command Line Tools select cannot
# build SwiftUI without a macro plugin the tools do not ship.
SDK26 := /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
ifeq ($(origin SDKROOT), undefined)
ifneq ($(wildcard $(SDK26)),)
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
export SDKROOT := $(SDK26)
endif
endif
endif

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
