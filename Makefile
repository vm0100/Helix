.PHONY: rust clean-rust build test project

rust:
	cd RustDiff && bash build.sh

clean-rust:
	cd RustDiff && cargo clean
	rm -f Sources/CHelixDiff/include/helix_diff.h

project: rust
	xcodegen generate

build: rust
	xcodebuild -project Helix.xcodeproj -scheme Helix -configuration Debug -derivedDataPath DerivedData build

test: rust
	swift test

clean: clean-rust
	rm -rf DerivedData .build
