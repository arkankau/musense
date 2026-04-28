import Foundation

struct AudioRecognitionAPIService {
    var hasToken: Bool {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "AUDD_API_TOKEN") as? String else {
            return false
        }
        return !token.isEmpty && token != "YOUR_AUDD_TOKEN_HERE"
    }

    func recognize(fileURL: URL) async throws -> RecognizedSong? {
        guard hasToken,
              let token = Bundle.main.object(forInfoDictionaryKey: "AUDD_API_TOKEN") as? String else {
            throw AudioRecognitionAPIError.missingToken
        }

        var request = URLRequest(url: URL(string: "https://api.audd.io/")!)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        request.httpBody = multipartBody(
            boundary: boundary,
            token: token,
            fileName: fileURL.lastPathComponent,
            fileData: fileData
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AudioRecognitionAPIError.badResponse
        }

        let decoded = try JSONDecoder().decode(AudDResponse.self, from: data)
        guard decoded.status == "success", let result = decoded.result else {
            return nil
        }

        return RecognizedSong(
            title: result.title ?? "",
            artist: result.artist ?? "",
            artworkURL: result.appleMusic?.artworkURL,
            webURL: result.songLink.flatMap(URL.init(string:))
        )
    }

    private func multipartBody(boundary: String, token: String, fileName: String, fileData: Data) -> Data {
        var body = Data()

        appendField(name: "api_token", value: token, boundary: boundary, to: &body)
        appendField(name: "return", value: "apple_music,spotify", boundary: boundary, to: &body)

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: audio/x-caf\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }

    private func appendField(name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }
}

enum AudioRecognitionAPIError: LocalizedError {
    case missingToken
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "Add an AUDD_API_TOKEN build setting or Info.plist value to enable API song recognition."
        case .badResponse:
            "The audio recognition API returned an unexpected response."
        }
    }
}

private struct AudDResponse: Decodable {
    var status: String
    var result: AudDResult?
}

private struct AudDResult: Decodable {
    var title: String?
    var artist: String?
    var songLink: String?
    var appleMusic: AudDAppleMusic?

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case songLink = "song_link"
        case appleMusic = "apple_music"
    }
}

private struct AudDAppleMusic: Decodable {
    var artworkURL: URL?

    enum CodingKeys: String, CodingKey {
        case artworkURL = "artworkUrl100"
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
