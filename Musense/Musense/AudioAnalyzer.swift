import AVFoundation
import Foundation
import ShazamKit
import Speech

struct AudioSnapshot: Equatable {
    var levels: [Double]
    var energyValue: Double
    var energyLabel: String
    var mood: String
    var tempo: Int
    var valence: Double
    var danceability: Double
    var isBeat: Bool
    var emotionColor: EmotionColor

    static let idle = AudioSnapshot(
        levels: Array(repeating: 0.03, count: 18),
        energyValue: 0.0,
        energyLabel: "Silence",
        mood: "Waiting",
        tempo: 0,
        valence: 0.5,
        danceability: 0.5,
        isBeat: false,
        emotionColor: .softMist
    )
}

final class AudioAnalyzer: NSObject, ObservableObject {
    @Published var snapshot = AudioSnapshot.idle
    @Published var isListening = false
    @Published var statusText = ""
    @Published var errorMessage: String?
    @Published var transcript = ""
    @Published var beatCount = 0
    @Published var recognizedSong: RecognizedSong?
    @Published var lyrics = ""
    @Published var recognitionStatus = ""

    private var engine: AVAudioEngine?
    private var rollingEnergy: [Double] = []
    private var beatTimes: [TimeInterval] = []
    private var lastBeatTime: TimeInterval = 0
    private var energyHistory: [Double] = []
    private var valenceHistory: [Double] = []
    private var danceabilityHistory: [Double] = []
    private var moodCounts: [String: Int] = [:]
    private var emotionColorCounts: [EmotionColor: Int] = [:]
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private var shazamSession = SHSession()
    private let lyricsService = LyricsService()
    private let apiRecognitionService = AudioRecognitionAPIService()
    private var lyricsTask: Task<Void, Never>?
    private var apiRecognitionTask: Task<Void, Never>?
    private var liveRecordingFile: AVAudioFile?
    private var liveRecordingURL: URL?
    private var liveRecordingStartedAt: Date?
    private var hasAttemptedAPIRecognition = false
    private var sessionStartedAt: Date?
    private var lastStableTempo: Int = 0
    private var onBeat: (() -> Void)?

    override init() {
        super.init()
        shazamSession.delegate = self
    }

    func startMicrophone(onBeat: @escaping () -> Void) {
        self.onBeat = onBeat
        errorMessage = nil

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }

