import Foundation

/// Italian formatting helpers that behave the same on iOS and Linux.
public enum SweepFormat {
    /// "1.234" (dot as thousands separator).
    public static func count(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    /// "1 foto", "1.234 foto".
    public static func photos(_ n: Int) -> String {
        "\(count(n)) foto"
    }

    /// Decimal (base 1000) sizes like the iOS storage screen: "820 KB", "12,4 MB", "1,25 GB".
    public static func bytes(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b < 1_000 { return "\(Int(b)) B" }
        if b < 1_000_000 { return "\(Int((b / 1_000).rounded())) KB" }
        if b < 1_000_000_000 { return decimal(b / 1_000_000, digits: 1) + " MB" }
        return decimal(b / 1_000_000_000, digits: 2) + " GB"
    }

    /// Video length: "0:07", "12:30", "1:02:03".
    public static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let ss = s < 10 ? "0\(s)" : "\(s)"
        if h > 0 {
            let mm = m < 10 ? "0\(m)" : "\(m)"
            return "\(h):\(mm):\(ss)"
        }
        return "\(m):\(ss)"
    }

    /// Number with a comma as decimal separator and trailing zeros removed.
    static func decimal(_ value: Double, digits: Int) -> String {
        var factor = 1.0
        for _ in 0..<digits { factor *= 10 }
        let rounded = (value * factor).rounded() / factor
        let whole = Int(rounded)
        var fraction = Int(((rounded - Double(whole)) * factor).rounded())
        if fraction == 0 { return "\(whole)" }
        var fractionDigits = digits
        while fraction % 10 == 0 { fraction /= 10; fractionDigits -= 1 }
        var f = String(fraction)
        while f.count < fractionDigits { f = "0" + f }
        return "\(whole),\(f)"
    }
}

/// Which items of an album are proposed.
public enum MediaFilter: String, CaseIterable, Codable, Sendable {
    case all, photos, videos

    public var title: String {
        switch self {
        case .all: return "Tutto"
        case .photos: return "Foto"
        case .videos: return "Video"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .photos: return "photo"
        case .videos: return "video"
        }
    }
}

/// Order in which photos are proposed.
public enum SweepOrder: String, CaseIterable, Codable, Sendable {
    case newestFirst, oldestFirst, largestFirst, random

    public var title: String {
        switch self {
        case .newestFirst: return "Recenti"
        case .oldestFirst: return "Vecchie"
        case .largestFirst: return "Più pesanti"
        case .random: return "Casuale"
        }
    }

    public var icon: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        case .largestFirst: return "externaldrive"
        case .random: return "shuffle"
        }
    }

    /// True when the order needs the file sizes.
    public var needsSizes: Bool { self == .largestFirst }

    /// Applies the order to ids that are already sorted newest first.
    /// `sizes` (bytes per id) is used by `.largestFirst`; equal or unknown
    /// sizes keep the newest-first order.
    public func arrange(newestFirst ids: [String], sizes: [String: Int64] = [:]) -> [String] {
        switch self {
        case .newestFirst: return ids
        case .oldestFirst: return ids.reversed()
        case .random: return ids.shuffled()
        case .largestFirst:
            return ids.enumerated()
                .sorted { a, b in
                    let sa = sizes[a.element] ?? 0, sb = sizes[b.element] ?? 0
                    return sa != sb ? sa > sb : a.offset < b.offset
                }
                .map(\.element)
        }
    }
}
