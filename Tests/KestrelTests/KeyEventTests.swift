import CoreGraphics
import XCTest
@testable import Kestrel

final class KeyEventTests: XCTestCase {
    // MARK: - Parsing

    func testPlainKeys() {
        XCTAssertEqual(KeyChord("return")?.keyCode, 36)
        XCTAssertEqual(KeyChord("tab")?.keyCode, 48)
        XCTAssertEqual(KeyChord("escape")?.keyCode, 53)
        XCTAssertEqual(KeyChord("space")?.keyCode, 49)
        XCTAssertEqual(KeyChord("return")?.flags, CGEventFlags())
    }

    func testAliases() {
        XCTAssertEqual(KeyChord("enter")?.keyCode, KeyChord("return")?.keyCode)
        XCTAssertEqual(KeyChord("esc")?.keyCode, KeyChord("escape")?.keyCode)
        XCTAssertEqual(KeyChord("backspace")?.keyCode, 51)
        XCTAssertEqual(KeyChord("del")?.keyCode, 117)
        XCTAssertEqual(KeyChord("pgdn")?.keyCode, 121)
        XCTAssertEqual(KeyChord("arrowup")?.keyCode, 126)
    }

    func testChords() {
        let save = KeyChord("cmd+s")
        XCTAssertEqual(save?.keyCode, 1)
        XCTAssertEqual(save?.flags, .maskCommand)
        XCTAssertEqual(save?.display, "cmd+s")

        let palette = KeyChord("Cmd+Shift+P")
        XCTAssertEqual(palette?.keyCode, 35)
        XCTAssertEqual(palette?.flags, [.maskCommand, .maskShift])
    }

    func testSeparatorsAndGlyphs() {
        XCTAssertEqual(KeyChord("cmd shift p")?.keyCode, 35)
        XCTAssertEqual(KeyChord("⌘+s")?.flags, .maskCommand)
        XCTAssertEqual(KeyChord("option-left")?.flags, .maskAlternate)
    }

    func testNonsenseIsRefused() {
        XCTAssertNil(KeyChord("banana"))
        XCTAssertNil(KeyChord("cmd+"))
        XCTAssertNil(KeyChord(""))
        XCTAssertNil(KeyChord("cmd+nope"))
        XCTAssertNil(KeyChord("hyper+s"))
    }

    // MARK: - Irreversibility

    func testCommittingKeysAreIrreversible() {
        for raw in ["return", "enter", "delete", "backspace", "cmd+q", "cmd+w", "cmd+delete"] {
            XCTAssertTrue(KeyChord(raw)?.isIrreversible == true, "\(raw) should be confirmed")
        }
    }

    func testOrdinaryKeysAreNot() {
        for raw in ["cmd+s", "tab", "escape", "cmd+f", "down", "cmd+shift+p"] {
            XCTAssertFalse(KeyChord(raw)?.isIrreversible == true, "\(raw) should not be confirmed")
        }
        XCTAssertFalse(KeyChord.isIrreversible(nil))
        XCTAssertFalse(KeyChord.isIrreversible("banana"))
    }

    // MARK: - Typing

    func testChunkingKeepsEveryCharacter() {
        let text = String(repeating: "abcde ", count: 20)
        let chunks = KeyEvents.chunks(of: text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= KeyEvents.chunkSize })
    }

    func testChunkingNeverSplitsASurrogatePair() {
        let text = String(repeating: "😀", count: 30)
        let chunks = KeyEvents.chunks(of: text, size: 5)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count % 2 == 0 })
    }

    func testShortTextIsOneChunk() {
        XCTAssertEqual(KeyEvents.chunks(of: "hello"), ["hello"])
        XCTAssertEqual(KeyEvents.chunks(of: ""), [])
    }

}
