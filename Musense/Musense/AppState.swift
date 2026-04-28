import SwiftUI
import UIKit

final class AppState: ObservableObject {
    @Published var didCompleteOnboarding = false
    @Published var hapticIntensity = 0.65
    @Published var visualizerStyle: VisualizerStyle = .waves
    @Published var reducedMotion = false
    @Published var sessions = MusicSession.demoSessions

    func save(_ session: MusicSession) {
        guard !sessions.contains(where: { $0.id == session.id }) else { return }

        var savedSession = session
        savedSession.isSaved = true
        savedSession.timestamp = "Just now"
        sessions.insert(savedSession, at: 0)
        playHaptic()
    }

    func deleteSessions(at offsets: IndexSet, from filteredSessions: [MusicSession]) {
        let idsToDelete = offsets.map { filteredSessions[$0].id }
        sessions.removeAll { idsToDelete.contains($0.id) }
    }

    func playHaptic() {
        guard hapticIntensity > 0 else { return }

        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch hapticIntensity {
        case ..<0.35:
            style = .light
        case ..<0.75:
            style = .medium
        default:
            style = .heavy
        }

        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: CGFloat(hapticIntensity))
    }
}
