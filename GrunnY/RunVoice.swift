import AVFoundation

/// One speaker for countdown, navigation and records. Navigation can interrupt
/// a split report; the report is then replayed after the urgent instruction.
@MainActor final class RunVoice: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = RunVoice()
    enum Priority: Int { case record = 0, direction = 1, event = 2 }
    private struct Line {
        let text: String
        let priority: Priority
        let expires: Date
    }
    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [Line] = []
    private var current: (line: Line, utterance: AVSpeechUtterance)?

    override init() {
        super.init()
        synthesizer.delegate = self
        // Let the system manage ducking/mixing and interruptions for speech.
        synthesizer.usesApplicationAudioSession = false
    }

    func say(_ text: String, priority: Priority = .direction, lifetime: TimeInterval = 20) {
        let line = Line(text: text, priority: priority, expires: .now.addingTimeInterval(lifetime))
        if let current, priority.rawValue > current.line.priority.rawValue {
            if current.line.priority == .record { queue.append(current.line) }
            self.current = nil
            synthesizer.stopSpeaking(at: .immediate)
        }
        if priority == .direction { queue.removeAll { $0.priority == .direction } }
        queue.append(line)
        playNext()
    }

    func stop() {
        queue = []; current = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func cancelDirections() {
        queue.removeAll { $0.priority == .direction }
        if current?.line.priority == .direction {
            current = nil
            synthesizer.stopSpeaking(at: .immediate)
            playNext()
        }
    }

    private func playNext() {
        guard current == nil else { return }
        queue.removeAll { $0.expires < .now }
        guard let index = queue.indices.max(by: { queue[$0].priority.rawValue < queue[$1].priority.rawValue }) else { return }
        let line = queue.remove(at: index)
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        current = (line, utterance)
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.current, ObjectIdentifier(current.utterance) == identifier else { return }
            self.current = nil
            self.playNext()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.current, ObjectIdentifier(current.utterance) == identifier else { return }
            self.current = nil
            self.playNext()
        }
    }
}
