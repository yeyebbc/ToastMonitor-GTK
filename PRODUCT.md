# Product

<!-- impeccable:product-schema 1 -->

## Platform

linux

<!-- 当前 Impeccable 平台枚举未覆盖原生 Linux；此处保留真实平台，不将 GTK 应用归为 web、iOS 或 Android。 -->

本仓库面向 Linux/GNOME 原生桌面应用。保留的 macOS SwiftUI 源码属于上游历史实现，不参与当前 Linux 构建，也不代表本仓库承诺同时维护 macOS 产品。

## Users

优先服务维护者自己的使用需求：在使用 AI 编程工具时查看用量、费用、账户余额和订阅额度。其他用户的需求应以实际反馈为依据，不预设团队管理、组织计费或企业后台场景。

## Product Purpose

将分散在多个 AI 工具中的使用记录汇总到本机，提供快速查看和历史核对的入口，帮助使用者理解自己的用量与费用。

成功意味着日常查看方便、采集持续可靠、数据含义清楚，并能在需要时导出或备份；不能以一个含义不明的总金额替代真实的费用结构。

## Positioning

ToastMonitor-GTK 是上游 ToastMonitor 的 GNOME/Linux 原生移植版，复用其采集、解析、去重、定价和数据库迁移能力，通过 GTK4/libadwaita 界面及桌面托盘呈现本地数据。

它是个人使用量监控工具，不承诺提供供应商账单的完整替代品。估算 API 价值与实际支付金额具有不同含义。

## Operating Context

- 应用与 AI 编程工具运行在同一台 Linux 电脑上，默认自动采集本地日志；远程数据源需显式配置。
- GNOME Shell 46 可选原生顶栏面板提供今日 token、调用、费用、余额和订阅额度，以及 Overview、Preferences、Plans 和刷新入口；普通托盘仍提供今日 token 总量及刷新、窗口和退出入口。关闭窗口继续采集；退出应用才停止采集。
- 窗口包含 Overview、Analysis、Plans、Sessions 和 Preferences；可按今日、周/7 天、月/30 天或全部时间查看用量。
- GNOME Shell 46 原生面板使用随应用提供的 ToastMonitor 扩展；连接时隐藏普通托盘，禁用或断开后恢复托盘。普通 GNOME Shell 托盘需要 AppIndicator/KStatusNotifierItem 扩展；没有任一扩展时仍可使用应用窗口。
- 字体、明暗外观和原生控件遵循 GNOME 桌面设置。保留 GNOME 原生体验，不套用网页或 macOS 的交互习惯。
- 使用 XDG 数据目录和 GNOME Secret Service。保存凭据需要可用且已解锁的 Secret Service；本地采集不依赖凭据存储服务。

## Capabilities and Constraints

- 当前技术栈：Swift 6.0+、adwaita-swift 0.1.0、GTK 4.14+、libadwaita 1.5+、SQLite、GIO 和 libsecret；构建边界以 `Package.swift` 为准。
- 本地采集支持 Claude Code、Codex、OpenCode、Hermes、Oh My Pi 和 DeepSeek Harness。账户连接用于读取支持的订阅额度、余额或账户支出，不等同于本地日志采集。
- 提供按工具和模型汇总、近 30 天每日分析与 CSV 导出、最近会话、手工订阅费用记录、受保护备份和数据库导出。
- 使用数据保留在本机，无遥测；仅显式连接的账户和远程数据源产生相应网络访问。凭据存入 Secret Service，不写入普通设置或使用量数据库。
- 实际支出、估算 API 价值、固定订阅费、已消费额度和账户余额必须明确区分，不能无条件相加。遵循 `docs/data-semantics.md` 中的数据语义约束；该文档中的上游平台细节不构成 Linux 界面功能承诺。
- 避免重复计数：例如 Codex 的输入 token 已包含缓存部分，不能再次叠加。采集失败时保留最后一次成功的额度数据，并明确错误或陈旧状态。
- 保留已有数据库迁移、去重、备份与恢复校验，以及导出脱敏和私有文件权限等保护机制。
- 当前 Linux 构建不提供 macOS 字体选择器、DeepSeek 浏览器登录自动化或 macOS 内置更新器。DeepSeek 凭据通过 Preferences 输入，更新通过 Linux 安装包或重新构建完成。

## Brand Commitments

保留 ToastMonitor/ToastMonitor-GTK 名称、上游来源说明、MIT 许可证和原版权声明。托盘使用现有 symbolic token 图标，并由桌面控制其前景色。

界面文案应直接说明数据含义、操作结果和下一步，避免把估算写成账单事实。现有界面为英文；中文化范围尚未确定。

## Evidence on Hand

- `README.md`：Linux 产品范围、依赖、安装、数据源和已记录的验证结果。
- `Package.swift`、`Sources/ToastMonitor/Linux/`、`Sources/LinuxBridge/`：当前可构建的原生应用及平台集成实现。
- `Sources/ToastMonitor/Collect/`、`Sources/ToastMonitor/Core/`：采集、定价、数据语义和存储实现。
- `docs/data-semantics.md`：费用、token、时间、质量和数据清理的语义要求。
- `Tests/ToastMonitorTests/`、`scripts/smoke-linux.sh`：已有测试和隔离式 Linux 集成验证；历史通过数量不代表当前版本重新验证的结果。
- `data/icons/hicolor/scalable/status/toastmonitor-token-symbolic.svg`：当前 Linux 托盘图标。
- `gnome-extension/`、`Sources/ToastMonitor/Linux/PanelSnapshot.swift`、`docs/gnome-extension.md`：GNOME Shell 46 原生面板、仅含展示数据的会话总线接口和安装说明；沿用现有 symbolic 图标与 Shell 主题。
- `docs/images/` 和 `Tests/VisualBaselines/` 保留上游视觉资料，不能直接作为当前 GTK 界面的视觉基准。

没有已确认的客户案例、用户证言、性能基准或商业定价，不应在未来界面或宣传中编造。

## Product Principles

1. 以维护者真实的日常使用需求决定功能优先级。
2. 本地优先、无遥测，凭据和个人使用记录保持受保护。
3. 费用和 token 口径清楚；不以汇总便利牺牲数据真实性。
4. 保持 GNOME 原生桌面行为，降低后台监控的操作负担。
5. 在界面改动中保留可靠采集、去重、迁移和数据恢复能力。

## Open Decisions

尚未确定中文化范围、产品专属无障碍验收标准，以及当前功能之外的新需求。未来按实际任务确认，不从上游 macOS 源码推导 Linux 功能承诺。
