import Foundation

public struct HangulComposer {
    private var cho: UInt32 = 0
    private var jung: UInt32 = 0
    private var jong: UInt32 = 0
    private var stack: [UInt32] = []   // push order; last = most recent (peek); used for backspace

    /// 모아치기 (chord typing): two keys within this many seconds may fill empty
    /// slots out of canonical order (jung/jong arriving before their cho).
    /// Safe on this layout because Sebeolsik-final keys are slot-distinct.
    /// ponytail: fixed knob; observed real rolls were 90–133ms apart. Promote to
    /// a Preference if daily typing wants tuning.
    public var chordWindow: Double = 0.15
    private var lastKeyTime: Double = -.infinity

    public init() {}

    public var isComposing: Bool { !stack.isEmpty }
    public var preedit: String { Syllable.render(cho: cho, jung: jung, jong: jong) }

    private var peek: UInt32 { stack.last ?? 0 }

    private mutating func push(_ c: UInt32) {
        switch Jamo.slot(of: c) {
        case .cho:  cho = c
        case .jung: jung = c
        case .jong: jong = c
        case nil:   break
        }
        stack.append(c)
    }

    /// Emit current buffer as a string and clear it.
    private mutating func drain() -> String {
        let s = Syllable.render(cho: cho, jung: jung, jong: jong)
        cho = 0; jung = 0; jong = 0; stack.removeAll(keepingCapacity: true)
        return s
    }

    public mutating func flush() -> String { drain() }

    /// Timed entry point: keys closer together than `chordWindow` may assemble
    /// out of order (모아치기). `time` is any monotonic clock in seconds
    /// (NSEvent.timestamp / systemUptime).
    public mutating func inputASCII(_ ascii: UInt32, at time: Double) -> String {
        let chord = time - lastKeyTime <= chordWindow
        lastKeyTime = time
        return input(ascii, chord: chord)
    }

    /// Untimed entry point: never chords (legacy behavior).
    public mutating func inputASCII(_ ascii: UInt32) -> String {
        input(ascii, chord: false)
    }

    /// Process one Sebeolsik-final ASCII key. Returns text to commit to the client (possibly empty).
    private mutating func input(_ ascii: UInt32, chord: Bool) -> String {
        guard let value = SebeolsikFinal.jamo(forASCII: ascii) else {
            // Not in the 3f map (e.g. space): commit current, let caller pass the key through.
            return drain()
        }
        var commit = ""
        switch Jamo.slot(of: value) {
        case .cho:
            if cho == 0 {
                // A cho with jung/jong already present is a new syllable when
                // typed deliberately, but a chord-window arrival is the same
                // syllable's cho landing late — fill instead of splitting.
                if !chord, jung != 0 || jong != 0 { commit += drain() }
                push(value)
            } else if Jamo.isCho(peek),
                      case let comb = Combination.combine(cho, value, allowChoToJong: false),
                      comb != 0 {
                push(comb)
            } else {
                commit += drain(); push(value)
            }
        case .jung:
            if jung == 0 {
                if !chord, jong != 0 { commit += drain() }
                push(value)
            } else if Jamo.isJung(peek),
                      case let comb = Combination.combine(jung, value),
                      comb != 0 {
                push(comb)
            } else {
                commit += drain(); push(value)
            }
        case .jong:
            if jong == 0 {
                push(value)
            } else if Jamo.isJong(peek),
                      case let comb = Combination.combine(jong, value),
                      comb != 0 {
                push(comb)
            } else {
                commit += drain(); push(value)
            }
        case nil:
            // Symbol/digit from the 3f map (e.g. '.', '·'): commit current, append the symbol.
            commit += drain()
            if let scalar = UnicodeScalar(value) {
                commit.unicodeScalars.append(scalar)
            }
        }
        return commit
    }

    /// Backspace one jamo while composing. Rebuilds slots from the remaining stack
    /// (a compound reverts to its base). Returns false if nothing was composing.
    public mutating func backspace() -> Bool {
        guard !stack.isEmpty else { return false }
        stack.removeLast()
        cho = 0; jung = 0; jong = 0
        for c in stack {
            switch Jamo.slot(of: c) {
            case .cho:  cho = c
            case .jung: jung = c
            case .jong: jong = c
            case nil:   break
            }
        }
        return true
    }
}
