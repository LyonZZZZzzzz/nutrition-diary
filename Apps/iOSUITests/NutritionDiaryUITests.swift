import XCTest

final class NutritionDiaryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-in-memory-store",
            "-appLanguagePreference", "zh-Hans"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["today.addFood"].waitForExistence(timeout: 30))
    }

    func testSearchEggRecordHouseholdPortionAndUpdateTodayTotal() {
        app.buttons["today.addFood"].tap()
        let search = app.textFields["addFood.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("鸡蛋")

        let eggID = "00000000-0000-0000-0000-000000000003"
        let egg = app.buttons["addFood.result.\(eggID)"]
        XCTAssertTrue(egg.waitForExistence(timeout: 10))
        app.staticTexts["鸡蛋"].tap()
        XCTAssertTrue(app.navigationBars["确认份量"].waitForExistence(timeout: 5))

        let householdPortion = app.buttons["addFood.quantityMode.portion"]
        XCTAssertTrue(householdPortion.waitForExistence(timeout: 5))
        householdPortion.tap()

        let energy = app.staticTexts["addFood.preview.energy_kcal"]
        scrollToElement(energy)
        XCTAssertTrue(energy.waitForExistence(timeout: 5))
        XCTAssertTrue(energy.label.contains("72"), "Expected 1 egg preview to round to 72 kcal, got \(energy.label)")

        let save = app.buttons["addFood.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let intake = app.descendants(matching: .any)["today.intakeCard"]
        XCTAssertTrue(intake.waitForExistence(timeout: 10))
        XCTAssertTrue(intake.label.contains("72"), "Expected today intake to contain 72 kcal, got \(intake.label)")
        XCTAssertTrue(app.staticTexts["鸡蛋"].waitForExistence(timeout: 5))
    }

    func testDragBreakfastEggToDinnerWithoutChangingIntake() {
        app.buttons["today.addFood"].tap()
        let search = app.textFields["addFood.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("鸡蛋")

        let egg = app.buttons["addFood.result.00000000-0000-0000-0000-000000000003"]
        XCTAssertTrue(egg.waitForExistence(timeout: 10))
        app.staticTexts["鸡蛋"].tap()
        XCTAssertTrue(app.navigationBars["确认份量"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addFood.save"].isEnabled)
        app.buttons["addFood.save"].tap()

        let intake = app.descendants(matching: .any)["today.intakeCard"]
        XCTAssertTrue(intake.waitForExistence(timeout: 10))
        let intakeBefore = intake.label

        let dinnerTitle = app.staticTexts["today.meal.title.dinner"]
        let dinnerDropTarget = app.descendants(matching: .any)["today.meal.dropHint.dinner"]
        scrollToHittable(dinnerDropTarget)
        let draggedFood = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.entry.")
        ).firstMatch
        XCTAssertTrue(draggedFood.waitForExistence(timeout: 5))
        XCTAssertTrue(draggedFood.isHittable)
        XCTAssertTrue(dinnerDropTarget.isHittable)

        draggedFood.press(
            forDuration: 1.2,
            thenDragTo: dinnerDropTarget,
            withVelocity: .slow,
            thenHoldForDuration: 0.5
        )

        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                draggedFood.exists && draggedFood.frame.minY > dinnerTitle.frame.minY
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed)
        let intakeAfter = app.descendants(matching: .any)["today.intakeCard"]
        scrollToTop(intakeAfter)
        XCTAssertTrue(intakeAfter.waitForExistence(timeout: 5))
        XCTAssertEqual(intakeAfter.label, intakeBefore)
    }

    func testNoResultsClearSearchAndInvalidPortionPreventsSave() {
        app.buttons["today.addFood"].tap()
        let search = app.textFields["addFood.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("ZZQX987654321")

        let noResults = app.descendants(matching: .any)["addFood.noResults"]
        XCTAssertTrue(noResults.waitForExistence(timeout: 10))

        app.buttons["addFood.clearSearch"].tap()
        XCTAssertTrue(noResults.waitForNonExistence(timeout: 10))
        let clearedValue = search.value as? String
        XCTAssertTrue(clearedValue == "" || clearedValue == "搜索食物、别名或菜品")

        search.tap()
        search.typeText("鸡蛋")
        let egg = app.buttons["addFood.result.00000000-0000-0000-0000-000000000003"]
        XCTAssertTrue(egg.waitForExistence(timeout: 10))
        app.staticTexts["鸡蛋"].tap()
        XCTAssertTrue(app.navigationBars["确认份量"].waitForExistence(timeout: 5))

        let amount = app.textFields["addFood.measuredAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("0")

        let invalidQuantity = app.descendants(matching: .any)["addFood.invalidQuantity"]
        scrollToElement(invalidQuantity)
        XCTAssertTrue(invalidQuantity.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addFood.save"].isEnabled)
    }

    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func scrollToTop(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeDown()
            swipes += 1
        }
    }


    func testMachineTranslatedFoodShowsLocalTranslationSource() {
        app.buttons["today.addFood"].tap()
        let search = app.textFields["addFood.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("双脆虾")

        let resultID = "25b037bb-d32f-5cb3-9704-ba68cd23891e"
        let result = app.buttons["addFood.result.\(resultID)"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        app.staticTexts["APPLEBEE'S，双脆虾"].tap()
        XCTAssertTrue(app.navigationBars["确认份量"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["中文名称来源"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["addFood.machineTranslationNote"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["英文原名"].exists)

        XCTAssertTrue(app.buttons["addFood.save"].isEnabled)
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["today.intakeCard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["APPLEBEE'S，双脆虾"].waitForExistence(timeout: 5))
    }


    func testFoodDataSourceShowsFullChineseCoverage() {
        app.tabBars.buttons["设置"].tap()
        let sourceLink = app.buttons["食物数据来源与许可证"]
        var swipes = 0
        while !sourceLink.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(sourceLink.isHittable)
        sourceLink.tap()
        XCTAssertTrue(app.navigationBars["食物数据来源"].waitForExistence(timeout: 5))
        let coverage = app.descendants(matching: .any)["foodData.chineseCoverage"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        XCTAssertTrue(coverage.label.contains("13,627 / 13,627"))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "full-chinese-coverage"
        attachment.lifetime = .keepAlways
        add(attachment)
    }


    func testStartupFailureShowsRecoveryScreen() {
        app.terminate()
        app.launchArguments = [
            "--ui-testing-in-memory-store",
            "--ui-testing-startup-failure",
            "-appLanguagePreference", "zh-Hans"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["启动失败"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["重试"].exists)
        XCTAssertTrue(app.buttons["重建本地数据库"].exists)
        let diagnostic = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Synthetic database startup failure")
        ).firstMatch
        XCTAssertTrue(diagnostic.exists)
    }

    func testPhotoFixtureConfirmsUploadAndRunsSecondPass() {
        relaunchForPhotoFixture(extraArguments: ["--ui-testing-photo-fixture"])
        app.buttons["photo.loadFixture"].tap()
        let analyze = app.buttons["photo.deepSeekAnalyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        analyze.tap()

        let consent = app.alerts["发送照片到 DeepSeek？"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.buttons["继续识别"].tap()

        if !app.navigationBars["确认识别结果"].waitForExistence(timeout: 10) {
            let alerts = app.alerts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | ")
            let texts = app.staticTexts.allElementsBoundByIndex.prefix(12).map { $0.label }.joined(separator: " | ")
            XCTFail("Photo review did not appear. Alerts: \(alerts). Texts: \(texts)")
            return
        }
        let passes = app.descendants(matching: .any)["photo.review.passes"]
        XCTAssertTrue(passes.waitForExistence(timeout: 5))
        XCTAssertTrue(passes.label.contains("2"))
        let dishLabel = app.descendants(matching: .any)["photo.review.dish.0"]
        scrollToElement(dishLabel)
        XCTAssertTrue(dishLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(dishLabel.label.contains("鱼香肉丝"))
        XCTAssertTrue(app.buttons["photo.review.confirm"].isEnabled)
    }

    func testPhotoFixtureLowConfidenceDoesNotAutoSelect() {
        relaunchForPhotoFixture(extraArguments: [
            "--ui-testing-photo-fixture",
            "--ui-testing-photo-low-confidence"
        ])
        app.buttons["photo.loadFixture"].tap()
        let analyze = app.buttons["photo.deepSeekAnalyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        analyze.tap()
        app.alerts["发送照片到 DeepSeek？"].buttons["继续识别"].tap()

        XCTAssertTrue(app.navigationBars["确认识别结果"].waitForExistence(timeout: 10))
        let manualCandidate = app.descendants(matching: .any)["photo.review.manualCandidate.0"]
        scrollToHittable(manualCandidate)
        XCTAssertTrue(manualCandidate.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["photo.review.confirm"].isEnabled)
    }

    private func relaunchForPhotoFixture(extraArguments: [String]) {
        app.terminate()
        app.launchArguments = [
            "--ui-testing-in-memory-store",
            "-appLanguagePreference", "zh-Hans",
            "--open-photo-tab"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["拍照记录"].waitForExistence(timeout: 30))
    }

    func testColdLaunchPerformance() {
        let performanceApp = XCUIApplication()
        performanceApp.launchArguments = [
            "--ui-testing-in-memory-store",
            "-appLanguagePreference", "zh-Hans"
        ]
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            performanceApp.terminate()
            performanceApp.launch()
        }
    }

    func testEnglishSearchFindsApple() {
        app.terminate()
        app.launchArguments = [
            "--ui-testing-in-memory-store",
            "-appLanguagePreference", "en"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["today.addFood"].waitForExistence(timeout: 30))
        app.buttons["today.addFood"].tap()

        let search = app.textFields["addFood.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("apple")

        let apple = app.buttons["addFood.result.00000000-0000-0000-0000-000000000017"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        XCTAssertTrue(apple.label.contains("Apple"))
    }
}
