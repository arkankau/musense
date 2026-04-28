import Foundation

struct LyricsService {
    func fetchLyrics(title: String, artist: String) async -> String? {
        let cleanTitle = cleanSongTitle(title)
        let cleanArtist = cleanArtistName(artist)

        guard !cleanTitle.isEmpty, !cleanArtist.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.lyrics.ovh"
        components.path = "/v1/\(cleanArtist)/\(cleanTitle)"

        guard let url = components.url else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let result = try JSONDecoder().decode(LyricsResponse.self, from: data)
            let lyrics = result.lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            return lyrics.isEmpty ? nil : lyrics
        } catch {
            return nil
        }
    }

    private func cleanSongTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "feat.", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanArtistName(_ artist: String) -> String {
        artist
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? artist
    }
}

private struct LyricsResponse: Decodable {
    var lyrics: String
}