                if granted {
                    SFSpeechRecognizer.requestAuthorization { [weak self] status in
                        DispatchQueue.main.async {
                            self?.startEngine(speechAuthorized: status == .authorized)
                        }
                    }
                } else {
                    self.errorMessage = "Microphone access is needed for Live Listen."
                    self.statusText = "Mic blocked"
                }
            }
        }
    }

    func stopMicrophone() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        speechRequest?.endAudio()
        speechTask?.cancel()
        speechRequest = nil
        speechTask = nil
        lyricsTask?.cancel()
        lyricsTask = nil
        apiRecognitionTask?.cancel()
        apiRecognitionTask = nil
        liveRecordingFile = nil
        isListening = false
        statusText = ""
    }

    func analyzeFile(at url: URL) async throws -> MusicSession {
        let localURL = try copyToTempLocation(url: url)
        let title = url.deletingPathExtension().lastPathComponent

        await MainActor.run {
            recognizedSong = nil
            lyrics = ""
            recognitionStatus = "Identifying..."
            statusText = "Analyzing \(title)"
        }

        let file = try AVAudioFile(forReading: localURL)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: file.processingFormat.channelCount,
            interleaved: false
        ) else {
            throw AudioAnalyzerError.unsupportedFormat
        }

        let signatureGenerator = SHSignatureGenerator()
        let chunkSize = AVAudioFrameCount(format.sampleRate * 0.05)
        var rollingEnergyState: [Double] = []
        var beatTimesState: [TimeInterval] = []
        var lastBeatTimeState: TimeInterval = 0
        var energySamples: [Double] = []
        var valenceSamples: [Double] = []
        var danceabilitySamples: [Double] = []
        var moodTally: [String: Int] = [:]
        var emotionTally: [EmotionColor: Int] = [:]
        var beatCounter = 0
        var lastSnapshotLocal = AudioSnapshot.idle
        var simulatedTime: TimeInterval = 0

        while file.framePosition < file.length {
            let remaining = file.length - file.framePosition
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), remaining))
            guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }

            do {
                try file.read(into: chunk, frameCount: frames)
            } catch {
                break
            }

            try? signatureGenerator.append(chunk, at: nil)

            let features = Self.extractFeatures(
                from: chunk,
                sampleRate: format.sampleRate,
                rollingEnergy: rollingEnergyState,
                beatTimes: beatTimesState,
                lastBeatTime: lastBeatTimeState,
                currentTime: simulatedTime
            )

            rollingEnergyState = features.rollingEnergy
            beatTimesState = features.beatTimes
            lastBeatTimeState = features.lastBeatTime
            if features.snapshot.isBeat { beatCounter += 1 }

            energySamples.append(features.snapshot.energyValue)
            valenceSamples.append(features.snapshot.valence)
            danceabilitySamples.append(features.snapshot.danceability)
            moodTally[features.snapshot.mood, default: 0] += 1
            emotionTally[features.snapshot.emotionColor, default: 0] += 1

            lastSnapshotLocal = features.snapshot
            simulatedTime += Double(frames) / format.sampleRate
        }

        let finalSnapshot = lastSnapshotLocal
        let totalBeats = beatCounter

        let averageEnergy = average(energySamples, fallback: finalSnapshot.energyValue)
        let averageValence = average(valenceSamples, fallback: finalSnapshot.valence)
        let averageDanceability = average(danceabilitySamples, fallback: finalSnapshot.danceability)
        let dominantMood = mostCommon(in: moodTally) ?? finalSnapshot.mood
        let dominantEmotion = mostCommon(in: emotionTally) ?? finalSnapshot.emotionColor
        let finalTempo = Self.estimatedTempo(from: beatTimesState)
        let energyLabel = Self.labelEnergy(averageEnergy)

        let tempoSummary = finalTempo > 0
            ? "\(finalTempo) bpm tempo"
            : "tempo not stable enough"
        let summary = "Musense found \(totalBeats) beats, \(energyLabel.lowercased()) energy, \(dominantMood.lowercased()) mood, and \(tempoSummary) in \(title)."

        let snapshotLevels = finalSnapshot.levels
        await MainActor.run {
            snapshot = AudioSnapshot(
                levels: snapshotLevels,
                energyValue: averageEnergy,
                energyLabel: energyLabel,
                mood: dominantMood,
                tempo: finalTempo,
                valence: averageValence,
                danceability: averageDanceability,
                isBeat: false,
                emotionColor: dominantEmotion
            )
            statusText = "Analyzed \(title)"
            recognitionStatus = "Searching..."
        }

        let signature = signatureGenerator.signature()
        await MainActor.run {
            let session = SHSession()
            self.shazamSession = session
            session.delegate = self
            session.match(signature)
        }

        return MusicSession(
            title: title.isEmpty ? "Uploaded Audio" : title,
            artist: "Local file",
            album: url.pathExtension.uppercased().isEmpty ? "Uploaded audio" : "\(url.pathExtension.uppercased()) upload",
            timestamp: "Just now",
            mood: dominantMood,
            energy: energyLabel,
            tempo: finalTempo,
            valence: averageValence,
            danceability: averageDanceability,
            isLiveSession: false,
            isSaved: true,
            summary: summary,
            emotionColor: dominantEmotion
        )
    }

    private func copyToTempLocation(url: URL) throws -> URL {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
        let destination = tempDir.appendingPathComponent("musense-upload-\(UUID().uuidString).\(url.pathExtension)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    func liveSession() -> MusicSession {
        let averageEnergy = average(energyHistory, fallback: snapshot.energyValue)
        let averageValence = average(valenceHistory, fallback: snapshot.valence)
        let averageDanceability = average(danceabilityHistory, fallback: snapshot.danceability)
        let mood = mostCommon(in: moodCounts) ?? snapshot.mood
        let emotionColor = mostCommon(in: emotionColorCounts) ?? snapshot.emotionColor
        let tempo = snapshot.tempo > 0 ? snapshot.tempo : lastStableTempo
        let tempoSummary = tempo > 0 ? "\(tempo) BPM" : "no stable tempo"
        let songTitle = recognizedSong?.displayTitle ?? "Untitled capture"
        let songArtist = recognizedSong?.displayArtist ?? "Microphone"
        let capturedText = lyrics.isEmpty ? transcript : lyrics
        let durationSeconds = sessionStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        let durationText = formatDuration(durationSeconds)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let timestamp = formatter.string(from: sessionStartedAt ?? Date())

        return MusicSession(
            title: songTitle,
            artist: songArtist,
            album: "Captured \(durationText)",
            timestamp: timestamp,
            mood: mood,
            energy: Self.labelEnergy(averageEnergy),
            tempo: tempo,
            valence: averageValence,
            danceability: averageDanceability,
            isLiveSession: true,
            isSaved: false,
            summary: "\(beatCount) beats, \(Self.labelEnergy(averageEnergy).lowercased()) energy, \(mood.lowercased()) mood, \(tempoSummary), over \(durationText).",
            transcript: capturedText,
            emotionColor: emotionColor
        )
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private func startEngine(speechAuthorized: Bool) {
        do {
            stopMicrophone()

            rollingEnergy.removeAll()
            beatTimes.removeAll()
            lastBeatTime = 0
            energyHistory.removeAll()
            valenceHistory.removeAll()
            danceabilityHistory.removeAll()
            moodCounts.removeAll()
            emotionColorCounts.removeAll()
            transcript = ""
            lyrics = ""
            recognizedSong = nil
            recognitionStatus = "Identifying..."
            beatCount = 0
            sessionStartedAt = Date()
            lastStableTempo = 0

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
            try session.setActive(true, options: [.notifyOthersOnDeactivation])

            let newEngine = AVAudioEngine()
            let input = newEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            configureSpeechRecognitionIfNeeded(isAuthorized: speechAuthorized)
            configureLiveRecording(format: format)

            input.installTap(onBus: 0, bufferSize: 8_192, format: format) { [weak self] buffer, audioTime in
                guard let self else { return }
                self.shazamSession.matchStreamingBuffer(buffer, at: audioTime)
                self.speechRequest?.append(buffer)
                try? self.liveRecordingFile?.write(from: buffer)
                self.processLiveBuffer(buffer, sampleRate: format.sampleRate)
            }

            try newEngine.start()
            engine = newEngine
            isListening = true
            statusText = "Listening"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Mic error"
            isListening = false
        }
    }

    private func processLiveBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        let features = Self.extractFeatures(
            from: buffer,
            sampleRate: sampleRate,
            rollingEnergy: rollingEnergy,
            beatTimes: beatTimes,
            lastBeatTime: lastBeatTime
        )

        rollingEnergy = features.rollingEnergy
        beatTimes = features.beatTimes
        lastBeatTime = features.lastBeatTime
        energyHistory.append(features.snapshot.energyValue)
        valenceHistory.append(features.snapshot.valence)
        danceabilityHistory.append(features.snapshot.danceability)
        moodCounts[features.snapshot.mood, default: 0] += 1
        emotionColorCounts[features.snapshot.emotionColor, default: 0] += 1
        energyHistory = Array(energyHistory.suffix(900))
        valenceHistory = Array(valenceHistory.suffix(900))
        danceabilityHistory = Array(danceabilityHistory.suffix(900))
        if features.snapshot.tempo > 0 {
            lastStableTempo = features.snapshot.tempo
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.snapshot = features.snapshot
            self.attemptAPIRecognitionIfReady()

            if features.snapshot.isBeat {
                self.beatCount += 1
                self.statusText = features.snapshot.mood
                self.onBeat?()
            } else if features.snapshot.energyValue < Self.silenceEnergyThreshold {
                self.statusText = "Quiet"
            } else {
                self.statusText = "Listening"
            }
        }
    }

    private func configureSpeechRecognitionIfNeeded(isAuthorized: Bool) {
        guard isAuthorized, speechRecognizer?.isAvailable == true else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = false
        }
        speechRequest = request
        speechTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }

                if error != nil {
                    self?.speechTask?.cancel()
                    self?.speechTask = nil
                }
            }
        }
    }

    private func configureLiveRecording(format: AVAudioFormat) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("musense-live-\(UUID().uuidString)")
            .appendingPathExtension("caf")

        do {
            liveRecordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
            liveRecordingURL = url
            liveRecordingStartedAt = Date()
            hasAttemptedAPIRecognition = false
        } catch {
            liveRecordingFile = nil
            liveRecordingURL = nil
            liveRecordingStartedAt = nil
        }
    }

    private func attemptAPIRecognitionIfReady() {
        guard recognizedSong == nil,
              !hasAttemptedAPIRecognition,
              apiRecognitionTask == nil,
              apiRecognitionService.hasToken,
              let url = liveRecordingURL,
              let startedAt = liveRecordingStartedAt,
              Date().timeIntervalSince(startedAt) > 8 else {
            return
        }

        hasAttemptedAPIRecognition = true
        recognitionStatus = "Searching..."

        apiRecognitionTask = Task { [weak self] in
            guard let self else { return }

            do {
                if let song = try await apiRecognitionService.recognize(fileURL: url) {
                    await MainActor.run {
                        self.recognizedSong = song
                        self.recognitionStatus = "Matched \(song.displayTitle)"
                        self.statusText = "Matched \(song.displayTitle)"
                        self.fetchLyrics(for: song)
                    }
                } else {
                    await MainActor.run {
                        self.recognitionStatus = "No match"
                    }
                }
            } catch {
                await MainActor.run {
                    self.recognitionStatus = error.localizedDescription
                }
            }

            await MainActor.run {
                self.apiRecognitionTask = nil
            }
        }
    }

    func identifyNow() {
        guard isListening else {
            recognitionStatus = "Start Live Listen first"
            return
        }

        shazamSession = SHSession()
        shazamSession.delegate = self
        recognitionStatus = "Listening..."
        statusText = "Listening"

        if apiRecognitionService.hasToken, liveRecordingURL != nil {
            hasAttemptedAPIRecognition = false
            liveRecordingStartedAt = Date(timeIntervalSinceNow: -10)
            attemptAPIRecognitionIfReady()
        }
    }

    var diagnosticsSummary: String {
        var lines: [String] = []
        lines.append("Mic: \(isListening ? "active" : "idle")")
        lines.append("Shazam: \(recognizedSong == nil ? "scanning" : "matched")")
        lines.append("Energy: \(snapshot.energyLabel)")
        lines.append("Beats: \(beatCount)")
        lines.append("Lyrics: \(lyrics.isEmpty ? "none" : "loaded")")
        #if targetEnvironment(simulator)
        lines.append("Simulator: ShazamKit unreliable")
        #endif
        return lines.joined(separator: " • ")
    }

    static func extractFeatures(
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        rollingEnergy existingEnergy: [Double] = [],
        beatTimes existingBeatTimes: [TimeInterval] = [],
        lastBeatTime existingLastBeatTime: TimeInterval = 0,
        currentTime: TimeInterval? = nil
    ) -> AudioFeatureResult {
        guard let channelData = buffer.floatChannelData else {
            return AudioFeatureResult(snapshot: .idle, summary: "No readable audio samples were found.")
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else {
            return AudioFeatureResult(snapshot: .idle, summary: "The audio file did not contain enough samples to analyze.")
        }

        var levels = Array(repeating: 0.0, count: 18)
        var sumSquares = 0.0
        var positiveSamples = 0
        var zeroCrossings = 0
        let bucketSize = max(frameLength / levels.count, 1)

        for frame in 0..<frameLength {
            var mixedSample = 0.0

            for channel in 0..<channelCount {
                mixedSample += Double(channelData[channel][frame])
            }

            mixedSample /= Double(channelCount)
            sumSquares += mixedSample * mixedSample

            if mixedSample > 0 {
                positiveSamples += 1
            }

            if frame > 0 {
                var previous = 0.0
                for channel in 0..<channelCount {
                    previous += Double(channelData[channel][frame - 1])
                }
                previous /= Double(channelCount)

                if (mixedSample >= 0 && previous < 0) || (mixedSample < 0 && previous >= 0) {
                    zeroCrossings += 1
                }
            }

            let bucket = min(frame / bucketSize, levels.count - 1)
            levels[bucket] = max(levels[bucket], min(abs(mixedSample) * 2.4, 1.0))
        }

        let rms = sqrt(sumSquares / Double(frameLength))
        let energyValue = normalizedEnergy(fromRMS: rms)
        var rollingEnergy = existingEnergy
        let previousAverageEnergy = rollingEnergy.isEmpty ? 0.0 : rollingEnergy.reduce(0, +) / Double(rollingEnergy.count)
        let previousPeak = rollingEnergy.max() ?? previousAverageEnergy
        rollingEnergy.append(energyValue)
        rollingEnergy = Array(rollingEnergy.suffix(16))

        let now = currentTime ?? Date().timeIntervalSinceReferenceDate
        var beatTimes = existingBeatTimes
        var lastBeatTime = existingLastBeatTime
        let isSilent = energyValue < silenceEnergyThreshold
        let adaptiveThreshold = max(0.09, previousAverageEnergy * 1.20)
        let transientJump = energyValue - previousAverageEnergy
        let isBeat = energyValue >= minimumBeatEnergy && (
            energyValue > adaptiveThreshold ||
            transientJump > 0.045 ||
            (energyValue > previousPeak * 0.95 && energyValue > 0.24)
        ) && now - lastBeatTime > 0.26

        if isBeat {
            beatTimes.append(now)
            beatTimes = Array(beatTimes.suffix(12))
            lastBeatTime = now
        }

        let tempo = estimatedTempo(from: beatTimes)
        let zeroCrossingRate = min(Double(zeroCrossings) / Double(frameLength), 1.0)
        let brightness = min(zeroCrossingRate * 14.0, 1.0)
        let positivity = min(Double(positiveSamples) / Double(frameLength), 1.0)
        let valence = isSilent ? 0.5 : clamp(0.18 + brightness * 0.42 + positivity * 0.4, lower: 0.0, upper: 1.0)
        let tempoFactor = tempo > 0 ? Double(tempo) / 180.0 : 0
        let danceability = isSilent ? 0.0 : clamp(tempoFactor * 0.55 + energyValue * 0.45, lower: 0.0, upper: 1.0)
        let energyLabel = labelEnergy(energyValue)
        let mood = labelMood(energy: energyValue, valence: valence)
        let emotionColor = labelEmotionColor(energy: energyValue, valence: valence)

        let normalizedLevels = levels.map { clamp($0 * 1.15 + (isSilent ? 0.02 : 0.05), lower: 0.02, upper: 1.0) }
        let snapshot = AudioSnapshot(
            levels: normalizedLevels,
            energyValue: energyValue,
            energyLabel: energyLabel,
            mood: mood,
            tempo: tempo,
            valence: valence,
            danceability: danceability,
            isBeat: isBeat,
            emotionColor: emotionColor
        )

        let tempoText = tempo > 0 ? "\(tempo) BPM tempo" : "no stable tempo yet"
        let summary = "Musense estimated \(energyLabel.lowercased()) energy, \(mood.lowercased()) mood, \(tempoText), \(valence.formatted(.number.precision(.fractionLength(2)))) valence, and \(danceability.formatted(.number.precision(.fractionLength(2)))) danceability from the audio waveform."

        return AudioFeatureResult(
            snapshot: snapshot,
            summary: summary,
            rollingEnergy: rollingEnergy,
            beatTimes: beatTimes,
            lastBeatTime: lastBeatTime
        )
    }

    private static func estimatedTempo(from beatTimes: [TimeInterval]) -> Int {
        guard beatTimes.count >= 6 else {
            return 0
        }

        let intervals = zip(beatTimes.dropFirst(), beatTimes)
            .map { $0 - $1 }
            .filter { $0 >= 0.32 && $0 <= 1.15 }
            .sorted()

        guard intervals.count >= 5 else {
            return 0
        }

        let medianInterval = intervals[intervals.count / 2]
        let closeIntervals = intervals.filter { abs($0 - medianInterval) / medianInterval < 0.18 }
        guard closeIntervals.count >= 4 else {
            return 0
        }

        let averageInterval = closeIntervals.reduce(0, +) / Double(closeIntervals.count)
        let variance = closeIntervals
            .map { pow($0 - averageInterval, 2) }
            .reduce(0, +) / Double(closeIntervals.count)
        let standardDeviation = sqrt(variance)
        guard standardDeviation / averageInterval < 0.16 else {
            return 0
        }

        let bpm = Int((60.0 / averageInterval).rounded())
        guard bpm >= 55 && bpm <= 175 else {
            return 0
        }

        return bpm
    }

    static func labelEnergy(_ energy: Double) -> String {
        switch energy {
        case ..<silenceEnergyThreshold:
            return "Silence"
        case ..<0.25:
            return "Low"
        case ..<0.55:
            return "Medium"
        default:
            return "High"
        }
    }

    private static func labelMood(energy: Double, valence: Double) -> String {
        guard energy >= silenceEnergyThreshold else {
            return "Waiting"
        }

        switch (energy, valence) {
        case (0.55..., 0.62...):
            return "Uplifting"
        case (0.55..., ..<0.62):
            return "Intense"
        case (..<0.35, 0.58...):
            return "Calm"
        case (..<0.35, ..<0.58):
            return "Soft"
        default:
            return "Warm"
        }
    }

    private static func labelEmotionColor(energy: Double, valence: Double) -> EmotionColor {
        guard energy >= silenceEnergyThreshold else {
            return .softMist
        }

        switch (energy, valence) {
        case (0.55..., 0.62...):
            return .upliftingCyan
        case (0.55..., ..<0.62):
            return .intenseIndigo
        case (..<0.35, 0.58...):
            return .calmBlue
        case (..<0.35, ..<0.58):
            return .softMist
        default:
            return .warmSky
        }
    }

    private func average(_ values: [Double], fallback: Double) -> Double {
        guard !values.isEmpty else { return fallback }
        return values.reduce(0, +) / Double(values.count)
    }

    private func mostCommon<Value: Hashable>(in counts: [Value: Int]) -> Value? {
        counts.max { $0.value < $1.value }?.key
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private static let silenceEnergyThreshold = 0.035
    private static let minimumBeatEnergy = 0.18

    private static func normalizedEnergy(fromRMS rms: Double) -> Double {
        guard rms > 0.0015 else { return 0 }

        // Map microphone RMS to a perceptual 0...1 range so quiet, medium, and loud music separate visibly.
        let decibels = 20 * log10(max(rms, 0.000_001))
        return clamp((decibels + 52) / 42, lower: 0.0, upper: 1.0)
    }
}

struct AudioFeatureResult {
    var snapshot: AudioSnapshot
    var summary: String
    var rollingEnergy: [Double] = []
    var beatTimes: [TimeInterval] = []
    var lastBeatTime: TimeInterval = 0
}

enum AudioAnalyzerError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Musense could not read that audio format."
        }
    }
}

