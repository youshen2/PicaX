import CryptoKit
import Foundation

extension ComicContentService {
    var hitomiDataDomain: String {
        let value = UserDefaults.standard.string(forKey: PlatformFeatureSettingsKey.hitomiDataDomain) ?? ""
        return PlatformFeatureSettings.normalizedDomain(value, fallback: "gold-usergeneratedcontent.net")
    }

    var hitomiPublicBaseURL: String {
        PlatformFeatureSettings.frontendBaseURL(for: .hitomi)
    }

    func loadHitomiExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        let path: String
        switch entry {
        case .latest:
            path = "index-all.nozomi"
        case .popular(let period):
            switch period {
            case .today:
                path = "popular/today-all.nozomi"
            case .week:
                path = "popular/week-all.nozomi"
            case .month:
                path = "popular/month-all.nozomi"
            case .year:
                path = "popular/year-all.nozomi"
            case .allTime:
                throw ComicContentError.unsupported("Hitomi 没有\(period.title)接口。")
            }
        case .random:
            path = "index-all.nozomi"
        case .search:
            throw ComicContentError.unsupported("Hitomi 搜索入口需要关键词；标签页已接入二进制索引。")
        }

        let pageSize = 24
        var ids = try await hitomiIDsFromNozomi(path: path, maxIDs: page * pageSize + pageSize)
        if entry == .random {
            ids.shuffle()
        }
        let start = max(0, (page - 1) * pageSize)
        guard start < ids.count else { return [] }
        return try await hitomiItems(for: Array(ids.dropFirst(start)), limit: pageSize)
    }

    func loadHitomiDetail(item: ComicListItem) async throws -> ComicDetailInfo {
        let id = try hitomiID(from: item.id)
        let brief = try await hitomiBrief(id: id)
        let jsURL = try hitomiURL(path: "galleries/\(id).js")
        let script = try await requestString(url: jsURL, headers: hitomiHeaders(referer: hitomiPublicBaseURL))
        guard let start = script.firstIndex(of: "{"), let end = script.lastIndex(of: "}") else {
            throw ComicContentError.invalidResponse("Hitomi galleries.js 缺少 JSON 数据。")
        }
        let jsonData = Data(script[start...end].utf8)
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ComicContentError.invalidResponse("Hitomi 详情 JSON 无法解析。")
        }

        let files = json["files"] as? [[String: Any]] ?? []
        let artists = hitomiNamedTags(json["artists"], key: "artist", namespace: "artist")
        let groups = hitomiNamedTags(json["groups"], key: "group", namespace: "group")
        let parodys = hitomiNamedTags(json["parodys"], key: "parody", namespace: "parody")
        let characters = hitomiNamedTags(json["characters"], key: "character", namespace: "character")
        let tags = hitomiGalleryTags(json["tags"])
        let type = (json["type"] as? String ?? brief.type).trimmingCharacters(in: .whitespacesAndNewlines)
        let language = (json["language"] as? String ?? brief.language).trimmingCharacters(in: .whitespacesAndNewlines)
        let typeTags = type.isEmpty ? [] : [ComicTagReference(title: type, query: type.lowercased(), platform: .hitomi, urlString: nil)]
        let languageTags = language.isEmpty ? [] : [ComicTagReference(title: language, query: "language:\(language.lowercased())", platform: .hitomi, urlString: nil)]
        let tagGroups = [
            ComicTagGroup(title: "类型", tags: typeTags),
            ComicTagGroup(title: "语言", tags: languageTags),
            ComicTagGroup(title: "作者", tags: artists),
            ComicTagGroup(title: "分组", tags: groups),
            ComicTagGroup(title: "原作", tags: parodys),
            ComicTagGroup(title: "角色", tags: characters),
            ComicTagGroup(title: "标签", tags: tags.isEmpty ? brief.tags : tags)
        ].filter { !$0.tags.isEmpty }

        let detailItem = ComicListItem(
            id: brief.item.id,
            platform: .hitomi,
            title: json["title"] as? String ?? brief.item.title,
            subtitle: artists.first?.title ?? brief.item.subtitle,
            coverURLString: brief.item.coverURLString.isEmpty ? item.coverURLString : brief.item.coverURLString,
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: files.count,
            likesCount: nil,
            favoriteDate: item.favoriteDate
        )

        var relatedItems = [ComicListItem]()
        for relatedID in hitomiRelatedIDs(json["related"]).prefix(6) {
            if let related = try? await hitomiBrief(id: "\(relatedID)") {
                relatedItems.append(related.item)
            }
        }

        return ComicDetailInfo(
            item: detailItem,
            description: "",
            tagGroups: tagGroups,
            chapters: singleReaderChapter(),
            related: relatedItems,
            updatedText: json["date"] as? String ?? brief.updatedText
        )
    }

    func searchHitomi(tag: ComicTagReference, page: Int) async throws -> [ComicListItem] {
        let ids = try await hitomiSearchIDs(query: tag.query)
        let pageSize = 24
        let start = max(0, (page - 1) * pageSize)
        guard start < ids.count else { return [] }
        return try await hitomiItems(for: Array(ids.dropFirst(start)), limit: pageSize)
    }

    func hitomiItems(for ids: [Int], limit: Int) async throws -> [ComicListItem] {
        var items = [ComicListItem]()
        for id in ids.prefix(limit * 2) {
            if let brief = try? await hitomiBrief(id: "\(id)") {
                items.append(brief.item)
            }
            if items.count >= limit {
                break
            }
        }
        guard !items.isEmpty else {
            throw ComicContentError.invalidResponse("Hitomi 没有返回可展示的漫画。")
        }
        return items
    }

    func hitomiBrief(id: String) async throws -> HitomiBrief {
        let url = try hitomiURL(path: "galleryblock/\(id).html")
        let html = try await requestString(url: url, headers: hitomiHeaders(referer: hitomiPublicBaseURL))
        let title = html.firstRegexCapture(#"<h1[^>]*class="[^"]*lillie[^"]*"[^>]*>\s*<a[^>]*>(.*?)</a>"#)?.htmlDecoded ?? id
        let linkPath = html.firstRegexCapture(#"<h1[^>]*class="[^"]*lillie[^"]*"[^>]*>\s*<a[^>]+href="([^"]+)""#) ?? "/galleries/\(id).html"
        let artist = html.firstRegexCapture(#"<div[^>]*class="[^"]*artist-list[^"]*"[^>]*>.*?<a[^>]*>(.*?)</a>"#)?.htmlDecoded ?? "N/A"
        let coverSource = html.firstRegexCapture(#"<div[^>]*class="[^"]*(?:dj-img1|cg-img1)[^"]*"[^>]*>.*?<source[^>]+data-srcset="([^"]+)""#)
        let tags = hitomiBriefTags(html)
        let item = ComicListItem(
            id: absoluteURL(linkPath, baseURL: hitomiPublicBaseURL),
            platform: .hitomi,
            title: title,
            subtitle: artist,
            coverURLString: hitomiCoverURL(from: coverSource),
            tags: tags.map(\.title),
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
        return HitomiBrief(
            item: item,
            type: hitomiTableValue(html, label: "Type"),
            language: hitomiTableValue(html, label: "Language"),
            tags: tags,
            updatedText: html.firstRegexCapture(#"<div[^>]*class="[^"]*dj-content[^"]*"[^>]*>.*?<p[^>]*>(.*?)</p>"#)?.htmlDecoded
        )
    }

    func hitomiSearchIDs(query: String) async throws -> [Int] {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: " ")
        guard !normalized.isEmpty else {
            return try await hitomiIDsFromNozomi(path: "index-all.nozomi", maxIDs: 80)
        }
        if normalized.contains(":") {
            return try await hitomiIDsForNamespacedQuery(normalized)
        }

        let version = try await hitomiIndexVersion()
        let key = Array(SHA256.hash(data: Data(normalized.utf8)).prefix(4))
        let node = try await hitomiIndexNode(field: "galleries", address: 0, version: version)
        guard let dataRange = try await hitomiBSearch(field: "galleries", key: key, node: node, version: version) else {
            return []
        }
        return try await hitomiIDsFromIndexData(offset: dataRange.offset, length: dataRange.length, version: version)
    }

    func hitomiIDsForNamespacedQuery(_ query: String) async throws -> [Int] {
        let parts = query.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        let namespace = parts[0]
        let value = parts[1]
        if namespace == "language" {
            return try await hitomiIDsFromNozomi(path: "n/index-\(value).nozomi", maxIDs: 120)
        }
        let area: String
        let tag: String
        if namespace == "female" || namespace == "male" {
            area = "tag"
            tag = query
        } else {
            area = namespace
            tag = value
        }
        return try await hitomiIDsFromNozomi(path: "n/\(area)/\(tag)-all.nozomi", maxIDs: 120)
    }

    func hitomiIDsFromNozomi(path: String, maxIDs: Int) async throws -> [Int] {
        let url = try hitomiURL(path: path)
        let end = max(3, maxIDs * 4 - 1)
        let data = try await requestData(url: url, headers: hitomiHeaders(referer: hitomiPublicBaseURL).merging(["Range": "bytes=0-\(end)"]) { _, new in new })
        return hitomiIDs(fromBigEndianData: data)
    }

    func hitomiIndexVersion() async throws -> String {
        let url = try hitomiURL(path: "galleriesindex/version?_=\(Int(Date().timeIntervalSince1970))")
        return try await requestString(url: url, headers: hitomiHeaders(referer: "\(hitomiPublicBaseURL)/search.html"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hitomiIndexNode(field: String, address: Int, version: String) async throws -> HitomiIndexNode {
        let url = try hitomiURL(path: "galleriesindex/\(field).\(version).index")
        let data = try await requestData(url: url, headers: hitomiHeaders(referer: "\(hitomiPublicBaseURL)/search.html").merging(["Range": "bytes=\(address)-\(address + 463)"]) { _, new in new })
        guard let node = hitomiDecodeNode(data) else {
            throw ComicContentError.invalidResponse("Hitomi 索引节点无法解析。")
        }
        return node
    }

    func hitomiBSearch(field: String, key: [UInt8], node: HitomiIndexNode, version: String) async throws -> (offset: Int, length: Int)? {
        let (found, index) = hitomiLocateKey(key, in: node)
        if found {
            guard index < node.data.count else { return nil }
            return node.data[index]
        }
        guard !node.subnodeAddresses.allSatisfy({ $0 == 0 }),
              index < node.subnodeAddresses.count,
              node.subnodeAddresses[index] > 0 else {
            return nil
        }
        let next = try await hitomiIndexNode(field: field, address: node.subnodeAddresses[index], version: version)
        return try await hitomiBSearch(field: field, key: key, node: next, version: version)
    }

    func hitomiIDsFromIndexData(offset: Int, length: Int, version: String) async throws -> [Int] {
        guard length > 4 else { return [] }
        let url = try hitomiURL(path: "galleriesindex/galleries.\(version).data")
        let data = try await requestData(url: url, headers: hitomiHeaders(referer: "\(hitomiPublicBaseURL)/search.html").merging(["Range": "bytes=\(offset)-\(offset + length - 1)"]) { _, new in new })
        let bytes = [UInt8](data)
        guard let count = hitomiInt32BE(bytes, at: 0), count > 0, bytes.count >= count * 4 + 4 else {
            return []
        }
        return stride(from: 0, to: count, by: 1).compactMap { index in
            hitomiInt32BE(bytes, at: 4 + index * 4)
        }
    }

    func hitomiDecodeNode(_ data: Data) -> HitomiIndexNode? {
        let bytes = [UInt8](data)
        var position = 0
        guard let numberOfKeys = hitomiInt32BE(bytes, at: position), numberOfKeys >= 0, numberOfKeys <= 32 else { return nil }
        position += 4

        var keys = [[UInt8]]()
        for _ in 0..<numberOfKeys {
            guard let keySize = hitomiInt32BE(bytes, at: position), keySize > 0, keySize <= 32, position + 4 + keySize <= bytes.count else {
                return nil
            }
            position += 4
            keys.append(Array(bytes[position..<(position + keySize)]))
            position += keySize
        }

        guard let numberOfData = hitomiInt32BE(bytes, at: position), numberOfData >= 0, numberOfData <= 32 else { return nil }
        position += 4
        var dataRanges = [(offset: Int, length: Int)]()
        for _ in 0..<numberOfData {
            guard let offset = hitomiUInt64BE(bytes, at: position), let length = hitomiInt32BE(bytes, at: position + 8) else {
                return nil
            }
            position += 12
            dataRanges.append((offset: Int(offset), length: length))
        }

        var subnodeAddresses = [Int]()
        for _ in 0..<17 {
            guard let address = hitomiUInt64BE(bytes, at: position) else { return nil }
            position += 8
            subnodeAddresses.append(Int(address))
        }
        return HitomiIndexNode(keys: keys, data: dataRanges, subnodeAddresses: subnodeAddresses)
    }

    func hitomiLocateKey(_ key: [UInt8], in node: HitomiIndexNode) -> (found: Bool, index: Int) {
        var compareResult = -1
        var index = 0
        while index < node.keys.count {
            compareResult = hitomiCompare(key, node.keys[index])
            if compareResult <= 0 {
                break
            }
            index += 1
        }
        return (compareResult == 0, index)
    }

    func hitomiCompare(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        for index in 0..<min(lhs.count, rhs.count) {
            if lhs[index] < rhs[index] { return -1 }
            if lhs[index] > rhs[index] { return 1 }
        }
        return 0
    }

    func hitomiIDs(fromBigEndianData data: Data) -> [Int] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - (bytes.count % 4), by: 4).compactMap { offset in
            hitomiInt32BE(bytes, at: offset)
        }
    }

    func hitomiInt32BE(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let value = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        return Int(Int32(bitPattern: value))
    }

    func hitomiUInt64BE(_ bytes: [UInt8], at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= bytes.count else { return nil }
        return bytes[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    func hitomiID(from target: String) throws -> String {
        if Int(target) != nil {
            return target
        }
        if let id = target.firstRegexCapture(#"([0-9]+)(?=\.html)"#) ?? target.firstRegexCapture(#"([0-9]+)"#) {
            return id
        }
        throw ComicContentError.invalidURL("Hitomi ID \(target)")
    }

    func hitomiURL(path: String) throws -> URL {
        var rawPath = path.hasPrefix("/") ? path : "/\(path)"
        if rawPath.contains("?") {
            let parts = rawPath.split(separator: "?", maxSplits: 1).map(String.init)
            rawPath = (parts.first ?? rawPath).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).map { "\($0)?\(parts.dropFirst().first ?? "")" } ?? rawPath
        } else {
            rawPath = rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPath
        }
        guard let url = URL(string: "https://ltn.\(hitomiDataDomain)\(rawPath)") else {
            throw ComicContentError.invalidURL("Hitomi \(path)")
        }
        return url
    }

    func hitomiHeaders(referer: String) -> [String: String] {
        webHeaders(referer: referer).merging(["Origin": hitomiPublicBaseURL]) { _, new in new }
    }

    func hitomiCoverURL(from source: String?) -> String {
        guard var cover = source?.trimmingCharacters(in: .whitespacesAndNewlines), !cover.isEmpty else {
            return ""
        }
        if cover.hasPrefix("//") {
            cover = String(cover.dropFirst(2))
            if let slash = cover.firstIndex(of: "/") {
                cover = String(cover[slash...])
            }
        }
        if let range = cover.range(of: #"2x.*"#, options: .regularExpression) {
            cover.removeSubrange(range)
        }
        cover = cover.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "avifbigtn", with: "webpbigtn")
            .replacingOccurrences(of: ".avif", with: ".webp")
        return cover.hasPrefix("http") ? cover : "https://atn.\(hitomiDataDomain)\(cover)"
    }

    func hitomiTableValue(_ html: String, label: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"<tr>\s*<td>\s*"# + escaped + #"\s*</td>\s*<td[^>]*>(.*?)</td>"#
        return html.firstRegexCapture(pattern)?.htmlDecoded ?? ""
    }

    func hitomiBriefTags(_ html: String) -> [ComicTagReference] {
        let rows = html.regexMatches(#"<td[^>]*class="[^"]*(?:series-list|relatedtags)[^"]*"[^>]*>.*?</td>"#, options: [.dotMatchesLineSeparators])
        return rows.flatMap { row in
            row.regexMatches(#"<a[^>]+href="([^"]+)"[^>]*>.*?</a>"#, options: [.dotMatchesLineSeparators]).compactMap { linkHTML -> ComicTagReference? in
                guard let link = linkHTML.firstRegexCapture(#"href="([^"]+)""#) else { return nil }
                let title = linkHTML.strippingHTML
                guard !title.isEmpty, title != "N/A" else { return nil }
                return ComicTagReference(title: title, query: hitomiQuery(title: title, link: link), platform: .hitomi, urlString: absoluteURL(link, baseURL: hitomiPublicBaseURL))
            }
        }
    }

    func hitomiNamedTags(_ value: Any?, key: String, namespace: String) -> [ComicTagReference] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let title = (item[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return nil
            }
            let url = (item["url"] as? String).map { absoluteURL($0, baseURL: "https://ltn.\(hitomiDataDomain)") }
            return ComicTagReference(title: title, query: "\(namespace):\(title.lowercased())", platform: .hitomi, urlString: url)
        }
    }

    func hitomiGalleryTags(_ value: Any?) -> [ComicTagReference] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let name = (item["tag"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            let isFemale = hitomiBool(item["female"])
            let isMale = hitomiBool(item["male"])
            let title = name + (isFemale ? " ♀" : isMale ? " ♂" : "")
            let namespace = isFemale ? "female" : isMale ? "male" : "tag"
            let url = (item["url"] as? String).map { absoluteURL($0, baseURL: "https://ltn.\(hitomiDataDomain)") }
            return ComicTagReference(title: title, query: "\(namespace):\(name.lowercased())", platform: .hitomi, urlString: url)
        }
    }

    func hitomiQuery(title: String, link: String) -> String {
        let decoded = (link.removingPercentEncoding ?? link).lowercased()
        for namespace in ["artist", "group", "series", "character", "tag", "language"] {
            guard let range = decoded.range(of: "/\(namespace)/") else { continue }
            var value = String(decoded[range.upperBound...])
            if let end = value.range(of: "-all")?.lowerBound ?? value.range(of: ".html")?.lowerBound {
                value = String(value[..<end])
            }
            return namespace == "tag" ? value : "\(namespace):\(value)"
        }
        return title.lowercased()
    }

    func hitomiRelatedIDs(_ value: Any?) -> [Int] {
        if let values = value as? [Int] {
            return values
        }
        if let values = value as? [String] {
            return values.compactMap(Int.init)
        }
        return []
    }

    func hitomiBool(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int == 1 }
        if let string = value as? String { return string == "1" || string.lowercased() == "true" }
        return false
    }

    func loadHitomiImages(item: ComicListItem) async throws -> [String] {
        let id = try hitomiID(from: item.id)
        let jsURL = try hitomiURL(path: "galleries/\(id).js")
        let script = try await requestString(url: jsURL, headers: hitomiHeaders(referer: hitomiPublicBaseURL))
        guard let start = script.firstIndex(of: "{"), let end = script.lastIndex(of: "}") else {
            throw ComicContentError.invalidResponse("Hitomi galleries.js 缺少 JSON 数据。")
        }
        let jsonData = Data(script[start...end].utf8)
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ComicContentError.invalidResponse("Hitomi 详情 JSON 无法解析。")
        }
        let gg = try await hitomiGG(galleryID: id)
        let files = json["files"] as? [[String: Any]] ?? []
        return files.compactMap { file in
            guard let hash = file["hash"] as? String, !hash.isEmpty else { return nil }
            let name = file["name"] as? String ?? "\(hash).webp"
            let ext = (file.intValue(for: "haswebp") == 1) ? "webp" : (name.components(separatedBy: ".").last ?? "jpg")
            return hitomiImageURL(hash: hash, ext: ext, gg: gg)
        }
    }

    func hitomiGG(galleryID: String) async throws -> HitomiGGData {
        let url = try hitomiURL(path: "gg.js?_=1683939645979")
        let js = try await requestString(url: url, headers: hitomiHeaders(referer: "\(hitomiPublicBaseURL)/reader/\(galleryID).html"))
        let numbers = js.regexMatches(#"(?<=case )\d+"#)
        let b = js.firstRegexCapture(#"b: '(\d+)"#) ?? "0"
        let initialG = js.firstRegexCapture(#"var o = ([0-9]+)"#).flatMap(Int.init) ?? 1
        return HitomiGGData(numbers: Set(numbers), b: b, initialG: initialG)
    }

    func hitomiImageURL(hash: String, ext: String, gg: HitomiGGData) -> String {
        let path = "\(gg.b)/\(hitomiHashSuffix(hash))/\(hash)"
        let raw = "https://\(hitomiDataDomain)/\(path).\(ext)"
        return raw.replacingOccurrences(of: "https://", with: "https://\(hitomiSubdomain(from: raw, base: "w", gg: gg)).")
    }

    func hitomiHashSuffix(_ hash: String) -> String {
        guard hash.count >= 3 else { return "" }
        let lastTwoStart = hash.index(hash.endIndex, offsetBy: -3)
        let pairStart = hash.index(hash.endIndex, offsetBy: -2)
        let pair = String(hash[pairStart...])
        let single = String(hash[lastTwoStart])
        return Int(single + pair, radix: 16).map(String.init) ?? ""
    }

    func hitomiSubdomain(from url: String, base: String, gg: HitomiGGData) -> String {
        let pattern = #"/[0-9a-f]{61}([0-9a-f]{2})([0-9a-f])"#
        guard let match = url.firstRegexCapturePair(pattern),
              let value = Int(match.1 + match.0, radix: 16) else {
            return "a"
        }
        let bit = gg.numbers.contains("\(value)") ? (~gg.initialG & 1) : gg.initialG
        let character = bit == 0 ? "a" : "b"
        if base == "w" {
            return character == "a" ? "w1" : "w2"
        }
        return "\(character)\(base)"
    }
}

struct HitomiBrief {
    let item: ComicListItem
    let type: String
    let language: String
    let tags: [ComicTagReference]
    let updatedText: String?
}

struct HitomiIndexNode {
    let keys: [[UInt8]]
    let data: [(offset: Int, length: Int)]
    let subnodeAddresses: [Int]
}

struct HitomiGGData {
    let numbers: Set<String>
    let b: String
    let initialG: Int
}
