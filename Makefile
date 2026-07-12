SHELL := /bin/zsh
PROJECT := TrackerCam.xcodeproj
SCHEME := TrackerCam
DERIVED_DATA := .build-xcode
XCODEBUILD := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild

.PHONY: validate-core validate-sim validate-app-tests validate-archive test profile-checklist generate

# Regenerate the Xcode project from project.yml. XcodeGen globs the filesystem, so a newly added
# source file does not compile until the project is regenerated — make the builds depend on this so
# a new file can never silently break the build (this exact drift broke the archive once).
generate:
	xcodegen generate

validate-core:
	TrackerCamCore/Scripts/verify.sh

validate-sim: generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

validate-app-tests: generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build-for-testing

# Run the TrackerCamTests suites on a named simulator (not just build-for-testing).
test: generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO test

validate-archive: generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO archive

profile-checklist:
	@sed -n '1,220p' DEVICE_PROFILING.md
