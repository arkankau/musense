import Foundation
import MediaPlayer
import UIKit

final class MusicIntegrationService: ObservableObject {
    @Published var appleMusicStatus = "Not connected"
    @Published var spotifyStatus = "Not connected"

    func requestAppleMusicAccess() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.appleMusicStatus = "Apple Music access granted"
                case .denied, .restricted:
                    self?.appleMusicStatus = "Apple Music access blocked"
                case .notDetermined:
                    self?.appleMusicStatus = "Apple Music permission pending"
                @unknown default:
                    self?.appleMusicStatus = "Apple Music status unknown"
                }
            }
        }
    }

    func openAppleMusicSearch() {
        open(urls: [
            URL(string: "music://"),
            URL(string: "https://music.apple.com/us/browse")
        ])
    }

    func openSpotifySearch() {
        spotifyStatus = "Opened Spotify handoff"
        open(urls: [
            URL(string: "spotify://"),
            URL(string: "https://open.spotify.com")
        ])
    }

    private func open(urls: [URL?]) {
        guard let url = urls.compactMap({ $0 }).first else { return }

        UIApplication.shared.open(url)
    }
}
