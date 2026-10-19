# 饮食营养记录项目更新规则

本文件是 `NutritionDiary` 项目的更新声明与强制规则。自本文件创建后，任何代码、资源、文档、数据库模型、版本归档或发布相关的更新，都必须遵守本文件。若其他说明与本文件冲突，以用户当前明确指令和本文件为准。

## 1. 事实来源与优先级

1. 用户当前明确提出的需求。
2. 本文件 `AGENTS.md`。
3. `project.yml` 中的版本、Target、部署版本和签名配置。
4. `Releases/README.md` 中的归档规范。
5. `README.md` 中的功能说明和当前边界。
6. 源码和测试中体现的实际行为。

不得根据旧版本文档覆盖当前代码事实。发现文档与代码不一致时，应在同一次更新中修正文档，并在发布说明中记录。

## 2. 版本与归档规则

- 工程版本唯一来源是 `project.yml`：
  - `MARKETING_VERSION` 表示语义版本。
  - `CURRENT_PROJECT_VERSION` 表示构建号。
- 当前已归档版本以 `Releases/index.json` 为准；版本归档仅保存在本机，并通过 `.gitignore` 排除在开源仓库之外。
- 每次完成一组可交付更新后，必须：
  1. 将 `CURRENT_PROJECT_VERSION` 至少加 1。
  2. 根据变更类型更新 `MARKETING_VERSION`。
  3. 运行测试和双端构建。
  4. 创建对应 `Releases/v<版本>-b<构建号>/`。
  5. 更新 `Releases/index.json` 和发布说明。
  6. 执行归档校验。
- 语义版本规则：
  - 修复缺陷、文档修正、重构且不改变用户能力：增加 patch 版本，例如 `0.1.0` 到 `0.1.1`。
  - 新增用户可见功能或明显改变行为：增加 minor 版本，例如 `0.1.1` 到 `0.2.0`。
  - 数据格式或使用方式发生不兼容变化：增加 major 版本；在 `1.0.0` 前也必须显式记录迁移方案。
- 同一版本目录和构建号禁止覆盖或复用。修复已归档版本的问题时，必须增加构建号或版本号并创建新归档。
- 除纯临时草稿外，不得只修改代码而不更新版本和归档。
- 发布说明必须写入 `RELEASE_NOTES.md`，包含用户可见变化、技术变化、验证结果和已知边界。
- 开源仓库不提交 `Releases/`、`.catalog-cache/`、构建缓存或生成的 Xcode 工程；版本归档仍必须在本机创建并校验。

## 3. 必做验证

更新完成前必须执行：

```sh
make test
make build-ios
make build-mac
```

创建归档时必须使用带构建验证的默认流程：

```sh
./Scripts/archive-version.sh --notes Docs/release-notes-vX.Y.Z-bN.md
./Scripts/archive-version.sh verify Releases/vX.Y.Z-bN
```

- 默认归档流程必须通过 Swift 测试、iOS 构建和 macOS 构建。
- 只有无法运行本地构建的紧急情况才允许 `--skip-build`，且 manifest 必须保留 `validation: skipped`，发布说明必须写明原因和未验证项。
- 涉及 HealthKit、相机、Foundation Models、CloudKit 或真机权限的更新，必须在发布说明中记录是否完成真机验证；未完成时不得声称已完成真机验收。
- 任何测试失败、构建失败、校验失败或版本目录冲突都必须阻止归档。

## 4. 架构与代码规则

