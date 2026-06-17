SHELL := /bin/zsh
PROJECT := TrackerCam.xcodeproj
SCHEME := TrackerCam
DERIVED_DATA := .build-xcode
XCODEBUILD := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild

.PHONY: validate-core validate-sim validate-archive

validate-core:
	TrackerCamCore/Scripts/verify.sh

validate-sim:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

validate-archive:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO archive
