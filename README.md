# PicaX

[![License](https://img.shields.io/github/license/youshen2/PicaX)](https://github.com/youshen2/PicaX/blob/master/LICENSE)
[![Download](https://img.shields.io/github/v/release/youshen2/PicaX)](https://github.com/youshen2/PicaX/releases)
[![stars](https://img.shields.io/github/stars/youshen2/PicaX)](https://github.com/youshen2/PicaX/stargazers)

PicaX 是一个使用 SwiftUI 构建的多漫画源阅读客户端，面向 iOS、watchOS、macOS 和 visionOS。项目以原生 Apple 平台体验为目标，把漫画源登录、浏览、搜索、收藏、阅读、下载、阅读统计、备份迁移和本地数据管理集中在一个应用里。

[![Telegram Group](https://img.shields.io/badge/Telegram-加入群组-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/pica_x)

## 下载

<a href="https://github.com/youshen2/PicaX/releases">
<img src="https://user-images.githubusercontent.com/69304392/148696068-0cfea65d-b18f-4685-82b5-329a330b1c0d.png"
alt="Get it on GitHub" align="center" height="80" /></a>

## 系统兼容性

| 平台 / 系统 | 支持情况 |
| --- | --- |
| iOS 15 | 支持主应用核心功能 |
| iOS 16.0 | 使用兼容导航实现，支持主应用核心功能 |
| iOS 16.1+ | 支持下载进度 Live Activity |
| iOS 17+ | 启用 SwiftUI `NavigationStack` 导航能力 |
| iOS 26+ | 在上述功能基础上启用 Liquid Glass 视觉效果 |
| watchOS 9+ | 支持配套 Apple Watch 应用。 |

主应用最低部署版本为 iOS 15.0。Live Activity 扩展最低需要 iOS 16.1，但不会阻止主应用安装或运行在 iOS 15、iOS 16.0 上。

## 支持的漫画源

- PicACG
- JMComic
- NHentai
- E-Hentai / ExHentai
- Hitomi
- 绅士漫画

## 已有功能

### 账号与来源

- 多平台账号管理，支持 API 登录、网页登录、Cookie / User-Agent 保存与复用。
- 每个漫画源都有独立的前端地址配置，便于随时进行修改。

### 浏览、搜索与发现

- 支持按来源进入随机、最新和排行榜等入口。
- 分类页支持按来源加载分类，并跳转到对应搜索结果。
- 搜索页支持单平台搜索和多平台聚合搜索。
- 支持 PicACG、NHentai、JMComic 等来源的高级排序选项，NHentai 支持语言过滤。
- 搜索历史可记录关键词与来源。
- 支持剪贴板漫画链接和JM车牌号检测、打开分享链接、JM 车牌号直达详情。

### 详情、收藏与评论

- 漫画详情页展示封面、标题、作者 / 上传者、分类、标签、页数、热度、章节等信息。
- 支持本地收藏和各来源云端收藏夹。
- 支持评论区加载；支持的来源可发送评论或加载章节评论。
- 支持按标签继续浏览同类漫画。
- 列表可显示阅读进度、收藏状态、标签和热度，并可隐藏已读内容。
- 支持通用屏蔽词和 JMComic 专用屏蔽词。

### 阅读器

- 支持竖向连续滚动、竖向分页、左到右分页、右到左分页。
- 支持章节切换、章节列表 Sheet、阅读列表 Sheet、阅读进度和阅读历史保存。
- 支持批量阅读，把已下载漫画或收藏夹内漫画组成临时阅读列表，阅读器内可上一本 / 下一本切换，也可从阅读列表删除条目。
- 支持点按翻页、自动翻页、两指缩放、双击缩放、长按临时缩放。
- 支持图片预加载、加载重试、深色模式降低图片亮度、图片间距、首图顶部留白和末图底部留白等。
- 支持章节末尾显示评论，已下载漫画会优先使用本地保存的章节评论。
- 支持页码、进度浮层、时间电量浮层、状态栏隐藏和 UI 显隐设置；iOS 26+ 使用液态玻璃背景，旧系统自动回退为常规材质。

### 下载与本地阅读

- 支持按章节下载漫画，可选择下载全部或部分章节。
- 支持下载详情评论和章节评论。
- 下载页支持平台筛选、完成状态筛选、排序和删除。
- 已下载漫画可离线阅读，阅读列表只包含已下载章节。
- 已下载漫画支持阅读全部。
- 已下载漫画支持长按以 ZIP 导出。
- 首页可显示最近下载记录。

### 统计、历史与首页

- 阅读历史记录章节、页码和进度，支持清空历史或只清空阅读进度。
- 阅读时长统计支持今日、累计、单本详情和趋势图。

### 数据、备份与迁移

- 支持导出导入 `.picax` 备份，可选择账号、设置、本地收藏、阅读历史、阅读时长、搜索历史、屏蔽词和已下载漫画。
- 支持从 PicaComic 备份导入，覆盖账号、设置、下载、历史记录、本地收藏、搜索记录和屏蔽词等兼容数据。

## 相比原 PicaComic 更多的功能

相对原项目 `PicaComic` README 中列出的浏览、在线阅读、下载、本地 / 云端收藏、数据同步和阅读历史，PicaX 目前额外补充了：

- 原生 SwiftUI / Apple 平台 UI，以及 iOS 26+ Liquid Glass 适配。
- 阅读时长统计、单本趋势、首页阅读时长卡片和低于阈值不记录设置。
- 批量阅读：已下载、云端收藏夹、本地收藏夹等列表可直接阅读全部，并在阅读器内切换上一本 / 下一本。
- 搜索补全：NHentai 平台的搜索补全。
- 已下载漫画 ZIP 导出，并支持自定义 ZIP 文件名格式。
- PicaComic 备份迁移入口，导入前预览并支持覆盖 / 合并。
- 下载评论区、下载限速、下载高级筛选、离线阅读全部。
- 本地 `.picax` 精细化备份导出 / 导入，支持选择备份内容。
- 更详细的设置项。

## 构建

1. 克隆仓库：

   ```bash
   git clone https://github.com/youshen2/PicaX.git
   cd PicaX
   ```

2. 使用 Xcode 打开项目：

   ```bash
   open PicaX.xcodeproj
   ```

3. 选择 `PicaX` scheme，并选择 iOS 模拟器、真机、macOS 或 visionOS 目标进行构建运行。

项目当前部署目标为 iOS 15.0 / watchOS 9.0 / macOS 26.0 / visionOS 26.0，Live Activity 扩展的部署目标为 iOS 16.1。由于项目包含 iOS 26、macOS 26 和 visionOS 26 API 的条件适配，构建时需要 Xcode 26 或更新版本；生成的 iOS 主应用仍可运行在 iOS 15 及更高版本。

### Telegram CI 发布

每次 CI 成功生成产物后，GitHub Actions 会将上一次成功编译到本次编译之间的 Commit 汇总作为 Caption，并通过 Telegram Bot 将以下 4 个未签名产物合并为同一个媒体组消息发送到频道：

- `PicaX-unsigned.ipa`
- `PicaX-with-watch-unsigned.ipa`
- `PicaX-WatchApp-unsigned.zip`
- `PicaX.dmg`

Caption 超过 Telegram 长度限制时会保留可容纳的 Commit，并注明省略数量及 Actions 链接，不会拆分成第二条消息。外部 Fork 发起的 Pull Request 不会读取仓库 Secrets，因此只构建和保存产物，不会发送到频道。

版本标签会在 GitHub Release 上传完成后以非静默方式发送版本更新消息和全部产物，并自动置顶。机器人还需要频道的置顶消息权限；标签构建不会重复发送普通 CI 消息。Telegram 不会因频道置顶额外通知所有成员，最终通知仍受订阅者的频道通知设置影响。

配置方式：

1. 通过 Telegram 的 `@BotFather` 创建机器人并取得 Bot Token。
2. 将机器人添加为目标频道管理员，并授予发布消息权限。
3. 在 GitHub 仓库的 `Settings > Secrets and variables > Actions` 中添加以下 Repository secrets：
   - `TELEGRAM_BOT_TOKEN`：机器人 Token。
   - `TELEGRAM_CHAT_ID`：频道标识；公开频道可填写 `@频道用户名`，私有频道可填写 `-100` 开头的数字 ID。

如果任一 Secret 缺失、机器人没有频道发布权限或 Telegram 上传失败，`Send artifacts to Telegram channel` 任务会失败并显示原因。

## 特别鸣谢

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=ccbkv&repo=PicaComic)](https://github.com/ccbkv/PicaComic)

本项目参考的原始多源漫画客户端之一。

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=Pacalini&repo=PicaComic)](https://github.com/Pacalini/PicaComic)

原项目的原 fork，提供了可参考的跨平台功能与 README 信息。

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=tonquer&repo=JMComic-qt)](https://github.com/tonquer/JMComic-qt)

JMComic 图片重组相关实现的重要参考。

[![Readme Card](https://github-readme-stats.vercel.app/api/pin/?username=EhTagTranslation&repo=Database)](https://github.com/EhTagTranslation/Database)

E-Hentai 标签中文翻译数据来源。

各漫画源网站及其社区维护者。

## 免责声明

本项目仅用于学习与个人使用，请在下载后 24 小时内删除。

应用中展示的漫画内容、账号系统和平台数据均来自对应漫画源，版权与服务条款归各平台及其权利方所有。请遵守当地法律法规和对应平台规则。

## 协议

本项目使用 Mozilla Public License 2.0 开源，详见 [LICENSE](LICENSE)。
