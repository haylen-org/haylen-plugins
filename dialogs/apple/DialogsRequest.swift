import Foundation

// A request of the app as the Lua API of the plugin sends it, after it checked every option, so a value that is missing takes its default.
struct DialogsRequest {
    enum Kind: String {
        case info
        case warning
        case error
    }

    // A named choice of file types, such as Images with `png` and `jpg`, whose extensions come without their dot.
    struct Filter {
        let name: String
        let extensions: [String]
    }

    let title: String
    let text: String
    let kind: Kind
    let buttons: [String]
    let multiple: Bool
    let name: String
    let data: Data
    let filters: [Filter]

    init(_ params: Any) {
        let values = params as? [String: Any] ?? [:]
        title = values["title"] as? String ?? ""
        text = values["text"] as? String ?? ""
        kind = Kind(rawValue: values["kind"] as? String ?? "") ?? .info
        buttons = values["buttons"] as? [String] ?? []
        multiple = values["multiple"] as? Bool ?? false
        name = values["name"] as? String ?? ""
        data = values["data"] as? Data ?? Data()
        let filterValues = values["filters"] as? [[String: Any]] ?? []
        filters = filterValues.map { Filter(name: $0["name"] as? String ?? "", extensions: $0["extensions"] as? [String] ?? []) }
    }

    // The extensions of every filter in order, once each.
    var extensions: [String] {
        var seen = Set<String>()
        return filters.flatMap(\.extensions).filter { seen.insert($0.lowercased()).inserted }
    }
}
