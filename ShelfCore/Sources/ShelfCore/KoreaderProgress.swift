import Foundation

/// A 0-based Kavita page index plus the optional EPUB scroll anchor.
///
/// Kavita stores this as `ProgressDto.pageNum` and `ProgressDto.bookScrollId`.
/// KOReader exchanges the same position as the `progress` string on
/// `PUT /api/Koreader/{apiKey}/syncs/progress`.
public struct DecodedKoreaderPosition: Equatable, Sendable {
    public var pageIndex: Int
    public var bookScrollId: String?

    public init(pageIndex: Int, bookScrollId: String? = nil) {
        self.pageIndex = pageIndex
        self.bookScrollId = bookScrollId
    }
}

public struct KoreaderSyncPayload: Encodable, Equatable, Sendable {
    public var document: String
    public var deviceId: String
    public var device: String
    public var percentage: Double
    public var progress: String
    public var timestamp: Int64

    public init(document: String, deviceId: String, device: String, percentage: Double, progress: String, timestamp: Int64) {
        self.document = document
        self.deviceId = deviceId
        self.device = device
        self.percentage = percentage
        self.progress = progress
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case document
        case deviceId = "device_id"
        case device
        case percentage
        case progress
        case timestamp
    }
}

/// Mirrors `Kavita.Services.Helpers.KoreaderHelper` so Shelf and KOReader share a page.
public enum KoreaderProgress {
    private static let docFragment = try! NSRegularExpression(pattern: #"DocFragment\[(\d+)\]"#)
    private static let justNumber = try! NSRegularExpression(pattern: #"^\d+$"#)
    private static let docFragmentHash = try! NSRegularExpression(pattern: #"^#_doc_fragment_?(\d+)"#)

    /// Page index Kavita's web reader writes. The last page is stored one past the end,
    /// which is how Kavita marks the chapter complete.
    public static func storedPageIndex(currentIndex: Int, pageCount: Int) -> Int {
        let index = max(0, currentIndex)
        guard pageCount > 0 else { return index }
        if index >= pageCount - 1 {
            return pageCount
        }
        return index
    }

    public static func encode(pageIndex: Int, format: MangaFormat, bookScrollId: String?) -> String {
        let fragmentIndex = pageIndex + 1
        guard format == .epub else {
            return String(fragmentIndex)
        }

        guard let target = scrollTarget(bookScrollId), !target.isEmpty else {
            return "/body/DocFragment[\(fragmentIndex)].0"
        }
        if target.lowercased().hasPrefix("id(") {
            return "/body/DocFragment[\(fragmentIndex)].0"
        }

        var fullPath = "/body/DocFragment[\(fragmentIndex)]/body/\(target)"
        if !fullPath.contains("/text()") && !fullPath.hasSuffix(".0") {
            fullPath += ".0"
        }
        return fullPath
    }

    public static func decode(_ progress: String) -> DecodedKoreaderPosition? {
        let trimmed = progress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let hashPage = firstCapture(docFragmentHash, in: trimmed) {
            return DecodedKoreaderPosition(pageIndex: max(0, hashPage - 1))
        }
        if firstMatch(justNumber, in: trimmed) != nil, let number = Int(trimmed) {
            return DecodedKoreaderPosition(pageIndex: max(0, number - 1))
        }

        let path = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard path.count >= 3 else { return nil }
        let pageIndex = pageNumber(in: path)

        guard path.count >= 6 else {
            return DecodedKoreaderPosition(pageIndex: pageIndex)
        }

        var lastPart = trimmed.components(separatedBy: "/body/").last ?? ""
        lastPart = lastPart.components(separatedBy: "/text()").first ?? lastPart
        if let dot = lastPart.lastIndex(of: "."), lastPart.index(after: dot) < lastPart.endIndex {
            let suffix = lastPart[lastPart.index(after: dot)...]
            if !suffix.isEmpty && suffix.allSatisfy(\.isNumber) {
                lastPart = String(lastPart[..<dot])
            }
        }

        let lastTag = path[5].uppercased()
        if lastTag == "A"
            || lastPart.range(of: "id(", options: .caseInsensitive) != nil
            || lastTag.hasPrefix("ID(") {
            return DecodedKoreaderPosition(pageIndex: pageIndex, bookScrollId: nil)
        }
        return DecodedKoreaderPosition(pageIndex: pageIndex, bookScrollId: "//body/\(lastPart)")
    }

    public static func payload(
        documentHash: String,
        deviceId: String,
        progress: String,
        pageIndex: Int,
        pageCount: Int,
        device: String = "Shelf",
        now: Date = Date()
    ) -> KoreaderSyncPayload {
        let percentage: Double
        if pageCount > 0 {
            percentage = Double(pageIndex) / Double(pageCount)
        } else {
            percentage = 0
        }
        return KoreaderSyncPayload(
            document: documentHash,
            deviceId: deviceId,
            device: device,
            percentage: percentage,
            progress: progress,
            timestamp: Int64(now.timeIntervalSince1970)
        )
    }

    private static func scrollTarget(_ bookScrollId: String?) -> String? {
        guard var target = bookScrollId?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
            return nil
        }
        if target.lowercased().hasPrefix("//body/") {
            target.removeFirst("//body/".count)
        }
        return target
    }

    private static func pageNumber(in path: [String], offset: Int = 2) -> Int {
        guard offset < path.count else { return 0 }
        guard let page = firstCapture(docFragment, in: path[offset]) else { return 0 }
        return max(0, page - 1)
    }

    private static func firstCapture(_ expression: NSRegularExpression, in text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[capture])
    }

    private static func firstMatch(_ expression: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..., in: text)
        return expression.firstMatch(in: text, range: range)
    }
}
