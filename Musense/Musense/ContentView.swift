import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var audioAnalyzer = AudioAnalyzer()
    @StateObject private var musicIntegration = MusicIntegrationService()

    var body: some View {
        Group {
            if appState.didCompleteOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .environmentObject(appState)
        .environmentObject(audioAnalyzer)
        .environmentObject(musicIntegration)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .tint(.musenseIndigo)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            MusenseBackground()

            VStack(alignment: .leading, spacing: 26) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    MusenseLogoLockup(size: 86, showsWordmark: true)

                    Text("Feel the music.")
                        .font(.musense(22, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                CalibrationCard()

                Button {
                    appState.playHaptic()
                    appState.didCompleteOnboarding = true
                } label: {
                    Text("Start Listening")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.musenseIndigo)
                .controlSize(.large)

                Spacer()
            }
            .padding(24)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var audioAnalyzer: AudioAnalyzer
    @EnvironmentObject private var musicIntegration: MusicIntegrationService
    @State private var searchText = ""
    @State private var isImporterPresented = false
    @State private var isAnalyzingFile = false
    @State private var uploadMessage: String?

    var filteredSessions: [MusicSession] {
        guard !searchText.isEmpty else { return appState.sessions }
        return appState.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var homeStatusLine: String? {
        if let song = audioAnalyzer.recognizedSong {
            return "Matched \(song.displayTitle)"
        }
        if !audioAnalyzer.recognitionStatus.isEmpty {
            return audioAnalyzer.recognitionStatus
        }
        return uploadMessage
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MusenseBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ModeSelector(
                            onUpload: { isImporterPresented = true },
                            onStream: {
                                musicIntegration.requestAppleMusicAccess()
                                musicIntegration.openAppleMusicSearch()
                            }
                        )

                        NavigationLink {
                            LiveExperienceView(session: .livePreview)
                        } label: {
                            LiveListenCard()
                        }
                        .buttonStyle(.plain)

                        QuickActionsRow(
                            isAnalyzingFile: isAnalyzingFile,
                            onUpload: { isImporterPresented = true },
                            onConnect: {
                                musicIntegration.requestAppleMusicAccess()
                                musicIntegration.openSpotifySearch()
                            }
                        )

                        if let statusLine = homeStatusLine {
                            Text(statusLine)
                                .font(.musense(13, weight: .semibold))
                                .foregroundStyle(.musenseIndigo)
                                .padding(.horizontal, 4)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent")
                                .font(.title3.bold())
                                .foregroundStyle(.musenseBlue)

                            ForEach(filteredSessions) { session in
                                NavigationLink {
                                    SongDetailView(session: session)
                                } label: {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Musense")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MusenseLogoLockup(size: 30, showsWordmark: true)
                }
            }
            .searchable(text: $searchText, prompt: "Search songs or artists")
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleImportedAudio(result)
            }
        }
    }

    private func handleImportedAudio(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            isAnalyzingFile = true
            uploadMessage = "Analyzing \(url.lastPathComponent)"

            Task {
                do {
                    let session = try await audioAnalyzer.analyzeFile(at: url)
                    await MainActor.run {
                        appState.save(session)
                        uploadMessage = "Saved \(session.title)"
                        isAnalyzingFile = false
                    }
                } catch {
                    await MainActor.run {
                        uploadMessage = error.localizedDescription
                        isAnalyzingFile = false
                    }
                }
            }
        case .failure(let error):
            uploadMessage = error.localizedDescription
        }
    }
}

struct LiveExperienceView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var audioAnalyzer: AudioAnalyzer
    @Environment(\.dismiss) private var dismiss
    var session: MusicSession
    @State private var automaticBeatTask: Task<Void, Never>?

    private var displayedEnergy: String {
        session.isLiveSession ? audioAnalyzer.snapshot.energyLabel : session.energy
    }

    private var displayedMood: String {
        session.isLiveSession ? audioAnalyzer.snapshot.mood : session.mood
    }

    private var displayedTempo: Int {
        session.isLiveSession ? audioAnalyzer.snapshot.tempo : session.tempo
    }

    private var displayedTitle: String {
        session.isLiveSession ? (audioAnalyzer.recognizedSong?.displayTitle ?? session.title) : session.title
    }

    private var displayedArtist: String {
        session.isLiveSession ? (audioAnalyzer.recognizedSong?.displayArtist ?? session.artist) : session.artist
    }

    private var currentSession: MusicSession {
        session.isLiveSession ? audioAnalyzer.liveSession() : session
    }

    var body: some View {
        ZStack {
            MusenseBackground()

            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text(displayedTitle)
                            .font(.title.bold())
                            .foregroundStyle(.musenseBlue)

                        Text(displayedArtist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VisualizerView(style: appState.visualizerStyle, snapshot: session.isLiveSession ? audioAnalyzer.snapshot : nil)
                        .frame(height: 290)
                        .padding(.horizontal)
                        .onTapGesture {
                            appState.playHaptic()
                        }
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { _ in
                                    cycleVisualizerStyle()
                                }
                        )
                        .onLongPressGesture {
                            appState.hapticIntensity = min(appState.hapticIntensity + 0.15, 1.0)
                            appState.playHaptic()
                        }

                    Text(session.isLiveSession ? audioAnalyzer.statusText : "\(displayedTempo) BPM")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        InsightCard(title: "Energy", value: displayedEnergy, systemImage: "bolt.fill")
                        InsightCard(title: "Mood", value: displayedMood, systemImage: "face.smiling")
                        InsightCard(title: "Tempo", value: displayedTempo > 0 ? "\(displayedTempo)" : "--", systemImage: "metronome.fill")
                    }
                    .padding(.horizontal)

                    if session.isLiveSession {
                        LiveCaptureCard(
                            transcript: audioAnalyzer.lyrics.isEmpty ? audioAnalyzer.transcript : audioAnalyzer.lyrics,
                            emotionColor: audioAnalyzer.snapshot.emotionColor,
                            mood: audioAnalyzer.snapshot.mood,
                            beatCount: audioAnalyzer.beatCount,
                            recognitionStatus: audioAnalyzer.recognitionStatus
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    appState.save(currentSession)
                } label: {
                    Label("Save", systemImage: "bookmark.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.musenseIndigo)

                NavigationLink {
                    SongDetailView(session: currentSession)
                } label: {
                    Label("Details", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.musenseIndigo)
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if session.isLiveSession {
                audioAnalyzer.startMicrophone {
                    appState.playHaptic()
                }
            } else {
                startAutomaticBeatLoop()
            }
        }
        .onDisappear {
            stopAutomaticBeatLoop()

            if session.isLiveSession {
                audioAnalyzer.stopMicrophone()
            }
        }
        .alert("Audio Error", isPresented: Binding(
            get: { audioAnalyzer.errorMessage != nil },
            set: { if !$0 { audioAnalyzer.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(audioAnalyzer.errorMessage ?? "")
        }
    }

    private func cycleVisualizerStyle() {
        let styles = VisualizerStyle.allCases
        guard let currentIndex = styles.firstIndex(of: appState.visualizerStyle) else { return }

        let nextIndex = styles.index(after: currentIndex)
        appState.visualizerStyle = nextIndex == styles.endIndex ? styles[styles.startIndex] : styles[nextIndex]
        appState.playHaptic()
    }

    private func startAutomaticBeatLoop() {
        stopAutomaticBeatLoop()

        let tempo = max(displayedTempo, 60)
        let interval = UInt64((60.0 / Double(tempo)) * 1_000_000_000)

        automaticBeatTask = Task { @MainActor in
            while !Task.isCancelled {
                appState.playHaptic()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopAutomaticBeatLoop() {
        automaticBeatTask?.cancel()
        automaticBeatTask = nil
    }
}

struct SongDetailView: View {
    @EnvironmentObject private var appState: AppState
    var session: MusicSession

    var body: some View {
        ZStack {
            MusenseBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SongHeroCard(session: session)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        FeatureCard(title: "Tempo", value: session.tempo > 0 ? "\(session.tempo) BPM" : "—")
                        FeatureCard(title: "Energy", value: session.energy)
                        FeatureCard(title: "Valence", value: session.valence.formatted(.number.precision(.fractionLength(2))))
                        FeatureCard(title: "Dance", value: session.danceability.formatted(.number.precision(.fractionLength(2))))
                    }

                    EmotionColorCard(emotionColor: session.emotionColor, mood: session.mood)

                    Text(session.summary)
                        .font(.musense(14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .musenseCard()

                    if !session.transcript.isEmpty {
                        Text(session.transcript)
                            .font(.musense(14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .musenseCard()
                    }

                    NavigationLink {
                        LiveExperienceView(session: session)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.musenseIndigo)
                }
                .padding()
            }
        }
        .navigationTitle("Song Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: LibraryFilter = .all

    var filteredSessions: [MusicSession] {
        switch filter {
        case .all:
            return appState.sessions
        case .saved:
            return appState.sessions.filter(\.isSaved)
        case .live:
            return appState.sessions.filter(\.isLiveSession)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MusenseBackground()

                List {
                    Picker("Filter", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    ForEach(filteredSessions) { session in
                        NavigationLink {
                            SongDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        appState.deleteSessions(at: offsets, from: filteredSessions)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Library")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var musicIntegration: MusicIntegrationService

    var body: some View {
        NavigationStack {
            ZStack {
                MusenseBackground()

                Form {
                    Section("Accessibility") {
                        Slider(value: $appState.hapticIntensity, in: 0...1) {
                            Text("Haptic Intensity")
                        } minimumValueLabel: {
                            Image(systemName: "iphone")
                        } maximumValueLabel: {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                        }

                        Picker("Visualization Style", selection: $appState.visualizerStyle) {
                            ForEach(VisualizerStyle.allCases) { style in
                                Label(style.title, systemImage: style.iconName).tag(style)
                            }
                        }

                        Toggle("Reduced Motion", isOn: $appState.reducedMotion)
                    }

                    Section("Music Sources") {
                        Button {
                            musicIntegration.requestAppleMusicAccess()
                            musicIntegration.openAppleMusicSearch()
                        } label: {
                            LabeledContent {
                                Text(musicIntegration.appleMusicStatus)
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label("Apple Music", systemImage: "music.note")
                            }
                        }

                        Button {
                            musicIntegration.openSpotifySearch()
                        } label: {
                            LabeledContent {
                                Text(musicIntegration.spotifyStatus)
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label("Spotify", systemImage: "link")
                            }
                        }

                        Label("Upload local audio from Home", systemImage: "square.and.arrow.up")
                    }

                    Section("Data") {
                        Button(role: .destructive) {
                            appState.sessions.removeAll()
                        } label: {
                            Text("Clear saved sessions")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
    }
}

struct HeaderBlock: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.musense(34, weight: .bold))
                .foregroundStyle(.musenseBlue)

            Text(subtitle)
                .font(.musense(16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MusenseLogoLockup: View {
    var size: CGFloat
    var showsWordmark: Bool

    var body: some View {
        HStack(spacing: size * 0.14) {
            MusenseLogoMark()
                .frame(width: size, height: size)

            if showsWordmark {
                Text("Musense")
                    .font(.musense(size * 0.52, weight: .bold))
                    .foregroundStyle(.musenseBlue)
                    .tracking(-1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Musense")
    }
}

struct MusenseLogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.musenseBlue, .musenseIndigo, .musenseSky],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .musenseBlue.opacity(0.18), radius: 14, y: 8)

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: width * 0.22, y: height * 0.72))
                        path.addLine(to: CGPoint(x: width * 0.22, y: height * 0.28))
                        path.addQuadCurve(
                            to: CGPoint(x: width * 0.50, y: height * 0.50),
                            control: CGPoint(x: width * 0.33, y: height * 0.24)
                        )
                        path.addQuadCurve(
                            to: CGPoint(x: width * 0.78, y: height * 0.28),
                            control: CGPoint(x: width * 0.67, y: height * 0.24)
                        )
                        path.addLine(to: CGPoint(x: width * 0.78, y: height * 0.72))
                    }
                    .stroke(.white, style: StrokeStyle(lineWidth: width * 0.075, lineCap: .round, lineJoin: .round))

                    Circle()
                        .fill(.white)
                        .frame(width: width * 0.09, height: width * 0.09)
                        .position(x: width * 0.50, y: height * 0.68)

                    RadioArc(startAngle: .degrees(138), endAngle: .degrees(222))
                        .stroke(.white, style: StrokeStyle(lineWidth: width * 0.035, lineCap: .round))
                        .frame(width: width * 0.30, height: width * 0.30)
                        .position(x: width * 0.50, y: height * 0.68)

                    RadioArc(startAngle: .degrees(-42), endAngle: .degrees(42))
                        .stroke(.white, style: StrokeStyle(lineWidth: width * 0.035, lineCap: .round))
                        .frame(width: width * 0.30, height: width * 0.30)
                        .position(x: width * 0.50, y: height * 0.68)

                    RadioArc(startAngle: .degrees(132), endAngle: .degrees(228))
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: width * 0.028, lineCap: .round))
                        .frame(width: width * 0.48, height: width * 0.48)
                        .position(x: width * 0.50, y: height * 0.68)

                    RadioArc(startAngle: .degrees(-48), endAngle: .degrees(48))
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: width * 0.028, lineCap: .round))
                        .frame(width: width * 0.48, height: width * 0.48)
                        .position(x: width * 0.50, y: height * 0.68)
                }
            }
            .padding(10)
        }
    }
}

struct RadioArc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

struct CalibrationCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Calibrate Your Experience")
                .font(.musense(20, weight: .bold))
                .foregroundStyle(.musenseBlue)

            VStack(alignment: .leading) {
                Text("Haptic Intensity")
                    .font(.musense(15, weight: .bold))

                Slider(value: $appState.hapticIntensity, in: 0...1) {
                    Text("Haptic Intensity")
                }
            }

            Picker("Visualization Style", selection: $appState.visualizerStyle) {
                ForEach(VisualizerStyle.allCases) { style in
                    Label(style.title, systemImage: style.iconName).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Reduced Motion", isOn: $appState.reducedMotion)
        }
        .musenseCard()
    }
}

struct ModeSelector: View {
    var onUpload: () -> Void
    var onStream: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SourcePill(title: "Live", systemImage: "dot.radiowaves.left.and.right")
            Button(action: onUpload) {
                SourcePill(title: "Upload", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            Button(action: onStream) {
                SourcePill(title: "Stream", systemImage: "music.note")
            }
            .buttonStyle(.plain)
        }
    }
}

struct SourcePill: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.musense(14, weight: .bold))
            .foregroundStyle(.musenseBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white.opacity(0.78), in: Capsule())
            .overlay {
                Capsule().stroke(.musenseSky.opacity(0.9), lineWidth: 1)
            }
    }
}

struct LiveListenCard: View {
    var body: some View {
        HStack {
            Text("Live Listen")
                .font(.musense(26, weight: .bold))

            Spacer()

            MusenseLogoMark()
                .frame(width: 52, height: 52)
                .padding(8)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.musenseAccent, .musenseIndigo, .musenseBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .shadow(color: .musenseBlue.opacity(0.25), radius: 18, y: 8)
    }
}

struct QuickActionsRow: View {
    var isAnalyzingFile: Bool
    var onUpload: () -> Void
    var onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onUpload) {
                ActionCard(
                    title: isAnalyzingFile ? "Analyzing..." : "Upload",
                    systemImage: "folder.fill"
                )
            }
            .buttonStyle(.plain)

            Button(action: onConnect) {
                ActionCard(title: "Connect", systemImage: "link.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }
}

struct ActionCard: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.musenseAccent)

            Text(title)
                .font(.musense(16, weight: .bold))
                .foregroundStyle(.musenseBlue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .musenseCard()
    }
}

struct SessionRow: View {
    var session: MusicSession

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [.musenseAccent, .musenseSky], startPoint: .topLeading, endPoint: .bottomTrailing))

                if session.isLiveSession {
                    MusenseLogoMark()
                        .padding(12)
                } else {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.musense(17, weight: .bold))
                    .foregroundStyle(.primary)

                Text("\(session.artist) - \(session.timestamp)")
                    .font(.musense(14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(session.mood)
                    .font(.musense(12, weight: .bold))
                    .foregroundStyle(.musenseIndigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.musenseSky.opacity(0.45), in: Capsule())
            }

            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.8), lineWidth: 1)
        }
    }
}

struct VisualizerView: View {
    @EnvironmentObject private var appState: AppState
    var style: VisualizerStyle
    var snapshot: AudioSnapshot?

    var body: some View {
        if appState.reducedMotion {
            TimelineView(.periodic(from: .now, by: 1.2)) { timeline in
                visualizerContent(for: timeline.date)
            }
        } else {
            TimelineView(.animation) { timeline in
                visualizerContent(for: timeline.date)
            }
        }
    }

    @ViewBuilder
    private func visualizerContent(for date: Date) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36)
                .fill(
                    LinearGradient(
                            colors: [.musenseBlue, .musenseIndigo, .musenseAccent, .musenseSky],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            switch style {
            case .waves:
                WaveVisualizer(date: date, energy: snapshot?.energyValue)
            case .bars:
                BarVisualizer(date: date, levels: snapshot?.levels)
            case .glow:
                GlowVisualizer(date: date, energy: snapshot?.energyValue, mood: snapshot?.mood)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 36))
        .overlay(alignment: .topLeading) {
            Label(style.title, systemImage: style.iconName)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(16)
        }
    }
}

struct BarVisualizer: View {
    var date: Date
    var levels: [Double]?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<18, id: \.self) { index in
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(0.86))
                    .frame(width: 8, height: barHeight(for: index))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 42)
    }

    private func barHeight(for index: Int) -> CGFloat {
        if let levels, index < levels.count {
            return CGFloat(42 + levels[index] * 145)
        }

        let phase = date.timeIntervalSinceReferenceDate * 2.2 + Double(index) * 0.55
        return CGFloat(58 + sin(phase) * 36 + Double(index % 4) * 12)
    }
}

