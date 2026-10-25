//
//  UITests.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2018-02-13.
//
//  ---------------------------------------------------------------------------
//
//  © 2018-2026 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest

@MainActor final class UITests: XCTestCase {
    
    override func setUp() async throws {
        
        try await super.setUp()
        
        // In UI tests it is usually best to stop immediately when a failure occurs.
        self.continueAfterFailure = false
    }
    
    
    func testTyping() {
        
        let app = XCUIApplication()
        app.launch()
        
        // open a new document
        let menuBarsQuery = app.menuBars
        menuBarsQuery.menuBarItems["File"].click()
        menuBarsQuery.menuItems["New Window"].click()
        
        // type some words
        let documentWindow = app.windows.firstMatch
        let textView = documentWindow.textViews.firstMatch
        _ = textView.waitForExistence(timeout: 5)
        textView.typeText("Test.\r")
        XCTAssertEqual(textView.value as! String, "Test.\n")
        
        // wait a bit to let document autosave
        sleep(1)
        
        // delete entire words
        for _ in 1...6 {
            textView.typeKey(.delete, modifierFlags: [])
        }
        
        let windowCountBeforeClose = app.windows.count
        // close window without saving
        documentWindow.buttons[XCUIIdentifierCloseWindow].click()
        if documentWindow.sheets.count > 0 {
            // it actually depends on user settings and iCloud availability if save sheet appears...
            documentWindow.sheets.firstMatch.children(matching: .button)["Delete"].click()
        }
        let fewerWindows = NSPredicate { _, _ in app.windows.count < windowCountBeforeClose }
        self.expectation(for: fewerWindows, evaluatedWith: nil)
        self.waitForExpectations(timeout: 5)
    }
    
    
    func testSettingsWindow() {
        
        let app = XCUIApplication()
        app.launch()
        
        // open the Settings window
        let menuBarsQuery = app.menuBars
        menuBarsQuery.menuBarItems["CotEditor"].click()
        menuBarsQuery.menuItems["Settings…"].click()
        
        // open all panes
        app.buttons["General"].firstMatch.click()
        app.buttons["Appearance"].firstMatch.click()
        app.buttons["Window"].firstMatch.click()
        app.buttons["Edit"].firstMatch.click()
        app.buttons["Mode"].firstMatch.click()
        app.buttons["Format"].firstMatch.click()
        app.buttons["Snippets"].firstMatch.click()
        app.buttons["Key Bindings"].firstMatch.click()
        app.buttons["Donation"].firstMatch.click()
    }
    
    
    func testLaunchPerformance() throws {
        
        // This measures how long it takes to launch your application.
        self.measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    
    func testSortIgnoringSurroundingWhitespace() throws {
        
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortWhitespace-\(UUID().uuidString).txt")
        let initial = "  zebra\t\napple\n"
        let sorted = "apple\n  zebra\t\n"
        try initial.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let app = XCUIApplication()
        app.launchArguments = ["-NSQuitAlwaysKeepsWindows", "NO"]
        app.launch()
        defer { app.terminate() }
        
        func openFixture() {
            app.typeKey("o", modifierFlags: .command)
            app.typeKey("g", modifierFlags: [.command, .shift])
            let pathField = app.textFields["PathTextField"].firstMatch
            XCTAssertTrue(pathField.waitForExistence(timeout: 10))
            pathField.click()
            pathField.typeKey("a", modifierFlags: .command)
            pathField.typeText(fileURL.path)
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(pathField.waitForNonExistence(timeout: 10))
            let openButton = app.buttons["OKButton"].firstMatch
            XCTAssertTrue(openButton.waitForExistence(timeout: 10))
            openButton.click()
        }
        
        openFixture()
        let title = fileURL.deletingPathExtension().lastPathComponent
        let window = app.windows.matching(NSPredicate(format: "title CONTAINS %@", title)).firstMatch
        let editor = window.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        XCTAssertEqual(editor.value as? String, initial)
        
        func sortDocument() {
            editor.click()
            editor.typeKey("a", modifierFlags: .command)
            app.activate()
            XCTAssertTrue(app.menuBars.firstMatch.waitForExistence(timeout: 5))
            // The Text menu can expose an empty accessibility title on newer macOS.
            app.menuBars.menuBarItems.containing(.menuItem, identifier: "Sort by Pattern…").firstMatch.click()
            app.menuBars.menuItems["Lines"].click()
            app.menuBars.menuItems["Sort by Pattern…"].click()
            let sheet = window.sheets.firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            let entireLine = sheet.radioButtons["Entire line"]
            entireLine.click()
            XCTAssertEqual(entireLine.value as? Int, 1)
            let toggle = sheet.checkBoxes["Ignore surrounding whitespace"]
            XCTAssertEqual(toggle.value as? Int, 0)
            // Changing the sort key animates the sheet height; wait for the control to settle.
            var lastFrame = toggle.frame
            var lastChange = Date()
            let settled = NSPredicate { _, _ in
                let frame = toggle.frame
                if frame != lastFrame { lastFrame = frame; lastChange = Date() }
                return Date().timeIntervalSince(lastChange) >= 0.5
            }
            self.expectation(for: settled, evaluatedWith: nil)
            self.waitForExpectations(timeout: 5)
            let optionsScreenshot = XCTAttachment(screenshot: sheet.screenshot())
            optionsScreenshot.name = "Sort options"
            optionsScreenshot.lifetime = .keepAlways
            self.add(optionsScreenshot)
            toggle.click()
            self.expectation(for: NSPredicate { _, _ in toggle.value as? Int == 1 }, evaluatedWith: nil)
            self.waitForExpectations(timeout: 5)
            let languageRules = sheet.checkBoxes["Respect language rules"]
            if languageRules.value as? Int == 1 { languageRules.click() }
            sheet.buttons["Sort"].click()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        }
        
        sortDocument()
        XCTAssertEqual(editor.value as? String, sorted)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, initial)
        sortDocument()
        XCTAssertEqual(editor.value as? String, sorted)
        app.typeKey("s", modifierFlags: .command)
        let persisted = NSPredicate { _, _ in
            (try? String(contentsOf: fileURL, encoding: .utf8)) == sorted
        }
        self.expectation(for: persisted, evaluatedWith: nil)
        self.waitForExpectations(timeout: 10)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data(sorted.utf8))
        
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Sorted document retains whitespace"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        
        app.terminate()
        app.launch()
        openFixture()
        let reopened = app.windows.matching(NSPredicate(format: "title CONTAINS %@", title)).firstMatch.textViews.firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 15))
        XCTAssertEqual(reopened.value as? String, sorted)
    }

}
