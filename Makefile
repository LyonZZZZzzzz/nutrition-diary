.PHONY: generate test test-ios-ui benchmark-catalog build-ios build-mac verify release-audit cloudkit-auth cloudkit-schema

generate:
	xcodegen generate

test:
	swift test --package-path Packages/NutritionKit
	python3 Scripts/verify_localizations.py
	python3 -m unittest Tools/test_build_food_catalog.py

benchmark-catalog:
	swift test --package-path Packages/NutritionKit --filter CatalogPerformanceTests

test-ios-ui: generate
	xcodebuild test -project NutritionDiary.xcodeproj -scheme NutritionDiary-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' CODE_SIGNING_ALLOWED=NO -only-testing:NutritionDiary-iOS-UITests -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 300

build-ios: generate
	xcodebuild -project NutritionDiary.xcodeproj -scheme NutritionDiary-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' CODE_SIGNING_ALLOWED=NO build

build-mac: generate
	xcodebuild -project NutritionDiary.xcodeproj -scheme NutritionDiary-macOS -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

archive-version:
	./Scripts/archive-version.sh

verify-release:
	./Scripts/archive-version.sh verify

verify: test test-ios-ui build-ios build-mac

release-audit:
	./Scripts/release-audit.sh

cloudkit-auth:
	./Scripts/cloudkit-schema.sh auth-management

cloudkit-schema:
	./Scripts/cloudkit-schema.sh export-development
	./Scripts/cloudkit-schema.sh validate-development
