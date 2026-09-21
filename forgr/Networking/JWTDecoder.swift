import Foundation

/// The backend doesn't expose a `/me` endpoint — `username` lives in the JWT
/// payload itself, so the client reads it there. Only the payload is decoded
/// (base64url, no signature verification needed client-side); a malformed or
/// foreign token just yields `nil` rather than throwing.
enum JWTDecoder {
    private struct Payload: Decodable {
        let username: String
    }

    static func username(fromToken token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data).username
    }
}
