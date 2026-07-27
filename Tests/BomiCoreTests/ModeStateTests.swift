import Testing
@testable import BomiCore

/// One process-wide cache: a write is what the next reader sees, no matter how
/// many controller instances conceptually share it. The value is restored
/// afterwards so test order cannot leak state into other tests.
@MainActor @Test func modeStateSharesWritesAcrossReaders() {
    let saved = ModeState.current
    defer { ModeState.current = saved }

    ModeState.current = .roman
    #expect(ModeState.current == .roman)

    ModeState.current = .korean
    #expect(ModeState.current == .korean)
}
