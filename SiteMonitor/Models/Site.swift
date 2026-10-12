import Foundation

nonisolated struct Site: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var url: URL
    var expectedText: String = ""
    var checksInertiaSSR: Bool = false

    var host: String {
        let host = url.host() ?? url.absoluteString
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }
}

nonisolated extension Site {
    private enum CodingKeys: String, CodingKey {
        case id, name, url, expectedText, checksInertiaSSR
    }

    // Fields added later are optional when reading, so a sites.json from an older version still loads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
        expectedText = try container.decodeIfPresent(String.self, forKey: .expectedText) ?? ""
        checksInertiaSSR = try container.decodeIfPresent(Bool.self, forKey: .checksInertiaSSR) ?? false
    }
}

extension Site {
    static let defaults: [Site] = [
        Site(name: "CompactCode", url: URL(string: "https://compactcode.eu")!),
        Site(name: "EHALE", url: URL(string: "https://ehale.eu")!),
        Site(name: "ACGT17", url: URL(string: "https://acgt17.be")!, checksInertiaSSR: true),
    ]

    static func url(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return nil
        }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host() else {
            return nil
        }
        let isWebAddress = (scheme == "http" || scheme == "https") && host.contains(".")
        return isWebAddress ? url : nil
    }
}
