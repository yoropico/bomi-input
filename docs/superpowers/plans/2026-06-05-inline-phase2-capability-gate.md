# Inline PHASE 2 — Non-Invasive Capability Gate (③) + Cursor-Move Invalidation (②) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make inline direct-input robust enough to re-enable: auto-demote append-only apps (Word/Office/HWP) to marked text without a hand-maintained blocklist, and stop replacing at a stale location when the user moves the caret mid-composition.

**Architecture:** Two-layer capability gate. **A (seed list):** a pure classifier flags known append-only bundle IDs → marked from keystroke 1 (zero artifact). **B (runtime learning):** after the first real inline *replace*, validate via caret landing; on violation, demote the client to marked, remember its bundle ID in a session cache, best-effort clean the leak, and re-render the in-progress syllable as marked. **②:** track the expected caret after each inline render; if the caret moved unexpectedly before the next composition keystroke, drop the tracked range and re-anchor. All new logic stays behind the unchanged default-FALSE `inlineCompositionEnabled` kill-switch and is a strictly additive branch over the stable marked path.

**Tech Stack:** Swift + Objective-C, InputMethodKit, XCTest. Pure policy logic in `OSXCore/InlineComposition.swift`; IMK-backed adapter + state in `OSXCore/InputController.swift`; render/commit hot-path in `OSXCore/InputReceiver.swift`; test doubles in `GureumTests/`.

---

## File Structure

- `OSXCore/InlineComposition.swift` — add the pure `bundleIdentifierUsesAppendOnlyTextStack(_:)` classifier, add `learnedAppendOnly()` to the `ClientCapabilities` protocol (default-false), and wire both into `classifyComposition`. Stays IMK-free and unit-testable.
- `OSXCore/InputController.swift` — add `expectedCaret: Int?` controller state (for ②); add a session-scoped learned-append-only cache (static, like `chromiumDetectionCache`) with record/query/reset hooks; implement `LiveClientCapabilities.learnedAppendOnly()`; clear `expectedCaret` wherever `directRange` is cleared.
- `OSXCore/InputReceiver.swift` — extend `renderInline` with the post-write caret-landing validation + demote/learn/repair, and with `expectedCaret` tracking; add the ② `invalidateDirectRangeIfCursorMoved` helper and call it (gated to `action == .none`) before `renderInline`.
- `GureumTests/MockInputClient.h` / `.m` — add an `appendOnlyIgnoresReplacementRange` mode so a test client can simulate Word-style append-only behavior.
- `GureumTests/InlineCompositionTests.swift` — add the seed-list/learned unit tests (extend `StubCaps`) and the runtime demote + ② render tests (in `InlineRenderTests`).

**Test commands** (macOS, DEBUG; target `OSXTests`, scheme `OSX`):

- One class/test:
  ```bash
  xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
    -only-testing:OSXTests/InlineCompositionTests 2>&1 | tail -40
  ```
- Full inline suite (regression gate):
  ```bash
  xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
    -only-testing:OSXTests/InlineCompositionTests -only-testing:OSXTests/InlineRenderTests 2>&1 | tail -40
  ```

After every build, `OSX/Version.xcconfig` is dirtied — run `git checkout OSX/Version.xcconfig` before committing, and never `git add` it (see CLAUDE.md).

---

## Task 1: Seed-list classifier (A-layer, pure)

**Files:**
- Modify: `OSXCore/InlineComposition.swift` (add classifier after `bundleIdentifierUsesTerminalTextStack`, ~line 142; add a `classifyComposition` step after the terminal step, ~line 223)
- Test: `GureumTests/InlineCompositionTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these two methods to `class InlineCompositionTests` in `GureumTests/InlineCompositionTests.swift` (after `testTerminalTextStackMatchesKnownTerminals`):

```swift
    func testAppendOnlyTextStackMatchesOfficeAndHancom() {
        XCTAssertTrue(bundleIdentifierUsesAppendOnlyTextStack("com.microsoft.Word"))
        XCTAssertTrue(bundleIdentifierUsesAppendOnlyTextStack("com.microsoft.Excel"))
        XCTAssertTrue(bundleIdentifierUsesAppendOnlyTextStack("com.microsoft.Powerpoint"))
        XCTAssertTrue(bundleIdentifierUsesAppendOnlyTextStack("com.microsoft.Outlook"))
        XCTAssertTrue(bundleIdentifierUsesAppendOnlyTextStack("com.haansoft.hwp"))
        // 점 경계 prefix: 같은 vendor라도 다른 앱은 잡지 않는다.
        XCTAssertFalse(bundleIdentifierUsesAppendOnlyTextStack("com.microsoft.VSCode"))
        XCTAssertFalse(bundleIdentifierUsesAppendOnlyTextStack("com.apple.Safari"))
        XCTAssertFalse(bundleIdentifierUsesAppendOnlyTextStack(""))
    }

    func testAppendOnlySeedBundleReturnsMarked() {
        // showsMarked nil + selectable true이면 기본 inline이지만, 시드 목록이면 marked.
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: true,
                            bundleID: "com.microsoft.Word")
        XCTAssertEqual(classifyComposition(caps), .marked)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineCompositionTests 2>&1 | tail -40
