import Foundation

struct LegalDocument: Identifiable {
    enum Kind: String, Hashable {
        case userAgreement
        case privacyPolicy
        case contentDisclaimer
    }

    let kind: Kind
    let title: String
    let summary: String
    let systemImage: String
    let introduction: String
    let sections: [LegalDocumentSection]

    var id: Kind { kind }

    static let all = [
        userAgreement,
        privacyPolicy,
        contentDisclaimer
    ]

    static let userAgreement = LegalDocument(
        kind: .userAgreement,
        title: "用户协议",
        summary: "使用条件、账号责任与服务规则",
        systemImage: "doc.text",
        introduction: "在使用 PicaX 前，请仔细阅读本协议。使用本应用即表示你理解并同意遵守以下条款。",
        sections: [
            LegalDocumentSection(
                id: "service",
                title: "1. 服务说明",
                body: "PicaX 是用于连接第三方内容平台的客户端工具，提供浏览、搜索、阅读、收藏、下载和本地管理等功能。PicaX 不生产、上传、托管、编辑或分发第三方平台提供的漫画、图片、标题、标签、评论及其他内容。"
            ),
            LegalDocumentSection(
                id: "eligibility",
                title: "2. 使用资格",
                body: "本应用仅面向已满 18 周岁、具备相应民事行为能力，并可依据所在地法律访问相关内容的用户。若你不满足这些条件，请停止使用本应用。"
            ),
            LegalDocumentSection(
                id: "third-party-services",
                title: "3. 第三方账号与服务",
                body: "当你登录、浏览或操作第三方平台时，PicaX 会根据你的指令向相应平台发送请求。你的使用同时受该平台的服务条款、隐私政策和内容规则约束；第三方平台独立提供并负责其服务。"
            ),
            LegalDocumentSection(
                id: "local-data",
                title: "4. 账号与本地数据",
                body: "平台登录凭证、Cookie、令牌、收藏、历史记录、下载和应用设置等数据可能保存在本机，用于维持登录状态和提供本地功能。请妥善保护设备及备份文件，并对因设备丢失、系统清理、卸载应用或主动删除导致的数据丢失自行负责。"
            ),
            LegalDocumentSection(
                id: "acceptable-use",
                title: "5. 使用规则",
                body: "你不得利用本应用侵犯他人权益、规避平台限制、实施未经授权的批量访问、传播违法内容、破坏服务稳定性，或从事其他违反适用法律及第三方平台规则的行为。"
            ),
            LegalDocumentSection(
                id: "content-rights",
                title: "6. 内容与知识产权",
                body: "第三方内容的著作权、商标权及其他权利归其权利人所有。PicaX 的名称、界面、代码及应用自身资源由其相应权利人依法享有权利。使用本应用不会向你转让任何第三方内容权利。"
            ),
            LegalDocumentSection(
                id: "availability",
                title: "7. 服务可用性",
                body: "第三方接口、站点规则、网络环境和系统能力可能随时变化，PicaX 不保证所有功能或内容持续可用。应用也可能因维护、升级或兼容性调整而变更或停止部分功能。"
            ),
            LegalDocumentSection(
                id: "changes-and-termination",
                title: "8. 协议变更与终止",
                body: "本协议可能随功能或法律要求更新。更新后的文本会在应用内提供；如你不同意相关条款，应停止使用并可删除本应用及其本地数据。"
            )
        ]
    )

