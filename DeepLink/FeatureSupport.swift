import AVFoundation
import Foundation

enum AgentInstallInstructions {
    static func installerURL(for enrollmentURL: URL) -> URL {
        enrollmentURL.appendingPathComponent("install.sh")
    }

    static func command(for enrollmentURL: URL) -> String {
        "curl -fsSL '\(installerURL(for: enrollmentURL).absoluteString)' | sh"
    }
}

enum DeepSeekTokenCandidate {
    private static let preferredKeys = [
        "value", "token", "userToken", "access_token", "accessToken", "authorization",
    ]

    static func values(key: String, raw: String) -> [String] {
        let normalizedKey = key.lowercased()
        guard normalizedKey.contains("token")
                || normalizedKey.contains("auth")
                || normalizedKey.contains("session")
                || normalizedKey.contains("credential") else {
            return []
        }

        let decoded = raw.removingPercentEncoding ?? raw
        var candidates: [String] = []
        if let data = decoded.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            collect(from: object, into: &candidates)
        } else if let candidate = normalize(decoded) {
            candidates.append(candidate)
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func collect(from object: Any, into candidates: inout [String]) {
        if let value = object as? String, let candidate = normalize(value) {
            candidates.append(candidate)
            return
        }
        if let dictionary = object as? [String: Any] {
            for key in preferredKeys {
                if let value = dictionary[key] {
                    collect(from: value, into: &candidates)
                }
            }
            for (key, value) in dictionary where !preferredKeys.contains(key) {
                let lowercased = key.lowercased()
                if lowercased.contains("token") || lowercased.contains("auth") || lowercased.contains("session") {
                    collect(from: value, into: &candidates)
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                collect(from: value, into: &candidates)
            }
        }
    }

    private static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard value.count >= 20, !value.contains("\n"), !value.contains("\r") else { return nil }
        return value
    }
}

enum VoiceAudioFile {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func isPlayable(filename: String?, directory: URL = documentsDirectory) -> Bool {
        guard let filename, !filename.isEmpty else { return false }
        let url = directory.appendingPathComponent(filename)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 44 else {
            return false
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        return player.duration > 0
    }
}

extension Notification.Name {
    static let deepSeekCredentialDidChange = Notification.Name("deepSeekCredentialDidChange")
}
