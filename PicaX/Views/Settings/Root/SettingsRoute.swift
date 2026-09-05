import Foundation

enum SettingsRoute: String, CaseIterable, Hashable, Identifiable {
    case platformAccounts
    case home
    case explore
    case search
    case comicList
    case comicDetail
    case reader
    case downloads
    case history
    case readingDuration
    case blockingKeywords
    case storage
    case backup
    case appDisplay
    case appBehavior
    case watchConnectivity
    case network
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .platformAccounts:
            "平台账号"
        case .home:
            "首页"
        case .explore:
            "发现页"
        case .search:
            "搜索"
        case .comicList:
            "漫画列表"
        case .comicDetail:
            "漫画详情"
        case .reader:
            "阅读器"
        case .downloads:
            "下载"
        case .history:
            "历史记录"
        case .readingDuration:
            "阅读时长"
        case .blockingKeywords:
            "关键词屏蔽"
        case .storage:
            "存储管理"
        case .backup:
            "备份与恢复"
        case .appDisplay:
            "显示"
        case .appBehavior:
            "App 行为"
        case .watchConnectivity:
            "Watch 互联"
        case .network:
            "网络与代理"
        case .about:
            "关于 PicaX"
        }
    }

    var systemImage: String {
        switch self {
        case .platformAccounts:
            "person.2"
        case .home:
            "house"
        case .explore:
            "safari"
        case .search:
            "magnifyingglass"
        case .comicList:
            "list.bullet.rectangle"
        case .comicDetail:
            "info.square"
        case .reader:
            "book"
        case .downloads:
            "arrow.down.circle"
        case .history:
            "clock.arrow.circlepath"
        case .readingDuration:
            "timer"
        case .blockingKeywords:
            "eye.slash"
        case .storage:
            "internaldrive"
        case .backup:
            "tray.full"
        case .appDisplay:
            "paintbrush"
        case .appBehavior:
            "gearshape"
        case .watchConnectivity:
            "applewatch"
        case .network:
            "network"
        case .about:
            "info.circle"
        }
    }

    func matches(_ query: String) -> Bool {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)

        guard !terms.isEmpty else { return true }

        let searchableText = ([title] + searchKeywords)
            .joined(separator: " ")
            .lowercased()

        return terms.allSatisfy { searchableText.contains($0) }
    }

    private var searchKeywords: [String] {
        switch self {
        case .platformAccounts:
            ComicPlatform.onlinePlatforms.map(\.title) + ["登录", "账号", "Cookie", "平台登录与账号管理"]
        case .home:
            ["阅读历史", "稍后再读", "追更", "阅读时长", "下载", "折叠", "卡片", "排序", "入口显示"]
        case .explore:
            ["发现", "默认来源", "平台选择", "记住"]
        case .search:
            ["默认搜索源", "搜索历史", "聚合搜索", "补全", "标签", "E-Hentai", "中文", "英文", "翻译"]
        case .comicList:
            ["布局", "瀑布流", "已读隐藏", "稍后再读", "阅读进度", "收藏状态", "标签", "热度", "漫画名称", "标题相似度", "跨平台阅读记录"]
        case .comicDetail:
            ["封面颜色", "章节排序", "章节分区", "内容顺序"]
        case .reader:
            ["自动翻页", "持续滚动", "点按翻页", "缩放", "预加载", "下一章", "浮动按钮", "状态栏", "页码", "亮度", "深色模式"]
        case .downloads:
            ["评论", "并发", "线程", "限速", "队列", "ZIP", "导出", "文件名", "章节屏蔽", "通知", "灵动岛"]
        case .history:
            ["阅读进度", "记录", "清空"]
        case .readingDuration:
            ["统计", "趋势", "单次", "低于", "清空", "记录"]
        case .blockingKeywords:
            ["屏蔽", "黑名单", "关键词", "标签", "JM"]
        case .storage:
            ["缓存", "图片缓存", "详情缓存", "空间", "清空缓存", "下载文件"]
        case .backup:
            ["WebDAV", "同步", "恢复", "导出", "导入", "备份文件"]
        case .appDisplay:
            ["深色", "浅色", "动画", "平滑过渡", "缩放"]
        case .appBehavior:
            ["剪贴板", "启动", "更新", "敏感", "隐私", "截图", "录屏", "封面"]
        case .watchConnectivity:
            ["Watch", "Apple Watch", "手表", "同步", "阅读记录", "本地收藏", "稍后再读"]
        case .network:
            ["代理", "内置代理", "Proxy", "Clash", "YAML", "订阅", "节点", "SOCKS5", "Shadowsocks", "VMess", "Trojan", "主机", "端口", "连接", "重试"]
        case .about:
            ["用户协议", "隐私政策", "免责声明", "开源许可", "版本", "更新日志", "GitHub", "Telegram", "编译"]
        }
    }
}