    static let privacyPolicy = LegalDocument(
        kind: .privacyPolicy,
        title: "隐私政策",
        summary: "本地数据、网络请求与同步说明",
        systemImage: "hand.raised",
        introduction: "本政策说明 PicaX 在提供客户端功能时如何处理数据。第三方平台及你自行配置的服务具有各自独立的隐私规则。",
        sections: [
            LegalDocumentSection(
                id: "local-processing",
                title: "1. 本机处理的数据",
                body: "为提供应用功能，PicaX 会在设备上保存或处理应用设置、平台账号与登录凭证、Cookie、收藏、稍后再读、搜索与阅读历史、阅读时长、下载记录、缓存及你主动创建的备份。"
            ),
            LegalDocumentSection(
                id: "network-requests",
                title: "2. 第三方平台请求",
                body: "当你登录、搜索、浏览、阅读、收藏、评论或下载时，相关请求及必要的账号凭证会直接发送至你所选择的第三方平台。第三方平台可能依据其隐私政策处理你的账号、IP 地址、请求内容及设备或浏览器信息。"
            ),
            LegalDocumentSection(
                id: "supporting-services",
                title: "3. 辅助网络服务",
                body: "检查应用更新、获取公开标签数据或访问项目链接时，应用可能连接 GitHub 等公开托管服务。相应服务会按照其自身规则处理网络请求。"
            ),
            LegalDocumentSection(
                id: "sync-and-backup",
                title: "4. 同步与备份",
                body: "如果你启用 WebDAV，所选备份数据会上传至你配置的服务器；服务器地址和用户名保存在本机，密码保存在系统 Keychain。与 Apple Watch 配合使用时，账号及你启用的同步数据可能通过 Apple 提供的设备通信能力传输至配对手表。"
            ),
            LegalDocumentSection(
                id: "collection",
                title: "5. PicaX 的数据收集",
                body: "当前版本未集成广告 SDK 或第三方统计 SDK，也不通过 PicaX 自有服务器集中收集上述本地数据。第三方平台、公开托管服务及你配置的 WebDAV 服务对数据的处理不属于 PicaX 的本地存储。"
            ),
            LegalDocumentSection(
                id: "controls",
                title: "6. 保存期限与控制",
                body: "本地数据通常会保留至你在应用内清除、退出相应账号、覆盖导入备份或卸载应用。你可以在设置中管理历史、缓存、下载、账号和备份；WebDAV 服务器上的数据需由你在对应服务器或应用的 WebDAV 页面管理。"
            ),
            LegalDocumentSection(
                id: "security",
                title: "7. 数据安全",
                body: "请使用设备密码并妥善保管备份文件和第三方账号。通过网络或保存在本机的数据均无法保证绝对安全，建议使用 HTTPS WebDAV 服务并及时撤销不再使用的第三方登录状态。"
            ),
            LegalDocumentSection(
                id: "adults-only",
                title: "8. 未成年人",
                body: "PicaX 仅面向已满 18 周岁的用户，不以未成年人为目标用户，也不应由未成年人使用。"
            ),
            LegalDocumentSection(
                id: "policy-updates",
                title: "9. 政策更新",
                body: "隐私实践发生变化时，本政策会相应更新。你可以随时在“设置 > 关于”中查看当前版本。"
            )
        ]
    )

    static let contentDisclaimer = LegalDocument(
        kind: .contentDisclaimer,
        title: "免责声明",
        summary: "第三方内容来源、权利与责任说明",
        systemImage: "exclamationmark.shield",
        introduction: "PicaX 仅提供第三方内容平台的客户端访问能力。应用中展示的漫画、图片、标题、标签、评论及相关内容均由相应第三方平台提供，并非 PicaX 自身提供。",
        sections: [
            LegalDocumentSection(
                id: "content-source",
                title: "1. 内容来源",
                body: "PicaX 不生产、上传、托管、编辑、审核或分发第三方内容。应用仅在你发起操作时，从所选第三方平台获取并展示相关信息。"
            ),
            LegalDocumentSection(
                id: "no-affiliation",
                title: "2. 非官方关系",
                body: "除非另有明确说明，PicaX 不是所连接平台的官方客户端，与相关平台、内容发布者或权利人不存在隶属、代理、合作、赞助或认可关系。平台名称及标识仅用于识别用户选择的服务。"
            ),
            LegalDocumentSection(
                id: "no-guarantee",
                title: "3. 内容与服务保证",
                body: "PicaX 无法控制第三方内容及服务，不保证其合法性、准确性、完整性、安全性、适宜性、持续可用性或是否符合你的所在地要求。第三方内容可能在不通知 PicaX 的情况下变更、下架或失效。"
            ),
            LegalDocumentSection(
                id: "intellectual-property",
                title: "4. 权利归属",
                body: "第三方内容的著作权、商标权、肖像权及其他权利归相应权利人所有。你应仅在获得授权或法律允许的范围内访问、下载、保存或分享内容。"
            ),
            LegalDocumentSection(
                id: "user-responsibility",
                title: "5. 用户责任",
                body: "你应自行确认访问和使用相关平台及内容符合所在地法律、年龄限制和第三方平台规则，并对使用本应用发起的登录、收藏、评论、下载、备份和分享等操作承担责任。"
            ),
            LegalDocumentSection(
                id: "accounts-and-network",
                title: "6. 账号与网络风险",
                body: "第三方平台可能限制或终止账号、接口或内容访问。因第三方平台行为、账号状态、网络故障、接口变化或不可抗力造成的登录失效、访问中断或数据异常，不由 PicaX 控制。"
            ),
            LegalDocumentSection(
                id: "local-copies",
                title: "7. 下载与本地副本",
                body: "下载、缓存和备份仅保存在你的设备或你自行配置的存储服务中。你有责任保护这些副本、避免未经授权的传播，并在不再具备保存依据时及时删除。"
            ),
            LegalDocumentSection(
                id: "liability",
                title: "8. 责任限制",
                body: "在适用法律允许的范围内，因使用或无法使用第三方内容与服务所产生的损失，应依据你与相应第三方之间的关系及适用规则处理。PicaX 不对第三方内容或服务作出明示或默示担保。"
            ),
            LegalDocumentSection(
                id: "acceptance",
                title: "9. 确认",
                body: "继续使用 PicaX 即表示你已阅读并理解本免责声明。若你不同意其中任何内容，请停止使用本应用。"
            )
        ]
    )
}

struct LegalDocumentSection: Identifiable {
    let id: String
    let title: String
    let body: String
}
