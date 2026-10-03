import AppKit

/// Types Parakeet's running transcript into the focused field while the hotkey is
/// held. During the hold it only appends whole words that two partials in a row
/// agree on, so nothing is erased while you speak; on release the final transcript
/// corrects what differs (Backspace back to the common prefix, then type the rest).
@MainActor
final class LiveTyper {
    private let engine: TranscriptionEngine
    private let clean: (String) -> String
    private var typed = ""
    private var previousPartial = ""
    /// App that had focus when the hold began; nil when live typing never started.
    private var targetPID: pid_t?
    /// Focus moved to another app mid-phrase: leave both apps alone from then on.
    private var lostFocus = false
    private var loop: Task<Void, Never>?

    init(engine: TranscriptionEngine, clean: @escaping (String) -> String) {
        self.engine = engine
        self.clean = clean
    }

    func start() {
        guard TextInserter.focusedTarget() == .inserted else { return }
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        loop = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    /// Stops the loop and waits for a partial that is still being recognised.
    func stop() async {
        loop?.cancel()
        await loop?.value
        loop = nil
    }

    /// Puts the final text in place of what was typed live. Nil when nothing was
    /// typed live, so the caller inserts the usual way into whatever has focus now.
    func finish(_ final: String) -> InsertionResult? {
        guard targetPID != nil, !typed.isEmpty else { return nil }
        replace(with: final)
        return lostFocus ? .noFocus : .inserted
    }

    private func tick() async {
        let samples = engine.peekSamples()
        guard samples.count >= 8_000 else { return } // 0.5 s at 16 kHz
        guard let raw = await engine.partial(samples: samples), !Task.isCancelled else { return }
        let partial = clean(raw)
        defer { previousPartial = partial }
        // Whole words both partials agree on; the unstable tail waits for the next pass.
        var agreed = String(zip(previousPartial, partial).prefix { $0 == $1 }.map(\.0))
        guard let lastSpace = agreed.lastIndex(where: \.isWhitespace) else { return }
        agreed = String(agreed[...lastSpace])
        // Append only, except a comma or period added to the last typed word; a
        // revision of whole words waits for the final pass.
        let keep = zip(typed, agreed).prefix { $0 == $1 }.count
        guard agreed.count > typed.count, typed.count - keep <= 2 else { return }
        replace(with: agreed)
    }

    private func replace(with text: String) {
        guard !lostFocus else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            lostFocus = true
            pttLog("live typing: focus moved to another app, stopped")
            return
        }
        let keep = zip(typed, text).prefix { $0 == $1 }.count
        if typed.count > keep { pttLog("live typing: erased \(typed.count - keep) chars") }
        TextInserter.backspace(typed.count - keep)
        TextInserter.type(String(text.dropFirst(keep)))
        typed = text
    }
}