extension AudioAnalyzer: SHSessionDelegate {
    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let mediaItem = match.mediaItems.first else {
            return
        }

        let song = RecognizedSong(
            title: mediaItem.title ?? "",
            artist: mediaItem.artist ?? "",
            artworkURL: mediaItem.artworkURL,
            webURL: mediaItem.webURL
        )

        DispatchQueue.main.async { [weak self] in
            guard let self, self.recognizedSong != song else { return }

            self.recognizedSong = song
            self.recognitionStatus = "Matched \(song.displayTitle)"
            self.statusText = "Matched \(song.displayTitle)"
            self.fetchLyrics(for: song)
        }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.recognizedSong == nil else { return }

            self.recognitionStatus = "No match"
        }
    }

    private func fetchLyrics(for song: RecognizedSong) {
        lyricsTask?.cancel()
        lyrics = ""

        lyricsTask = Task { [weak self] in
            guard let self else { return }

            let fetchedLyrics = await lyricsService.fetchLyrics(
                title: song.displayTitle,
                artist: song.displayArtist
            )

            await MainActor.run {
                guard !Task.isCancelled else { return }

                if let fetchedLyrics {
                    self.lyrics = fetchedLyrics
                    self.transcript = fetchedLyrics
                    self.recognitionStatus = "Matched"
                } else {
                    self.recognitionStatus = "Matched"
                }
            }
        }
    }
}
