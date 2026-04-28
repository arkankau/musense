import AVFoundation
import XCTest
@testable import Musense

final class MusenseTests: XCTestCase {
    func testSavingSessionMarksItSavedAndAvoidsDuplicates() {
        let appState = AppState()
        appState.hapticIntensity = 0
        let initialCount = appState.sessions.count
        let session = makeSession(title: "Test Track", isSaved: false)

        appState.save(session)
        appState.save(session)

        XCTAssertEqual(appState.sessions.count, initialCount + 1)
        XCTAssertEqual(appState.sessions.first?.id, session.id)
        XCTAssertEqual(appState.sessions.first?.isSaved, true)
        XCTAssertEqual(appState.sessions.first?.timestamp, "Just now")
    }

    func testDeletingFilteredSessionsRemovesMatchingIdsOnly() {
        let appState = AppState()
        appState.hapticIntensity = 0
        let liveSession = makeSession(title: "Live Capture", isLiveSession: true)
        let savedSession = makeSession(title: "Saved Track", isLiveSession: false)
        appState.sessions = [liveSession, savedSession]

        appState.deleteSessions(at: IndexSet(integer: 0), from: [liveSession])

        XCTAssertEqual(appState.sessions, [savedSession])
    }

    func testHighAmplitudeBufferProducesHighEnergyFeatures() throws {
        let buffer = try makeSineBuffer(amplitude: 0.8, frequency: 440)

        let result = AudioAnalyzer.extractFeatures(
            from: buffer,
            sampleRate: buffer.format.sampleRate,
            rollingEnergy: Array(repeating: 0.05, count: 8),
            beatTimes: [],
            lastBeatTime: 0
        )

        XCTAssertEqual(result.snapshot.levels.count, 18)
        XCTAssertEqual(result.snapshot.energyLabel, "High")
        XCTAssertGreaterThan(result.snapshot.energyValue, 0.55)
        XCTAssertTrue(result.snapshot.isBeat)
        XCTAssertEqual(result.snapshot.tempo, 0)
        XCTAssertTrue(result.summary.contains("high energy"))
        XCTAssertTrue(result.summary.contains("no stable tempo yet"))
    }

    func testQuietBufferProducesLowEnergyFeatures() throws {
        let buffer = try makeSineBuffer(amplitude: 0.01, frequency: 220)

        let result = AudioAnalyzer.extractFeatures(from: buffer, sampleRate: buffer.format.sampleRate)

        XCTAssertEqual(result.snapshot.energyLabel, "Low")
        XCTAssertLessThan(result.snapshot.energyValue, 0.25)
        XCTAssertFalse(result.snapshot.isBeat)
        XCTAssertEqual(result.snapshot.levels.count, 18)
    }

    func testAnalyzeFileCreatesSavedLocalSession() async throws {
        let url = try makeTemporaryAudioFile()
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let analyzer = AudioAnalyzer()
        let session = try await analyzer.analyzeFile(at: url)

        XCTAssertEqual(session.title, "musense-test-tone")
        XCTAssertEqual(session.artist, "Local file")
        XCTAssertTrue(session.isSaved)
        XCTAssertFalse(session.isLiveSession)
        XCTAssertGreaterThanOrEqual(session.tempo, 0)
        XCTAssertFalse(session.summary.isEmpty)
    }

    private func makeSession(
        title: String,
        isLiveSession: Bool = false,
        isSaved: Bool = true
    ) -> MusicSession {
        MusicSession(
            title: title,
            artist: "Test Artist",
            album: "Test Album",
            timestamp: "Now",
            mood: "Warm",
            energy: "Medium",
            tempo: 120,
            valence: 0.6,
            danceability: 0.7,
            isLiveSession: isLiveSession,
            isSaved: isSaved,
            summary: "Test summary"
        )
    }

    private func makeSineBuffer(
        amplitude: Float,
        frequency: Double,
        sampleRate: Double = 44_100,
        duration: Double = 1.0
    ) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount

        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            let phase = 2.0 * Double.pi * frequency * Double(frame) / sampleRate
            samples[frame] = amplitude * Float(sin(phase))
        }

        return buffer
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let buffer = try makeSineBuffer(amplitude: 0.35, frequency: 330)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("musense-test-tone.caf")
        try? FileManager.default.removeItem(at: url)

        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try file.write(from: buffer)
        return url
    }
}