struct WaveVisualizer: View {
    var date: Date
    var energy: Double?

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .stroke(.white.opacity(0.18 + Double(index) * 0.08), lineWidth: 16)
                    .scaleEffect(waveScale(for: index))
            }

            Image(systemName: "music.note")
                .font(.system(size: 70, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
        }
        .padding(42)
    }

    private func waveScale(for index: Int) -> CGFloat {
        if let energy {
            return CGFloat(0.45 + energy * 0.45 + Double(index) * 0.18)
        }

        let phase = date.timeIntervalSinceReferenceDate * 0.9 + Double(index) * 0.75
        return CGFloat(0.52 + abs(sin(phase)) * 0.35 + Double(index) * 0.17)
    }
}

struct GlowVisualizer: View {
    var date: Date
    var energy: Double?
    var mood: String?

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? .musenseSky.opacity(0.52) : .musenseAccent.opacity(0.58))
                    .frame(width: glowSize(for: index), height: glowSize(for: index))
                    .offset(x: xOffset(for: index), y: yOffset(for: index))
                    .blur(radius: 8)
            }

            Text(mood ?? "High Energy")
                .font(.title.bold())
                .foregroundStyle(.white)
        }
    }

    private func glowSize(for index: Int) -> CGFloat {
        if let energy {
            return CGFloat(48 + energy * 118 + Double(index % 3) * 18)
        }

        let phase = date.timeIntervalSinceReferenceDate + Double(index)
        return CGFloat(62 + abs(sin(phase)) * 82)
    }

    private func xOffset(for index: Int) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate * 0.8 + Double(index)
        return CGFloat(cos(phase) * 95)
    }

    private func yOffset(for index: Int) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate * 0.7 + Double(index) * 0.8
        return CGFloat(sin(phase) * 76)
    }
}

