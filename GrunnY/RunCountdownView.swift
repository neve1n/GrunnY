import SwiftUI

struct RunCountdownView: View {
    let start: () -> Void
    let cancel: () -> Void
    @State private var step = 0
    @State private var interrupted = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let labels = ["3", "2", "1", "START"]

    var body: some View {
        ZStack {
            Color(red: 0.294, green: 0.918, blue: 0.839).ignoresSafeArea()
            Text(labels[step])
                .font(.system(size: step == 3 ? 58 : 68, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .id(step)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.75).combined(with: .opacity))
        }
        .statusBarHidden()
        .interactiveDismissDisabled()
        .accessibilityLabel(step == 3 ? "러닝 시작" : "러닝 시작까지 \(labels[step])")
        .accessibilityAction(.escape, cancel)
        .task {
            do {
                for next in 1...3 {
                    try await Task.sleep(for: .seconds(1))
                    guard !interrupted, scenePhase == .active else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { step = next }
                }
                try await Task.sleep(for: .milliseconds(600))
                guard !interrupted, scenePhase == .active else { return }
                start()
            } catch {
                // Dismissal cancels the countdown without starting a run.
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                interrupted = true
                cancel()
            }
        }
    }
}

// Carry the initial screen with presentation, rather than racing two Bool states.
struct RunPresentation: Identifiable {
    let id = UUID()
    let countdown: Bool
}

struct RunSessionFlow: View {
    let location: LocationManager
    let planner: RoutePlanner
    let targetPace: Int
    let done: () -> Void
    let cancel: () -> Void
    @State private var countingDown: Bool

    init(location: LocationManager, planner: RoutePlanner, targetPace: Int,
         countdown: Bool, done: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.location = location
        self.planner = planner
        self.targetPace = targetPace
        self.done = done
        self.cancel = cancel
        _countingDown = State(initialValue: countdown)
    }

    var body: some View {
        Group {
            if countingDown {
                RunCountdownView {
                    location.startRun()
                    guard location.isRunning else { cancel(); return }
                    countingDown = false
                } cancel: {
                    // Keep the countdown branch intact until dismissal completes.
                    cancel()
                }
            } else if location.startedAt != nil {
                DesignedRunSession(location: location, planner: planner,
                                   targetPace: targetPace, done: done)
            } else {
                Color.clear.task { cancel() }
            }
        }
        .interactiveDismissDisabled()
    }
}
