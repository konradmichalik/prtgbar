.PHONY: xcode build clean lint

xcode:
	xcodegen generate

build: xcode
	xcodebuild -scheme PRTGBar -configuration Release build

# Swift: SwiftLint (auto-detect Xcode for SourceKit)
lint:
	@if [ -z "$$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then \
		DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --strict; \
	else \
		swiftlint lint --strict; \
	fi

clean:
	rm -rf build/
	rm -rf DerivedData/
	rm -rf PRTGBar.xcodeproj
