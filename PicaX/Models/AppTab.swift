import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case favorites
    case explore
    case categories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "主页"
        case .favorites:
            "收藏"
        case .explore:
            "发现"
        case .categories:
            "分类"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house"
        case .favorites:
            "heart"
        case .explore:
            "safari"
        case .categories:
            "square.grid.2x2"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .favorites:
            "heart.fill"
        case .explore:
            "safari.fill"
        case .categories:
            "square.grid.2x2.fill"
        }
    }
}