struct InsightCard: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.musenseIndigo)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .foregroundStyle(.musenseBlue)
        }
        .frame(maxWidth: .infinity)
        .musenseCard()
    }
}

struct LiveCaptureCard: View {
    var transcript: String
    var emotionColor: EmotionColor
    var mood: String
    var beatCount: Int
    var recognitionStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(mood)
                    .font(.musense(20, weight: .heavy))
                    .foregroundStyle(emotionColor.color)

                Spacer()

                Text("\(beatCount)")
                    .font(.musense(14, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if !transcript.isEmpty {
                Text(transcript)
                    .font(.musense(14, weight: .semibold))
                    .foregroundStyle(emotionColor.color.opacity(0.85))
                    .lineLimit(3)
            }
        }
        .musenseCard()
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(emotionColor.color.opacity(0.35), lineWidth: 1)
        )
    }
}

struct EmotionColorCard: View {
    var emotionColor: EmotionColor
    var mood: String

    var body: some View {
        Text(mood)
            .font(.musense(34, weight: .heavy))
            .foregroundStyle(emotionColor.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .musenseCard()
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(emotionColor.color.opacity(0.4), lineWidth: 1)
            )
    }
}

struct PlaybackPreview: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("1:24")
                Spacer()
                Text("3:45")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: 0.38)
                .tint(.musenseIndigo)
        }
        .padding(.horizontal)
    }
}

struct SongHeroCard: View {
    var session: MusicSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [.musenseBlue, .musenseAccent, .musenseSky], startPoint: .topLeading, endPoint: .bottomTrailing))

                MusenseLogoMark()
                    .frame(width: 108, height: 108)
            }
            .frame(height: 210)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.musense(28, weight: .bold))
                    .foregroundStyle(.musenseBlue)

                Text("\(session.artist) - \(session.album)")
                    .font(.musense(15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .musenseCard()
    }
}

struct FeatureCard: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.musense(12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.musense(20, weight: .bold))
                .foregroundStyle(.musenseBlue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .musenseCard()
    }
}

struct MusenseBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.musenseMist, .white, .musenseSky.opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.musenseAccent.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: 120, y: -240)

            Circle()
                .fill(.musenseIndigo.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 46)
                .offset(x: -140, y: 260)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func musenseCard() -> some View {
        padding(16)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: .musenseBlue.opacity(0.08), radius: 16, y: 8)
    }
}

#Preview {
    ContentView()
}