- 使用 XcodeGen 管理工程。`project.yml` 是工程配置来源，禁止手工编辑生成的 `.xcodeproj` 作为持久修改。
- iOS 与 macOS 共用 `NutritionKit` Swift 包中的领域模型、计算和持久化逻辑；平台专属代码只处理界面适配、相机、HealthKit 和端侧模型。
- 使用 Swift 6 严格并发。UI 与 ViewModel 保持在 MainActor；SwiftData、网络、文件处理和照片分析使用明确的 actor 或 ModelActor 边界。
- 不引入 `@unchecked Sendable` 规避并发错误；优先重构数据边界。
- 跨层传递不可变 DTO，不在 actor 之间传递 SwiftData Model。
- 新增功能必须同步增加测试，尤其是营养计算、单位换算、可食比例、热量平衡、时区、HealthKit 同步标识和数据迁移。
- SwiftData 模型变更必须提供向后兼容或迁移方案，不得静默删除用户饮食、目标或照片引用。
- 所有持久化时间使用 UTC `Date`，同时保存本地 `dayKey` 和时区；跨时区统计不得直接按 UTC 日切分。
- 营养值必须区分 `complete`、`estimated`、`missing`。缺失不得当作零；照片估算默认不得写入 HealthKit，除非用户明确允许。
- HealthKit 写入必须继续使用稳定同步标识和递增版本号，修改或删除餐次时避免重复样本。
- Apple Watch 能量必须按来源选择，禁止把多个来源的活动或静息能量直接相加。
- Apple 本机照片识别不上传照片。DeepSeek 云端识别只能由用户每次明确确认后触发；不得自动上传照片。云端结果只能提取菜品、份量或可见营养标签，混合餐营养仍须由本地目录计算，禁止模型直接猜测混合菜营养。
- 食物、食谱或食物目录更新必须保留来源、许可证和版本信息。

## 5. 资源与数据安全

- `Releases/` 只包含源码快照、发布说明、截图、Asset Catalog 和校验信息，并且仅保存在本机，不进入开源仓库。
- 不得归档以下内容：
  - IPA、macOS App、DerivedData 或其他构建缓存。
  - Apple 开发者证书、描述文件、私钥和签名材料。
  - API Key、Token、账号密码或环境变量。
  - 用户饮食数据、HealthKit 原始数据、照片、备份文件或数据库。
- 源码归档必须排除 `.git/`、`Releases/`、`.build/`、`.swiftpm/`、`DerivedData/`、`xcuserdata/` 和系统临时文件。
- 新增资源时放入相应源码目录，并同步更新版本资源快照和 manifest。
- 若新增网络服务、第三方 SDK、数据源或权限，必须更新 README 的数据安全、许可和失败降级说明。
- DeepSeek API Key 只能保存在本机 Keychain，不得进入日志、UserDefaults、iCloud、导出备份、源码归档或版本资源。

## 6. 文档与格式规则

- 用户可见功能变化必须更新 `README.md` 和对应 `RELEASE_NOTES.md`。
- 版本规范或归档脚本变化必须更新 `Releases/README.md`。
- 数据模型、公共接口或关键实现变化应在发布说明中记录迁移和兼容影响。
- 所有 Markdown、笔记和文档中的数学公式必须使用 `$$ ... $$`，每对定界符必须完整写在同一行；禁止单美元符号、反斜杠圆括号或反斜杠方括号公式。
- 文档中的命令必须可直接复制运行，并优先使用 `make` 或 `Scripts/` 中的统一入口。
- 不得在文档中把未实现的功能描述为已完成。

## 7. 每次更新的标准流程

1. 检查当前版本、已有归档、相关源码、测试和文档。
2. 明确本次更新属于 patch、minor 或 major，并说明原因。
3. 实施代码与资源修改。
4. 增加或更新自动化测试。
5. 更新 `project.yml` 版本号和构建号。
6. 运行 `make test`、`make build-ios`、`make build-mac`。
7. 编写 `Docs/release-notes-vX.Y.Z-bN.md`。
8. 运行 `./Scripts/archive-version.sh --notes ...`。
9. 运行归档 `verify`，确认 manifest、index、资源、截图、源码包和 SHA256 全部有效。
10. 检查工作区差异，确认没有缓存、密钥、用户数据或构建产物被纳入归档。
11. 向用户报告版本号、归档路径、验证结果和仍存在的边界。

## 8. 规则生效

本文件自创建起生效。创建前已经生成的 `v0.1.0-b1` 保留现状；其后所有更新必须从下一次版本开始遵守上述版本、验证和归档流程。