```
Expected: COMPILE FAILURE — `cannot find 'bundleIdentifierUsesAppendOnlyTextStack' in scope`.

- [ ] **Step 3: Add the classifier**

In `OSXCore/InlineComposition.swift`, immediately after the `bundleIdentifierUsesTerminalTextStack(_:)` function (it ends near line 142), add:

```swift
/// 주어진 번들 식별자가 insertText의 replacementRange를 무시하고 append하는
/// "append-only" 텍스트 스택(MS Office/한글 등)인지 판정한다.
///
/// 이런 앱은 인라인 직접 입력의 제자리 치환을 무시해 조합 글자를 중복시키므로
/// 첫 키부터 marked로 강제한다. (PHASE 2 A층 시드 목록 — 알려진 앱 잔상 0 보장)
/// 번들 식별자는 best-known 값이며 온디바이스 매트릭스에서 실측 확인한다.
public func bundleIdentifierUsesAppendOnlyTextStack(_ bundleID: String) -> Bool {
    bundleIdentifier(bundleID, matchesAnyPrefix: [
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.microsoft.Powerpoint",
        "com.microsoft.Outlook",
        "com.microsoft.onenote.mac",
        "com.hancom.hoffice.hwp",
        "com.hancom.hwp",
        "com.haansoft.hwp",
    ])
}
```

- [ ] **Step 4: Wire it into `classifyComposition`**

In `OSXCore/InlineComposition.swift`, in `classifyComposition`, find the terminal step (step 6, ends near line 223 with its closing `}` after `return .marked`). Insert this block immediately after it, before the `// 7. selectedRange ...` block:

```swift
    // 6.5 append-only 시드 목록(MS Office/한글 등) → marked (A층). 알려진 앱은
    //     첫 키부터 marked라 인라인 잔상이 전혀 없다.
    if let bundleID = caps.bundleIdentifier,
       bundleIdentifierUsesAppendOnlyTextStack(bundleID)
    {
        return .marked
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineCompositionTests 2>&1 | tail -40
```
Expected: PASS (all InlineCompositionTests green, including the two new ones).

- [ ] **Step 6: Commit**

```bash
git checkout OSX/Version.xcconfig 2>/dev/null
git add OSXCore/InlineComposition.swift GureumTests/InlineCompositionTests.swift
git commit -m "feat(inline): PHASE 2 A-layer — seed-list classifier for append-only apps (Office/HWP) -> marked

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `learnedAppendOnly` capability (B-layer query, pure)

**Files:**
- Modify: `OSXCore/InlineComposition.swift` (protocol `ClientCapabilities` ~line 29; its default extension ~line 65; `classifyComposition` after the new 6.5 step)
- Modify: `GureumTests/InlineCompositionTests.swift` (extend `StubCaps`, add one test)

- [ ] **Step 1: Write the failing test**

In `GureumTests/InlineCompositionTests.swift`, first extend `StubCaps` so it can express the learned flag. Change its stored properties + initializer + protocol methods:

Add a stored property next to the others:
```swift
    let learnedAppend: Bool
```
Add an initializer parameter (after `chromiumFramework: Bool = false`, keep the default so existing call sites compile):
```swift
         learnedAppend: Bool = false)
```
Assign it in the init body (next to `self.chromiumFramework = chromiumFramework`):
```swift
        self.learnedAppend = learnedAppend
```
Add the protocol method (next to `usesChromiumFrameworkTextStack`):
```swift
    func learnedAppendOnly() -> Bool { learnedAppend }
