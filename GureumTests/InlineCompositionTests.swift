//
//  InlineCompositionTests.swift
//  OSXTests
//
//  Unit tests for the pure composition-mode policy (`classifyComposition`).
//  These tests intentionally avoid IMK/AppKit and a live `IMKTextInput`
//  client; the policy is exercised through the `ClientCapabilities`
//  abstraction only.
//

@testable import GureumCore
import XCTest

/// `ClientCapabilities`의 테스트용 스텁. 각 질의 표면을 생성 시점에 고정한다.
private struct StubCaps: ClientCapabilities {
    let alwaysMarked: Bool
    let showsMarked: Bool?
    let selectableRange: Bool
    let bundleID: String?
    let forcedMarked: [String]
    let chromiumFramework: Bool

    init(alwaysMarked: Bool,
         showsMarked: Bool?,
         selectableRange: Bool,
         bundleID: String? = nil,
         forcedMarked: [String] = [],
         chromiumFramework: Bool = false)
    {
        self.alwaysMarked = alwaysMarked
        self.showsMarked = showsMarked
        self.selectableRange = selectableRange
        self.bundleID = bundleID
        self.forcedMarked = forcedMarked
        self.chromiumFramework = chromiumFramework
    }

    var alwaysMarkedGlobal: Bool { alwaysMarked }
    func showsComposingTextAsMarkedText() -> Bool? { showsMarked }
    func selectedRangeIsQueryable() -> Bool { selectableRange }
    var bundleIdentifier: String? { bundleID }
    var forcedMarkedBundleIDs: [String] { forcedMarked }
    func usesChromiumFrameworkTextStack() -> Bool { chromiumFramework }
}

class InlineCompositionTests: XCTestCase {
    func testAlwaysMarkedGlobalForcesMarked() {
        // 전역 강제 설정이 켜져 있으면 다른 필드와 무관하게 marked.
        let caps = StubCaps(alwaysMarked: true, showsMarked: false, selectableRange: true)
        XCTAssertEqual(classifyComposition(caps), .marked)
    }

    func testShowsMarkedTrueReturnsMarked() {
        let caps = StubCaps(alwaysMarked: false, showsMarked: true, selectableRange: true)
        XCTAssertEqual(classifyComposition(caps), .marked)
    }

    func testShowsMarkedFalseReturnsInline() {
        let caps = StubCaps(alwaysMarked: false, showsMarked: false, selectableRange: false)
        XCTAssertEqual(classifyComposition(caps), .inline)
    }

