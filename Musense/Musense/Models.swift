import SwiftUI

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case waves
    case bars
    case glow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waves:
            "Waves"
        case .bars:
            "Bars"
        case .glow:
            "Glow"
        }
    }

    var iconName: String {
        switch self {
        case .waves:
            "water.waves"
        case .bars:
            "chart.bar.fill"
        case .glow:
            "sparkles"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case saved
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .saved:
            "Saved"
        case .live:
            "Live"
        }
    }
}

enum EmotionColor: String, CaseIterable, Hashable {
    case calmBlue
    case warmSky
    case upliftingCyan
    case intenseIndigo
    case softMist

    var title: String {
        switch self {
        case .calmBlue:
            "Calm Blue"
        case .warmSky:
            "Warm Sky"
        case .upliftingCyan:
            "Uplifting Cyan"
        case .intenseIndigo:
            "Intense Indigo"
        case .softMist:
            "Soft Mist"
        }
    }

    var color: Color {
        switch self {
        case .calmBlue:
            .musenseSky
        case .warmSky:
            .musenseAccent
        case .upliftingCyan:
            Color(red: 0.20, green: 0.82, blue: 1.00)
        case .intenseIndigo:
            .musenseBlue
        case .softMist:
            .musenseMist
        }
    }
}

struct RecognizedSong: Equatable, Hashable {
    var title: String
    var artist: String
    var artworkURL: URL?
    var webURL: URL?

    var displayTitle: String {
        title.isEmpty ? "Recognized Song" : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }
}

struct MusicSession: Identifiable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var timestamp: String
    var mood: String
    var energy: String
    var tempo: Int
    var valence: Double
    var danceability: Double
    var isLiveSession: Bool
    var isSaved: Bool
    var summary: String
    var transcript: String
    var emotionColor: EmotionColor

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        timestamp: String,
        mood: String,
        energy: String,
        tempo: Int,
        valence: Double,
        danceability: Double,
        isLiveSession: Bool,
        isSaved: Bool,
        summary: String,
        transcript: String = "",
        emotionColor: EmotionColor = .calmBlue
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.timestamp = timestamp
        self.mood = mood
        self.energy = energy
        self.tempo = tempo
        self.valence = valence
        self.danceability = danceability
        self.isLiveSession = isLiveSession
        self.isSaved = isSaved
        self.summary = summary
        self.transcript = transcript
        self.emotionColor = emotionColor
    }
}

extension MusicSession {
    static let demoSessions: [MusicSession] = [
        MusicSession(
            title: "Golden Hour",
            artist: "JVKE",
            album: "This Is What ____ Feels Like",
            timestamp: "3 days ago",
            mood: "Warm",
            energy: "High",
            tempo: 124,
            valence: 0.78,
            danceability: 0.71,
            isLiveSession: false,
            isSaved: true,
            summary: "A bright, swelling track with a warm emotional arc and a strong beat for haptic pulses."
        ),
        MusicSession(
            title: "Sunflower",
            artist: "Post Malone, Swae Lee",
            album: "Spider-Man: Into the Spider-Verse",
            timestamp: "1 week ago",
            mood: "Uplifting",
            energy: "Medium",
            tempo: 90,
            valence: 0.84,
            danceability: 0.76,
            isLiveSession: false,
            isSaved: true,
            summary: "Smooth, relaxed, and optimistic with steady rhythmic motion."
        ),
        MusicSession(
            title: "Dining Hall Loop",
            artist: "Live listen",
            album: "Ambient capture",
            timestamp: "2 weeks ago",
            mood: "Busy",
            energy: "Variable",
            tempo: 118,
            valence: 0.53,
            danceability: 0.58,
            isLiveSession: true,
            isSaved: false,
            summary: "A live ambient scan with changing energy and mixed background rhythm."
        )
    ]

    static let livePreview = MusicSession(
        title: "Live Listen",
        artist: "Nearby audio",
        album: "Real-time capture",
        timestamp: "Now",
        mood: "Analyzing",
        energy: "Building",
        tempo: 120,
        valence: 0.66,
        danceability: 0.69,
        isLiveSession: true,
        isSaved: false,
        summary: "Musense is listening for rhythm, intensity, and emotional color."
    )
}

extension Color {
    static let musenseBlue = Color(red: 0.05, green: 0.28, blue: 0.63) // #0D47A1
    static let musenseIndigo = Color(red: 0.08, green: 0.40, blue: 0.88) // #1565E0
    static let musenseAccent = Color(red: 0.24, green: 0.55, blue: 1.00) // #3D8BFF
    static let musenseSky = Color(red: 0.42, green: 0.71, blue: 1.00) // #6CB4FF
    static let musenseMist = Color(red: 0.90, green: 0.94, blue: 1.00) // #E6F0FF
    static let musensePink = Color(red: 0.42, green: 0.71, blue: 1.00)
    static let musenseCream = Color(red: 0.90, green: 0.94, blue: 1.00)
}

extension ShapeStyle where Self == Color {
    static var musenseBlue: Color { .musenseBlue }
    static var musenseIndigo: Color { .musenseIndigo }
    static var musenseAccent: Color { .musenseAccent }
    static var musensePink: Color { .musensePink }
    static var musenseSky: Color { .musenseSky }
    static var musenseMist: Color { .musenseMist }
    static var musenseCream: Color { .musenseCream }
}

extension Font {
    static func musense(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Manrope", size: size).weight(weight)
    }
}
