.PHONY: xcode build clean

xcode:
	xcodegen generate

build: xcode
	xcodebuild -scheme PRTGBar -configuration Release build

clean:
	rm -rf build/
	rm -rf DerivedData/
	rm -rf PRTGBar.xcodeproj