    func testUnknownShowsMarkedWithoutSelectableRangeReturnsMarked() {
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: false)
        XCTAssertEqual(classifyComposition(caps), .marked)
    }

    func testUnknownShowsMarkedWithSelectableRangeReturnsInline() {
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: true)
        XCTAssertEqual(classifyComposition(caps), .inline)
    }

    // MARK: - P2: pure engine/blocklist helpers (DKST port, MIT)

    func testWebKitTextStackMatchesSafariAndWebKitBundles() {
        XCTAssertTrue(bundleIdentifierUsesWebKitTextStack("com.apple.Safari"))
        XCTAssertTrue(bundleIdentifierUsesWebKitTextStack("com.apple.WebKit.WebContent"))
        XCTAssertTrue(bundleIdentifierUsesWebKitTextStack("com.apple.mobilesafari"))
        XCTAssertTrue(bundleIdentifierUsesWebKitTextStack("com.apple.Safari.Helper"))
        // prefix는 점 경계를 요구한다: "com.apple.WebKit"으로 시작해도 다음이 점이 아니면 불일치.
        XCTAssertFalse(bundleIdentifierUsesWebKitTextStack("com.apple.WebKitten"))
        XCTAssertFalse(bundleIdentifierUsesWebKitTextStack("com.google.Chrome"))
        XCTAssertFalse(bundleIdentifierUsesWebKitTextStack(""))
    }

    func testChromiumMarkedPolicyMatchesKnownBrowsers() {
        XCTAssertTrue(bundleIdentifierUsesChromiumMarkedTextPolicy("com.google.Chrome"))
        XCTAssertTrue(bundleIdentifierUsesChromiumMarkedTextPolicy("com.google.Chrome.canary"))
        XCTAssertTrue(bundleIdentifierUsesChromiumMarkedTextPolicy("com.microsoft.edgemac"))
        XCTAssertTrue(bundleIdentifierUsesChromiumMarkedTextPolicy("com.brave.Browser"))
        XCTAssertTrue(bundleIdentifierUsesChromiumMarkedTextPolicy("company.thebrowser.Browser")) // Arc
        XCTAssertTrue(bundleIdentifierUsesChromiumMarkedTextPolicy("com.naver.Whale"))
        XCTAssertTrue(bundleIdentifierUsesChromiumMarkedTextPolicy("org.chromium.Chromium"))
        XCTAssertFalse(bundleIdentifierUsesChromiumMarkedTextPolicy("com.apple.Safari"))
        XCTAssertFalse(bundleIdentifierUsesChromiumMarkedTextPolicy(""))
    }

    func testForcedMarkedListMatchesCaseInsensitively() {
        let list = ["com.acme.Editor", "net.example.App"]
        XCTAssertTrue(bundleIdentifierMatchesForcedMarkedList("com.acme.Editor", list))
        XCTAssertTrue(bundleIdentifierMatchesForcedMarkedList("com.acme.editor", list)) // 대소문자 무시
        XCTAssertFalse(bundleIdentifierMatchesForcedMarkedList("com.acme.Other", list))
        XCTAssertFalse(bundleIdentifierMatchesForcedMarkedList("com.acme.Editor", []))
        XCTAssertFalse(bundleIdentifierMatchesForcedMarkedList("", list))
    }

    // MARK: - P2: classifyComposition engine/blocklist branches

    func testForcedMarkedBundleIDForcesMarked() {
        // showsMarked nil + selectable true이면 기본은 inline이지만, 강제 목록에 있으면 marked.
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: true,
                            bundleID: "com.acme.Editor", forcedMarked: ["com.acme.Editor"])
        XCTAssertEqual(classifyComposition(caps), .marked)
    }

    func testForcedMarkedOverridesWebKitInline() {
        // WebKit 번들이라도 사용자 강제 목록에 있으면 marked가 이긴다(강제 목록이 WebKit보다 우선).
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: true,
                            bundleID: "com.apple.Safari", forcedMarked: ["com.apple.Safari"])
        XCTAssertEqual(classifyComposition(caps), .marked)
    }

    func testWebKitBundleReturnsInlineEvenWhenSelectedRangeUnqueryable() {
        // selectable=false면 기본 안전값은 marked지만, WebKit 판정이 그 앞 단계라 inline.
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: false,
                            bundleID: "com.apple.Safari")
        XCTAssertEqual(classifyComposition(caps), .inline)
    }

    func testChromiumBundleReturnsMarked() {
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: true,
                            bundleID: "com.google.Chrome")
        XCTAssertEqual(classifyComposition(caps), .marked)
    }

    func testChromiumFrameworkScanReturnsMarked() {
        // 번들 prefix 목록에 없는 Electron 앱이라도 프레임워크 스캔이 true면 marked.
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: true,
                            bundleID: "com.unknown.electronapp", chromiumFramework: true)
        XCTAssertEqual(classifyComposition(caps), .marked)
    }

    func testAppleMarkedSignalBeatsChromiumPolicy() {
        // Apple 신호(showsMarked=false=inline)는 Chromium 판정보다 우선한다(체인 2단계).
        let caps = StubCaps(alwaysMarked: false, showsMarked: false, selectableRange: true,
                            bundleID: "com.google.Chrome")
        XCTAssertEqual(classifyComposition(caps), .inline)
    }
}

/// 인라인 렌더(Step 8)를 mock 클라이언트로 검증하는 통합 테스트.
/// 기존 한글 테스트와 동일한 입력 패턴(`inputKeys`)을 재사용한다.
class InlineRenderTests: XCTestCase {
    let app = ModerateApp()
    private var savedInlineEnabled = false

