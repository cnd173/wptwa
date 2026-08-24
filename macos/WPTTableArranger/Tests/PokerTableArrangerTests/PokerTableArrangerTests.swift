import XCTest
@testable import PokerTableArranger

final class PokerTableArrangerTests: XCTestCase {
    func testTargetClientMatchesOnlyExactSupportedBundleIdentifier() {
        XCTAssertTrue(TargetPokerClient.supports(bundleIdentifier: "com.wptglobal.wptg"))
        XCTAssertFalse(TargetPokerClient.supports(bundleIdentifier: "com.example.poker"))
        XCTAssertFalse(TargetPokerClient.supports(bundleIdentifier: "com.wptglobal.wptg.helper"))
        XCTAssertFalse(TargetPokerClient.supports(bundleIdentifier: nil))
    }

    func testWindowClassification() {
        XCTAssertEqual(
            WindowClassifier.classify(title: "HLB7110 - 0.05/0.10/0.20(0.05) - NLHE"),
            .table
        )
        XCTAssertEqual(WindowClassifier.classify(title: "Tournament - MTT"), .table)
        XCTAssertEqual(WindowClassifier.classify(title: "Hand History"), .history)
        XCTAssertEqual(WindowClassifier.classify(title: "15:13 Indochina Time"), .lobby)
        XCTAssertEqual(WindowClassifier.classify(title: "WPT Global"), .lobby)
        XCTAssertEqual(WindowClassifier.classify(title: "Cashier"), .ignored)
        XCTAssertEqual(WindowClassifier.classify(title: "Login verification"), .ignored)
        XCTAssertEqual(WindowClassifier.classify(title: "HL settings"), .ignored)
    }

    func testDefaultSlotsProduceThreeByTwoGrid() {
        let slots = defaultSlots(screenWidth: 1920, screenHeight: 1080)

        XCTAssertEqual(slots.count, 6)
        XCTAssertEqual(slots[0], Slot(id: 1, x: 0, y: 0, width: 640, height: 432))
        XCTAssertEqual(slots[2], Slot(id: 3, x: 1280, y: 0, width: 640, height: 432))
        XCTAssertEqual(slots[5], Slot(id: 6, x: 1280, y: 432, width: 640, height: 432))
    }

    func testCSVCodecRoundTripsEscapedValues() {
        let input = ["plain", "comma,value", "quote \"value\"", "two\nlines", ""]
        let encoded = CSVCodec.row(input)

        XCTAssertEqual(CSVCodec.parse(encoded + "\n"), [input])
    }

    func testSlotLayoutValidationNormalizesIDsAndRejectsInvalidDimensions() {
        let valid = [
            Slot(id: 90, x: -640, y: 0, width: 640, height: 432),
            Slot(id: 90, x: 0, y: 0, width: 640, height: 432),
        ]

        XCTAssertEqual(
            SlotLayoutValidator.normalized(valid),
            [
                Slot(id: 1, x: -640, y: 0, width: 640, height: 432),
                Slot(id: 2, x: 0, y: 0, width: 640, height: 432),
            ]
        )
        XCTAssertNil(SlotLayoutValidator.normalized([]))
        XCTAssertNil(SlotLayoutValidator.normalized([Slot(id: 1, x: 0, y: 0, width: 0, height: 432)]))
        XCTAssertNil(SlotLayoutValidator.normalized((1...(maxSlots + 1)).map {
            Slot(id: $0, x: 0, y: 0, width: 100, height: 100)
        }))
    }
}
