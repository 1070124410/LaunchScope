.PHONY: build test install package clean

build:
	./scripts/build-app.sh

test:
	swift test

install: test build
	/usr/bin/ditto "dist/LaunchScope.app" "/Applications/LaunchScope.app"
	@echo "Installed /Applications/LaunchScope.app"

package: build
	./scripts/package-release.sh

clean:
	swift package clean
	rm -rf dist