```

Then add this test method to `class InlineCompositionTests`:
```swift
    func testLearnedAppendOnlyReturnsMarked() {
        // 런타임 학습으로 append-only로 판명된 클라이언트는 시드 목록에 없어도 marked.
        let caps = StubCaps(alwaysMarked: false, showsMarked: nil, selectableRange: true,
                            bundleID: "com.unknown.editor", learnedAppend: true)
        XCTAssertEqual(classifyComposition(caps), .marked)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineCompositionTests/testLearnedAppendOnlyReturnsMarked 2>&1 | tail -40
```
Expected: FAIL — `classifyComposition` returns `.inline` (the learned branch does not exist yet), assertion fails.

- [ ] **Step 3: Add the protocol method + default**

In `OSXCore/InlineComposition.swift`, in the `public protocol ClientCapabilities` body (after `func usesChromiumFrameworkTextStack() -> Bool`), add:

```swift
    /// 런타임 학습 결과: 이 클라이언트가 (사후 caret 검증으로) append-only로 판명됐는지.
    /// 라이브 어댑터는 번들 식별자별 학습 캐시를 조회한다. (PHASE 2 B층)
    func learnedAppendOnly() -> Bool
```

In the `public extension ClientCapabilities` block (where `usesChromiumFrameworkTextStack` has its default), add:

```swift
    /// 기본값: 학습된 바 없음. (P1 스텁/구형 conformer 호환)
    func learnedAppendOnly() -> Bool { false }
```

- [ ] **Step 4: Wire it into `classifyComposition`**

In `OSXCore/InlineComposition.swift`, in `classifyComposition`, immediately after the `// 6.5 append-only 시드 목록 ...` block added in Task 1, add:

```swift
    // 6.6 런타임 학습으로 append-only로 판명된 클라이언트 → marked (B층). 시드에
    //     없던 미지의 앱을 1회 학습 후 영구(세션) marked로 유지한다.
    if caps.learnedAppendOnly() {
        return .marked
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineCompositionTests 2>&1 | tail -40
```
Expected: PASS (all InlineCompositionTests green).

- [ ] **Step 6: Commit**

```bash
git checkout OSX/Version.xcconfig 2>/dev/null
git add OSXCore/InlineComposition.swift GureumTests/InlineCompositionTests.swift
git commit -m "feat(inline): PHASE 2 B-layer — learnedAppendOnly capability + classify step

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Controller state — `expectedCaret` + learned-append cache

**Files:**
- Modify: `OSXCore/InputController.swift` (class state ~line 60; static cache near `chromiumDetectionCache` ~line 228; `LiveClientCapabilities.learnedAppendOnly()`; clear sites in `deactivateServer` ~line 416 and `cancelComposition` ~line 460; `MockInputController.cancelComposition` ~line 566)
- Modify: `OSXCore/InputReceiver.swift` (`setValue` mode-change clear site ~line 364)
- Test: `GureumTests/InlineCompositionTests.swift` (add a cache mechanics test to `InlineRenderTests`)

- [ ] **Step 1: Write the failing test**

In `GureumTests/InlineCompositionTests.swift`, add this test to `class InlineRenderTests`:

```swift
    func testLearnedAppendOnlyCacheRecordsAndResets() {
        InputController.resetLearnedAppendOnlyCache()
        XCTAssertFalse(InputController.isLearnedAppendOnly(bundleID: "com.test.x"))
        InputController.recordLearnedAppendOnly(bundleID: "com.test.x")
        XCTAssertTrue(InputController.isLearnedAppendOnly(bundleID: "com.test.x"))
        // 빈 번들 식별자는 기록하지 않는다.
        InputController.recordLearnedAppendOnly(bundleID: "")
        XCTAssertFalse(InputController.isLearnedAppendOnly(bundleID: ""))
        InputController.resetLearnedAppendOnlyCache()
        XCTAssertFalse(InputController.isLearnedAppendOnly(bundleID: "com.test.x"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineRenderTests/testLearnedAppendOnlyCacheRecordsAndResets 2>&1 | tail -40
```
Expected: COMPILE FAILURE — `type 'InputController' has no member 'resetLearnedAppendOnlyCache'`.

- [ ] **Step 3: Add controller state + cache + clear sites**

In `OSXCore/InputController.swift`, in the `class InputController`, add `expectedCaret` next to `directText`/`useMarkedText` (after the `var useMarkedText = true` line ~66):

```swift
    /// 직전 인라인 렌더 직후의 기대 caret(selectedRange.location), 즉 directRange의 끝.
    /// ② 커서이동 무효화가 사용한다. nil = 추적 안 함.
    var expectedCaret: Int?
```

Still in `class InputController`, add the learned-append cache (place it right before the closing `}` of the class, after the `directRangeIsCurrent(...)` method ~line 73):

```swift
    // MARK: - PHASE 2 B층: 런타임 append-only 학습 캐시 (세션 한정)

    /// 사후 검증에서 append-only로 판명된 클라이언트의 번들 식별자 집합. IMK 이벤트는
    /// 메인 스레드에서만 처리되므로 별도 동기화 없이 안전하다. 프로세스 생명주기 한정
    /// (영구화는 후속 과제).
    private static var learnedAppendOnlyCache: Set<String> = []

    /// 사후 검증에서 append-only로 판명된 클라이언트를 기록한다(빈 식별자는 무시).
    static func recordLearnedAppendOnly(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        learnedAppendOnlyCache.insert(bundleID)
    }

    /// 주어진 번들 식별자가 append-only로 학습됐는지.
    static func isLearnedAppendOnly(bundleID: String) -> Bool {
        learnedAppendOnlyCache.contains(bundleID)
    }

    /// 테스트 격리용: 학습 캐시를 비운다.
    static func resetLearnedAppendOnlyCache() {
        learnedAppendOnlyCache.removeAll()
    }
```

In `LiveClientCapabilities` (same file), add the method (next to `usesChromiumFrameworkTextStack`, ~line 205):

```swift
    /// 런타임 학습 캐시에서 이 클라이언트(번들 식별자)가 append-only로 판명됐는지 조회.
    func learnedAppendOnly() -> Bool {
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty else {
            return false
        }
        return InputController.isLearnedAppendOnly(bundleID: bundleID)
    }
```

In `deactivateServer(_:)` (the `directRange = nil` / `directText = ""` block ~line 416), add:
```swift
        expectedCaret = nil
```

In `cancelComposition()` (the `directRange = nil` / `directText = ""` block ~line 460), add:
```swift
        expectedCaret = nil
```

In `MockInputController.cancelComposition()` (the `directRange = nil` / `directText = ""` block ~line 569), add `expectedCaret = nil` in the same style as those two surrounding lines (they run on `self` — `MockInputController` IS an `InputController` — so NO `controller.` prefix here):
```swift
            expectedCaret = nil
```

In `OSXCore/InputReceiver.swift`, in `setValue(...)`, the input-mode-change block clears tracking (`controller.directRange = nil` / `controller.directText = ""` ~line 364). Add:
```swift
                controller.expectedCaret = nil
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineRenderTests/testLearnedAppendOnlyCacheRecordsAndResets 2>&1 | tail -40
```
Expected: PASS.

- [ ] **Step 5: Run the full inline suite (no regressions)**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineCompositionTests -only-testing:OSXTests/InlineRenderTests 2>&1 | tail -40
```
Expected: PASS (all green; `expectedCaret` is written-but-not-yet-read, so behavior is unchanged).

- [ ] **Step 6: Commit**

```bash
git checkout OSX/Version.xcconfig 2>/dev/null
git add OSXCore/InputController.swift OSXCore/InputReceiver.swift GureumTests/InlineCompositionTests.swift
git commit -m "feat(inline): PHASE 2 — controller expectedCaret state + session learned-append cache

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Append-only test client mode (test infra)

**Files:**
- Modify: `GureumTests/MockInputClient.h` (add a property)
- Modify: `GureumTests/MockInputClient.m` (honor it in `insertText:replacementRange:`)
- Test: `GureumTests/InlineCompositionTests.swift` (sanity test in `InlineRenderTests`)

- [ ] **Step 1: Write the failing test**

In `GureumTests/InlineCompositionTests.swift`, add this test to `class InlineRenderTests`:

```swift
    func testAppendOnlyClientIgnoresReplacementRange() {
        let client = MockInputClient()
        client.string = "ㅇ"
        client.setSelectedRange(NSRange(location: 1, length: 0))
        client.appendOnlyIgnoresReplacementRange = true
        // 제자리 치환을 요청해도 무시하고 끝에 append해야 한다(Word 모사).
        client.insertText("아", replacementRange: NSRange(location: 0, length: 1))
        XCTAssertEqual("ㅇ아", client.string, "append-only client must append, not replace: \(client.string)")
        XCTAssertEqual(2, client.selectedRange().location, "caret must land after the appended text")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineRenderTests/testAppendOnlyClientIgnoresReplacementRange 2>&1 | tail -40
```
Expected: COMPILE FAILURE — `value of type 'MockInputClient' has no member 'appendOnlyIgnoresReplacementRange'`.

- [ ] **Step 3: Add the property + behavior**

In `GureumTests/MockInputClient.h`, inside the `@interface` (after the recording method declarations, before `@end`), add:

```objc
// When YES, insertText:replacementRange: IGNORES replacementRange and always appends
// at the end of the document (simulating append-only apps like MS Word that ignore the
// replacement range). Only affects the inline path (no active marked region). Used to
// test PHASE 2 runtime learning. Default NO.
@property (nonatomic, assign) BOOL appendOnlyIgnoresReplacementRange;
```

In `GureumTests/MockInputClient.m`, in `-insertText:replacementRange:`, insert this block immediately after the `addObject:@{...}` recording block and BEFORE the `if ([self hasMarkedText])` block:

```objc
    // PHASE 2 테스트용 append-only 모사: replacementRange를 무시하고 문서 끝에 append한다.
    // marked region이 없는 인라인 경로에서만 동작한다(marked 경로는 기존 동작 유지).
    if (self.appendOnlyIgnoresReplacementRange && ![self hasMarkedText]) {
        NSString *appended = [string isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)string string] : string;
        appended = appended ?: @"";
        NSRange end = NSMakeRange(self.textStorage.length, 0);
        [self.textStorage replaceCharactersInRange:end withString:appended];
        [self setSelectedRange:NSMakeRange(self.textStorage.length, 0)];
        return;
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineRenderTests/testAppendOnlyClientIgnoresReplacementRange 2>&1 | tail -40
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git checkout OSX/Version.xcconfig 2>/dev/null
git add GureumTests/MockInputClient.h GureumTests/MockInputClient.m GureumTests/InlineCompositionTests.swift
git commit -m "test(inline): MockInputClient append-only mode (simulate Word ignoring replacementRange)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `renderInline` post-write validation → demote / learn / repair

**Files:**
- Modify: `OSXCore/InputReceiver.swift` (rewrite `renderInline` ~lines 141-189; add two private helpers after it)
- Test: `GureumTests/InlineCompositionTests.swift` (add demote test + reset cache in `InlineRenderTests.setUp`/`tearDown`)

- [ ] **Step 1: Add cache reset to test lifecycle, then write the failing test**

First, make `InlineRenderTests` isolate the static learned cache. In `GureumTests/InlineCompositionTests.swift`, in `class InlineRenderTests`:

In `override func setUp()`, add as the first line of the body (before `super.setUp()` is fine, but place it right after `super.setUp()`):
```swift
        InputController.resetLearnedAppendOnlyCache()
```
In `override func tearDown()`, add before `super.tearDown()`:
```swift
        InputController.resetLearnedAppendOnlyCache()
```

Then add this test to `class InlineRenderTests`:

```swift
    func testInlineDemotesToMarkedWhenClientAppendsIgnoringRange() {
        Configuration.shared.inlineCompositionEnabled = true
        app.controller.useMarkedText = false
        app.client.appendOnlyIgnoresReplacementRange = true
        app.client.resetRecordedMarkedTexts()

        // "dk" = ㅇ 그리고 ㅏ. 둘째 키가 첫 글자를 제자리 치환하려 하지만 append-only
        // 클라이언트가 무시하고 append → caret 착지 검증이 위반을 감지한다.
        app.inputKeys("dk")

        XCTAssertTrue(app.controller.useMarkedText,
                      "append-only client must be demoted to marked after the violating replace")
        let bundleID = app.client.bundleIdentifier() ?? ""
        XCTAssertTrue(InputController.isLearnedAppendOnly(bundleID: bundleID),
                      "violating client's bundle id must be learned")
        XCTAssertFalse(app.client.recordedMarkedTexts().isEmpty,
                       "demote must re-render the in-progress composition as marked text")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineRenderTests/testInlineDemotesToMarkedWhenClientAppendsIgnoringRange 2>&1 | tail -40
```
Expected: FAIL — `app.controller.useMarkedText` is still `false` (no validation/demote yet); the first assertion fails.

- [ ] **Step 3: Rewrite `renderInline` with validation + add helpers**

In `OSXCore/InputReceiver.swift`, replace the entire `private func renderInline(_ sender:...)` function (currently ~lines 141-189) with:

```swift
    /// 인라인(직접 입력) 렌더링: 커밋 문자열과 조합 중인 문자열을 합쳐 단 한 번의
    /// insertText로 문서에 반영하고, 조합 중인 문자가 차지하는 범위(directRange)를
    /// 갱신한다. PHASE 2: 실제 치환 직후 caret 착지를 검증해 append-only 클라이언트를
    /// marked로 강등·학습한다. (DKST 스타일 포팅, MIT)
    private func renderInline(_ sender: IMKTextInput & IMKUnicodeTextInput) {
        let commitString = composer.dequeueCommitString()
        let composedString = _internalComposedString
        let combined = commitString + composedString

        // 직전 조합 문자열이 자리하던 범위를 찾아 대체 대상으로 삼는다.
        let replaceRange = (controller.directRange != nil)
            ? inlineReplaceRange(controller.directText, dr: controller.directRange!, client: sender)
            : NSRange(location: NSNotFound, length: 0)

        // ① fail-safe (PHASE 1): 추적 중이던 directRange의 위치를 잃었고(replaceRange ==
        // NSNotFound: 검증·backtrack 모두 실패) 새로 조합할 글자가 없으면(composedString
        // empty = 커밋/종료) combined은 이미 인라인으로 들어가 있는 글자(directText)의
        // 마무리일 뿐이다. 위치를 못 찾는 상태에서 append하면 중복되므로(예: "안녕" →
        // "안녕녕") 삽입을 건너뛰고 추적만 비운다.
        if controller.directRange != nil, replaceRange.location == NSNotFound, composedString.isEmpty {
            controller.directRange = nil
            controller.directText = ""
            controller.expectedCaret = nil
            return
        }

        // 검증 실패 시 누수 구간 산정에 필요하므로 직전 directText를 미리 저장한다.
        let priorDirectText = controller.directText

        if !combined.isEmpty || replaceRange.location != NSNotFound {
            sender.insertText(combined, replacementRange: replaceRange)
        }

        // PHASE 2 ③(B층): 실제 치환을 시도한(replaceRange != NSNotFound) 비어 있지 않은
        // 삽입이라면, caret 착지로 제자리 치환이 실제 일어났는지 검증한다. append-only
        // 앱(Word 등)은 replacementRange를 무시하고 append하므로 caret이 기대보다
        // 오른쪽에 남는다. 위반이면 그 클라이언트를 marked로 강등·학습한다.
        if !combined.isEmpty, replaceRange.location != NSNotFound,
           didInlineReplaceFail(combined: combined, replaceRange: replaceRange, client: sender)
        {
            demoteToMarked(priorDirectText: priorDirectText, replaceRange: replaceRange,
                           combined: combined, client: sender)
            return
        }

        if composedString.isEmpty {
            controller.directRange = nil
            controller.directText = ""
            controller.expectedCaret = nil
        } else {
            let baseLoc: Int
            if replaceRange.location != NSNotFound {
                baseLoc = replaceRange.location
            } else {
                let sel = sender.selectedRange()
                // 셀렉션 위치를 알 수 없으면 직접 범위를 산정할 수 없으므로,
                // 손상된 directRange를 저장하지 않고 추적 상태를 비운다.
                if sel.location == NSNotFound {
                    controller.directRange = nil
                    controller.directText = ""
                    controller.expectedCaret = nil
                    return
                }
                baseLoc = sel.location - (combined as NSString).length
            }
            controller.directRange = NSRange(location: baseLoc + (commitString as NSString).length,
                                             length: (composedString as NSString).length)
            controller.directText = composedString
            // ② 기대 caret = 삽입한 combined의 끝 = directRange의 끝.
            controller.expectedCaret = baseLoc + (combined as NSString).length
        }
    }

    /// 인라인 제자리 치환이 실패했는지(=클라이언트가 replacementRange를 무시하고
    /// append했는지) caret 착지로 판정한다. 기대 caret = replaceRange.location +
    /// combined 길이. selectedRange가 이와 다르면 실패로 본다. selectedRange를 알 수
    /// 없으면(NSNotFound) 함부로 강등하지 않는다(false).
    private func didInlineReplaceFail(combined: String, replaceRange: NSRange,
                                      client sender: IMKTextInput & IMKUnicodeTextInput) -> Bool
    {
        let sel = sender.selectedRange()
        if sel.location == NSNotFound {
            return false
        }
        let expected = replaceRange.location + (combined as NSString).length
        return sel.location != expected
    }

    /// append-only로 판명된 클라이언트를 marked로 강등·학습한다. 누수 구간은 best-effort로
    /// 제거를 시도하고(append-only 앱은 이 삭제도 무시할 수 있어 1회성 잔상이 남을 수
    /// 있음 — 깨끗함은 A층 시드 목록이 보장), 진행 중 조합을 marked로 즉시 재렌더한다.
    private func demoteToMarked(priorDirectText: String, replaceRange: NSRange, combined: String,
                               client sender: IMKTextInput & IMKUnicodeTextInput)
    {
        // 1) 학습 + 세션 강등.
        if let bundleID = sender.bundleIdentifier(), !bundleID.isEmpty {
            InputController.recordLearnedAppendOnly(bundleID: bundleID)
        }
        controller.useMarkedText = true

        // 2) best-effort 누수 제거: [replaceRange.location, priorDirectText + combined].
        let leakedLength = (priorDirectText as NSString).length + (combined as NSString).length
        let leakedRange = NSRange(location: replaceRange.location, length: leakedLength)
        sender.insertText("", replacementRange: leakedRange)

        // 3) 인라인 추적 비우고 진행 중 조합을 marked로 재렌더(useMarkedText=true이므로
        //    updateComposition이 marked 경로를 탄다).
        controller.directRange = nil
        controller.directText = ""
        controller.expectedCaret = nil
        updateComposition()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineRenderTests/testInlineDemotesToMarkedWhenClientAppendsIgnoringRange 2>&1 | tail -40
```
Expected: PASS.

- [ ] **Step 5: Run the full inline suite (no regressions)**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineCompositionTests -only-testing:OSXTests/InlineRenderTests 2>&1 | tail -40
```
Expected: PASS — in particular `testInlineModeProducesDirectInsertionsNoMarkedText` (honors-range client → no false-positive demote, exact insert ranges unchanged), `testInlineSpaceCommitDoesNotDuplicateLastSyllable`, `testInlineEnterCommitDoesNotDuplicateLastSyllable`, and `testInlineCommitWithLostDirectRangeDoesNotAppend` (① fail-safe) all green.

- [ ] **Step 6: Commit**

```bash
git checkout OSX/Version.xcconfig 2>/dev/null
git add OSXCore/InputReceiver.swift GureumTests/InlineCompositionTests.swift
git commit -m "feat(inline): PHASE 2 ③ — post-write caret validation demotes append-only clients to marked

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: ② cursor-move invalidation

**Files:**
- Modify: `OSXCore/InputReceiver.swift` (add `invalidateDirectRangeIfCursorMoved` helper; call it in `input(...)` inline branch ~lines 95-100)
- Test: `GureumTests/InlineCompositionTests.swift` (add ② test to `InlineRenderTests`)

- [ ] **Step 1: Write the failing test**

In `GureumTests/InlineCompositionTests.swift`, add this test to `class InlineRenderTests`:

```swift
    func testCursorMoveMidCompositionReanchorsInsteadOfReplacingStaleRange() {
        Configuration.shared.inlineCompositionEnabled = true
        app.controller.useMarkedText = false

        // 기존 텍스트 끝에서 조합을 시작한다.
        app.client.string = "XY"
        app.client.setSelectedRange(NSRange(location: 2, length: 0))
        app.inputKeys("d") // ㅇ → "XYㅇ", directRange=(2,1), expectedCaret=3

        // 사용자가 커서를 문서 맨 앞으로 옮긴다(클릭/화살표 모사).
        app.client.setSelectedRange(NSRange(location: 0, length: 0))
        app.client.resetRecordedInsertions()

        app.inputKeys("k") // ㅏ → "아"; action==.none. ②가 stale directRange(2,1)를 무효화.

        let insertions = app.client.recordedInsertions()
        XCTAssertFalse(insertions.isEmpty, "a keystroke after cursor move must produce an insertion")
        // 핵심: 옛 directRange(2,1) 제자리 치환이 아니라 NSNotFound(새 삽입)이어야 한다.
        let firstRange = insertions.first?["range"]
        XCTAssertEqual(NSStringFromRange(NSRange(location: NSNotFound, length: 0)), firstRange,
                       "after cursor move the keystroke must insert fresh (NSNotFound), not replace the stale range: \(insertions)")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineRenderTests/testCursorMoveMidCompositionReanchorsInsteadOfReplacingStaleRange 2>&1 | tail -40
```
Expected: FAIL — without ②, `inlineReplaceRange` validates the stale "ㅇ" still at (2,1) and replaces there, so the recorded range is `{2, 1}`, not `{NSNotFound, 0}`.

- [ ] **Step 3: Add the ② helper + call site**

In `OSXCore/InputReceiver.swift`, add this helper immediately before `renderInline` (i.e., before the `/// 직전 인라인 조합 문자열...` doc comment of `inlineReplaceRange`, or anywhere in the same extension — place it right after the `input(text:...)` function, before `inlineReplaceRange`):

```swift
    /// ② 커서이동 무효화: 직전 인라인 렌더 이후의 기대 caret(expectedCaret)과 현재
    /// selectedRange가 다르면 사용자가 커서를 옮긴 것 → directRange를 비워 재앵커한다.
    /// 그대로 두면 directRangeIsCurrent가 옛 위치의 텍스트를 그대로 확인해 그 위치를
    /// 제자리 치환하고, 사용자가 옮긴 위치를 무시한다(Word move-then-delete 점프).
    private func invalidateDirectRangeIfCursorMoved(_ sender: IMKTextInput & IMKUnicodeTextInput) {
        guard controller.directRange != nil, let expected = controller.expectedCaret else {
            return
        }
        let sel = sender.selectedRange()
        if sel.location == NSNotFound {
            return
        }
        if sel.location != expected {
            controller.directRange = nil
            controller.directText = ""
            controller.expectedCaret = nil
        }
    }
```

Then, in `input(text:...)`, find the inline branch (currently):
```swift
        if Configuration.shared.inlineCompositionEnabled, !controller.useMarkedText {
            // 인라인(직접 입력) 분기: 커밋 + 조합 문자를 한 번의 insertText로 문서에 반영한다.
            renderInline(sender)
            if result.action == .commit {
                return result
            }
        } else {
```
Replace it with:
```swift
        if Configuration.shared.inlineCompositionEnabled, !controller.useMarkedText {
            // ② 커서이동 무효화: 순수 조합 연속(action == .none)일 때만 검사한다. 커밋/취소
            // 경로는 ① fail-safe가 처리하므로 건드리지 않는다(그렇지 않으면 lost-range 커밋이
            // stale 추적을 비워 append 중복을 낸다).
            if result.action == .none {
                invalidateDirectRangeIfCursorMoved(sender)
            }
            // 인라인(직접 입력) 분기: 커밋 + 조합 문자를 한 번의 insertText로 문서에 반영한다.
            renderInline(sender)
            if result.action == .commit {
                return result
            }
        } else {
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineRenderTests/testCursorMoveMidCompositionReanchorsInsteadOfReplacingStaleRange 2>&1 | tail -40
```
Expected: PASS.

- [ ] **Step 5: Run the full inline suite (no regressions)**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests/InlineCompositionTests -only-testing:OSXTests/InlineRenderTests 2>&1 | tail -40
```
Expected: PASS. Critical regression checks:
- `testInlineModeProducesDirectInsertionsNoMarkedText` — normal typing has no cursor move, so ② never fires; the exact replace ranges `{0,1}`/`{1,1}` are unchanged.
- `testInlineCommitWithLostDirectRangeDoesNotAppend` — space is `action == .commit`, so ② is skipped and the ① fail-safe still suppresses the duplicate.
- `testInlineModeChangeMidCompositionDoesNotDuplicate` / `testInlineForcedCommitMidCompositionDoesNotDuplicate` — still green.

- [ ] **Step 6: Commit**

```bash
git checkout OSX/Version.xcconfig 2>/dev/null
git add OSXCore/InputReceiver.swift GureumTests/InlineCompositionTests.swift
git commit -m "feat(inline): PHASE 2 ② — drop stale directRange on cursor move, re-anchor fresh

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Full regression build + spec status update

**Files:**
- Modify: `docs/superpowers/specs/2026-06-04-inline-direct-input-design.md` (mark PHASE 2 ③+② implemented)

- [ ] **Step 1: Run the ENTIRE OSXTests suite (full regression gate)**

Run:
```bash
xcodebuild test -project bomi-input.xcodeproj -scheme OSX -destination 'platform=macOS' \
  -only-testing:OSXTests 2>&1 | tail -50
```
Expected: PASS for everything except the known 1 baseline failure recorded in prior sessions (the `testIPMDServerClientWrapper`-class IMK-environment crash noted in the test comments). If any inline/classify test fails, fix before proceeding — do not edit the spec on red.

- [ ] **Step 2: Update the spec STATUS**

In `docs/superpowers/specs/2026-06-04-inline-direct-input-design.md`, at the top of the `### PHASE 2 (next — capability gate done right, NON-INVASIVE; design 2026-06-05)` section, change the heading to:
```markdown
### PHASE 2 (③ non-invasive gate + ② cursor-move — IMPLEMENTED 2026-06-05, behind kill-switch)
```
And add this line right under the heading:
```markdown
Implemented (A seed list `bundleIdentifierUsesAppendOnlyTextStack`, B runtime caret-landing learning in
renderInline → demote+learn+best-effort-repair, ② expectedCaret invalidation). OSXTests green
(1 known IMK-env baseline). Inline still default-FALSE; PENDING: flip the UI switch ON + run the on-device
matrix (Word/Excel/Hancom → marked; Notes/Safari/Slack → inline; an unknown append app → B-layer learns),
then decide whether to flip the default.
```

- [ ] **Step 3: Commit**

```bash
git checkout OSX/Version.xcconfig 2>/dev/null
git add docs/superpowers/specs/2026-06-04-inline-direct-input-design.md
git commit -m "spec(inline): PHASE 2 ③+② implemented behind kill-switch; on-device matrix pending

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## On-device dogfood (manual, after enabling — not a code task)

Build/sign/install per CLAUDE.md, flip `inlineCompositionEnabled` ON via Preferences → "인라인 직접 입력 (실험적)", then run the matrix:
- **Seed → marked (no artifact):** MS Word, Excel, PowerPoint, Hancom 한글. Verify bundle IDs match the seed list; if an app still duplicates, capture its real bundle ID and widen the seed list.
- **Stay inline:** Notes/TextEdit, Safari, Slack — underline-free, correct text, no duplication on space/enter.
- **B-layer learns:** an unknown append-only app — expect at most a one-time small residue on the FIRST composition, then marked (clean) forever after in that session.
- **② :** in an inline app, type a syllable, click/arrow elsewhere, keep typing — the new text lands at the new caret; the old syllable is left intact (not edited in place).

Record per-app results; only then decide whether to flip the `inlineCompositionEnabled` default to true.