    override class func setUp() {
        Configuration.shared = Configuration(suiteName: "org.youknowone.Gureum.test")!
        super.setUp()
    }

    override class func tearDown() {
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        // 공유 Configuration은 실제 UserDefaults suite를 변경하므로 이전 값을 저장한다.
        savedInlineEnabled = Configuration.shared.inlineCompositionEnabled

        Configuration.shared.removePersistentDomain(forName: GureumTests.domainName)

        app.client.string = ""
        // 두벌식: "dkssud" => ㅇ ㅏ ㄴ ㄴ ㅕ ㅇ => "안녕"
        app.controller.setValue(GureumInputSource.han2.rawValue, forTag: kTextServiceInputModePropertyTag, client: app.client)
    }

    override func tearDown() {
        // suite를 더럽힌 채로 두지 않는다.
        Configuration.shared.inlineCompositionEnabled = savedInlineEnabled
        Configuration.shared.inlineCompositionEnabled = false
        super.tearDown()
    }

    /// 인라인 모드: 키 입력마다 직접 insertText가 발생하고 marked text는 전혀 호출되지 않는다.
    func testInlineModeProducesDirectInsertionsNoMarkedText() {
        Configuration.shared.inlineCompositionEnabled = true
        // classifyComposition은 NSTextView mock을 .marked로 분류할 수 있으므로,
        // 타이핑 직전에 컨트롤러 인스턴스에 직접 강제한다.
        app.controller.useMarkedText = false
        app.client.resetRecordedInsertions()
        app.client.resetRecordedMarkedTexts()

        app.inputKeys("dkssud") // ㅇ ㅏ ㄴ ㄴ ㅕ ㅇ

        let insertions = app.client.recordedInsertions()
        let markedTexts = app.client.recordedMarkedTexts()

        // 참고용: 실제 (string, range) 시퀀스를 테스트 로그에 출력한다.
        print("InlineRenderTests insertions: \(insertions)")

        // range를 존중하는 클라이언트(MockInputClient)에 적용되면 문서는 "안녕"이 된다.
        XCTAssertEqual("안녕", app.client.string, "document text mismatch: \(app.client.string)")
        XCTAssertEqual(0, markedTexts.count, "inline mode must NOT call setMarkedText, got: \(markedTexts)")
        XCTAssertEqual(6, insertions.count, "expected exactly one insert per keystroke, got: \(insertions)")

        // 텍스트 스토리지와 독립적으로 IME가 내보낸 insert 시퀀스 자체를 검증한다.
        // 각 항목은 (삽입 문자열, replacementRange) 쌍이며 순서대로 일치해야 한다.
        let notFoundRange = NSStringFromRange(NSRange(location: NSNotFound, length: 0))
        let firstReplace = NSStringFromRange(NSRange(location: 0, length: 1))
        let secondReplace = NSStringFromRange(NSRange(location: 1, length: 1))
        let expected: [(String, String)] = [
            ("ㅇ", notFoundRange),
            ("아", firstReplace),
            ("안", firstReplace),
            ("안ㄴ", firstReplace),
            ("녀", secondReplace),
            ("녕", secondReplace),
        ]
        XCTAssertEqual(expected.count, insertions.count, "insert count mismatch: \(insertions)")
        for (index, pair) in expected.enumerated() where index < insertions.count {
            let entry = insertions[index]
            XCTAssertEqual(pair.0, entry["string"], "insert[\(index)] string mismatch: \(entry)")
            XCTAssertEqual(pair.1, entry["range"], "insert[\(index)] range mismatch: \(entry)")
        }
    }

    /// 인라인 조합 중 입력 모드 전환 시 진행 중인 음절이 중복되지 않아야 한다.
    /// (인라인으로 "안" 조합 → 모드 전환 → "안안" 회귀 방지)
    func testInlineModeChangeMidCompositionDoesNotDuplicate() {
        Configuration.shared.inlineCompositionEnabled = true
        app.controller.useMarkedText = false

        app.inputKeys("dks") // ㅇ ㅏ ㄴ => "안" (커밋하지 않음)
        XCTAssertEqual("안", app.client.string, "inline composition should leave 안 in the document, got: \(app.client.string)")

        // 다른 입력 모드로 전환하면 진행 중인 인라인 조합이 커밋된다.
        app.controller.setValue(GureumInputSource.qwerty.rawValue, forTag: kTextServiceInputModePropertyTag, client: app.client)

        XCTAssertEqual("안", app.client.string, "mode change mid-composition must not duplicate the syllable, got: \(app.client.string)")
    }

    /// 인라인 조합 중 강제 커밋(deactivateServer가 트리거하는 경로) 시 진행 중인
    /// 음절이 중복되지 않아야 한다. (인라인으로 "안" 조합 → 강제 커밋 → "안안" 회귀 방지)
    ///
    /// deactivateServer(_:)를 직접 호출하지 않는 이유: 그 오버라이드는 인라인 인지
    /// 커밋(commitComposition)을 수행한 뒤 라이브 IMK super.deactivateServer(_:)를
    /// 호출하는데, 이 super는 XCTest 환경에서 IMK 서버/클라이언트 래퍼가 완전히
    /// 구성되지 않아 EXC_BAD_ACCESS(0x8)로 크래시한다(testIPMDServerClientWrapper와
    /// 동일 근본 원인). 따라서 deactivateServer가 트리거하는 인라인 인지 커밋 경로
    /// 자체(commitComposition → receiver.commitCompositionEvent)를 직접 구동해
    /// 불변식을 검증한다. 운영 코드의 deactivateServer는 영향받지 않는다.
    func testInlineForcedCommitMidCompositionDoesNotDuplicate() {
        Configuration.shared.inlineCompositionEnabled = true
        app.controller.useMarkedText = false

        app.inputKeys("dks") // ㅇ ㅏ ㄴ => "안" (커밋하지 않음)
        XCTAssertEqual("안", app.client.string, "inline composition should leave 안 in the document, got: \(app.client.string)")

        // deactivateServer(_:)가 super 호출 직전에 수행하는 바로 그 커밋 경로.
        app.controller.commitComposition(app.client)

        XCTAssertEqual("안", app.client.string, "forced commit mid-composition must not duplicate the syllable, got: \(app.client.string)")
    }

    /// 킬스위치 OFF: marked 경로로 동작하며 인라인 결합 insert는 발생하지 않는다.
    func testKillSwitchOffFallsBackToMarkedPath() {
        Configuration.shared.inlineCompositionEnabled = false
        app.client.resetRecordedInsertions()
        app.client.resetRecordedMarkedTexts()

        app.inputKeys("dkssud") // ㅇ ㅏ ㄴ ㄴ ㅕ ㅇ

        let markedTexts = app.client.recordedMarkedTexts()
        let insertions = app.client.recordedInsertions()

        // marked 경로가 사용되었음이 핵심 불변식: setMarkedText가 호출되어야 한다.
        XCTAssertFalse(markedTexts.isEmpty, "marked path must run when kill-switch is OFF")

        // 인라인 경로가 동작하지 않았음을 결정적으로 확인한다: renderInline만이 만들어내는
        // (커밋+조합) 결합 insert("안ㄴ")가 절대 발생하지 않아야 한다. marked 경로는
        // 완성된 음절만 commit하므로 결합 문자열을 insertText로 내보내지 않는다.
        let combinedInlineStrings = insertions.compactMap { $0["string"] }
        XCTAssertFalse(combinedInlineStrings.contains("안ㄴ"),
                       "marked path must NOT emit the inline combined insert, got: \(insertions)")

        // 커밋 후 최종 문서 텍스트는 "안녕"으로 끝난다.
        app.inputKey(.space)
        XCTAssertTrue(app.client.string.hasSuffix("안녕"), "committed text should end with 안녕, got: \(app.client.string)")
    }
}
