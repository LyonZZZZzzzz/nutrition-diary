# 饮食营养记录

原生 SwiftUI 双端饮食营养与热量平衡 App。iPhone 使用 iOS 27 端侧 Apple Foundation Models 分析餐食照片，读取 Apple Watch 活动/静息能量，并向 HealthKit 写入确认后的膳食营养；Mac 提供完整本地录入、查看和导出。

源代码采用 MIT License；第三方食物数据继续遵循各自来源许可，详见 `THIRD_PARTY_NOTICES.md`。

## 已实现

- XcodeGen 生成 iOS 27 / macOS 15 双 Target 工程。
- 共享 `NutritionKit` Swift 包：营养状态、每 100 克/毫升基准、可食比例、家庭份量、食谱累计、每日汇总、热量平衡、照片食物匹配、JSON/CSV 导出。
- 121 项版本化公开授权种子数据，覆盖咖啡与饮品、蔬菜、水果、其他食材、调味食材和常见混合食品，全部具备人工审核的中英文名称与分类。
- 随 App 打包 13,627 条离线食物目录，使用 SQLite FTS5 搜索；全部记录均具备简体中文名称，英文原名与别名继续保留用于核对和联合搜索。精简后的 `Catalog.sqlite` 约 62 MiB，只保留 Payload、FTS 和元数据。
- 新增 120 项中式复合菜覆盖层，包括 50 道炒菜、15 道炖煮菜、15 道饭面粉饺、10 道汤羹、10 道早餐、10 道凉菜、10 项咖啡奶茶和 10 项甜品；全部由本地食材配方、成品重量与家庭份量计算，不复制无明确再分发许可的中国食物成分表。
- 设置页支持“跟随系统、简体中文、English”；应用内切换立即生效，UI、食物名称、分类、来源、营养项、餐次、健康状态和错误提示同步切换。
- 中文名称按人工审核、台湾 FDA 参考、本地机器翻译依次生成；品牌和餐厅原名保留，机器译名在详情页明确标注并同时展示英文原名。
- SwiftData 本地持久化、每日能量汇总、平衡目标、冲突副本和同步元数据存储。
- iCloud 私有自定义 Zone 通过 `CKSyncEngine` 同步日记、自定义食物、复合食物、每日能量汇总和热量目标；使用离线待上传批次、删除墓碑、首次合并与三向冲突副本。
- iPhone 相册选择/相机拍摄最多三张照片；DeepSeek `deepseek-flash` Vision 为混合餐主入口，Apple Intelligence 可用时保留端侧次入口。多菜、低置信度、候选接近或份量跨度异常时按需执行第二次近景识别，所有结果必须人工确认后计入。
- 照片估算保留为 `estimated`，默认不写入 Health；可在设置中显式允许。
- 照片确认页支持小碗、饭碗、汤碗、20/25 厘米盘、250/350/450 毫升杯和包装份量先验；自动选中要求候选至少 0.80 且领先第二名至少 0.10，否则只展示前三项等待人工核对。
- 新增仅本机照片纠错学习：保存哈希化查询、食物 ID、确认/拒绝次数和份量比例，不上传、不进入 CloudKit、JSON 导出或版本归档；删除本机数据时一并清除。
- HealthKit 读取活动能量、静息能量和 Apple 锻炼时间，按来源聚合，默认 Apple Watch 优先并允许手动指定来源；前台观察查询与回到前台会刷新，禁止多来源相加。
- 今日页、拍照页、历史、食物库、设置、JSON/CSV 导出；JSON 备份可合并或完整恢复，媒体 ZIP 同时备份本地照片。
- 设置页可分别删除当前设备数据或本机与 iCloud 数据，并显示 iCloud 账号、待上传数量、最后成功时间、冲突数量和手动同步入口；账号切换必须显式确认。Health App 中已写入的膳食样本需在 Health 内单独删除。
- 数据库启动失败时提供诊断、重试和经确认重建，不自动删除现有数据。
- 餐次添加支持克/毫升和家庭份量，实时预览热量、蛋白质、脂肪、碳水、纤维、糖和钠；保存成功后才关闭页面并更新今日汇总。
- 今日页支持长按菜品在早餐、午餐、晚餐和加餐之间拖动；只更新餐次和目标默认时间，不删除重建记录，并同步更新 HealthKit 与 CloudKit。
- 共享单元与集成测试覆盖核心计算、照片匹配、语言解析、双语搜索、旧数据兼容、SQLite 检索、 SwiftData 保存及每日营养汇总。
- iOS UI 测试覆盖“搜索鸡蛋 → 选择 1 个 → 预览 72 kcal → 保存 → 今日总摄入 72 kcal”、无结果、非法份量、英文搜索、机器翻译详情、13,627 / 13,627 中文覆盖页面和冷启动性能指标。
- `Scripts/verify_localizations.py` 校验 String Catalog 覆盖率，并已纳入 `make test`。

## 中英双语与本地化

- 语言偏好保存在本机 `UserDefaults`，不进入 CloudKit 或 JSON 备份；iPhone 与 Mac 可分别选择。
- `Apps/Shared/Localizable.xcstrings` 保存应用内 UI 翻译；`InfoPlist.xcstrings` 保存系统显示名称与权限说明。
- 食物双语字段写入 `Catalog.sqlite` schema v4，并保存每条中文名称的来源：人工审核、台湾参考或本地机器翻译。
- 本地机器翻译缓存位于 `CatalogData/FoodNameZhTranslations.json`。首次开发机生成命令：

```sh
BATCH_SIZE=500 ./Scripts/build-food-translations.sh
```

- 修改目录源名称后，可用 `RESUME=1 ./Scripts/build-food-translations.sh` 从已成功批次继续。
- 重新构建目录使用：

```sh
python3 Tools/build_food_catalog.py   --foundation .catalog-cache/foundation/FoodData_Central_foundation_food_json_2026-04-30.json   --sr-legacy .catalog-cache/sr-legacy/FoodData_Central_sr_legacy_food_json_2018-04.json   --fndds .catalog-cache/fndds/surveyDownload.json   --translation-cache CatalogData/FoodNameZhTranslations.json
```

- 人工译名、品牌和重点术语位于 `Packages/NutritionKit/Sources/NutritionKit/Resources/FoodLocalizationOverlay.json` 和 `Tools/food-name-translation-rules.json`。
- 台湾 FDA 文件可通过 `TAIWAN_FILE` 或 `--taiwan-reference` 作为中文名称参考层接入，不会新增重复食物记录；缺失台湾文件时仍由本地翻译缓存保证全量覆盖。

## 生成与构建

```sh
xcodegen generate
make test
make test-ios-ui
make build-mac
make build-ios
make verify
```

直接使用 Xcode：

```sh
open NutritionDiary.xcodeproj
```



## 开源与本地归档

- 源代码采用 MIT License，版权人为 `lyonzhu`；第三方数据许可单独列在 `THIRD_PARTY_NOTICES.md`。
- `Catalog.sqlite` 约 62MB，直接保存为普通 Git 文件，本轮不使用 Git LFS。
- `Releases/` 只作为本机不可覆盖版本归档，不进入开源仓库；开源仓只发布可复现源码、测试、工具和必要资源。
- XcodeGen 生成的 `.xcodeproj`、构建缓存、目录缓存、证书、描述文件和本地密钥不进入 Git。
- `.github/workflows/ci.yml` 在 macOS 27 运行完整测试、UI 测试和双端构建。
- 法务与支持页面源文件位于 `LegalSite/`，设计为独立公开 GitHub Pages 仓库。


## CloudKit 同步

- 正式 Debug 固定使用 CloudKit Development，Release 固定使用 Production；DeviceTest 仅保留 HealthKit 并禁用 CloudKit。
- Team ID、容器和两个环境分别由独立的 iOS/macOS entitlement 固定，签名描述文件必须包含 `iCloud.com.lyonzhu.NutritionDiary`。
- 管理授权使用 Keychain 中的 CloudKit Console token；Schema 导出、校验和对比命令见 `CloudKit/README.md`。

- 记录类型：`NutritionSyncRecord`；自定义 Zone：`NutritionDiary`。
- 记录键：`<recordKind>:<UUID>`；`recordKind` 为 `diaryEntry`、`savedFood`、`compositeFood`、`energyDay` 或 `balanceGoal`。
- Payload 包含 `schemaVersion`、业务 JSON、`updatedAt`、`deletedAt` 和 `deviceID`。照片、DeepSeek Key、语言偏好、HealthKit 原始样本和 CloudKit 凭据不会写入 Payload。
- 首次同步先拉取云端增量，再合并本地记录，最后上传待发送记录。网络失败时本地保存不变，设置页显示待上传数量并允许重试。
- 每个指标在合并时只采用一个逻辑记录；冲突时较新记录进入统计，失败版本保存为不参与统计的冲突副本。墓碑记录幂等应用，重复拉取不会生成重复饮食条目。
- iCloud 账号变化会暂停同步并要求确认。确认前不会把上一账号的数据上传到新账号。
- CloudKit 开发 Schema 必须在 Apple Developer / CloudKit Console 中部署到生产环境后再进行 TestFlight/App Store 验收。

## 项目更新声明

项目的强制更新规则、版本策略、验证要求、数据安全边界和本地归档流程定义在 [AGENTS.md](AGENTS.md)。任何后续更新都必须先阅读并遵守该文件。

## 版本归档

版本基线和资源仅保存在本机 `Releases/`，该目录已被开源仓库忽略。创建新版本前先更新 `project.yml` 中的 `MARKETING_VERSION` 或 `CURRENT_PROJECT_VERSION`，然后运行：

```sh
make archive-version
make verify-release
```

归档会运行测试和双端构建，生成不可覆盖的源码快照、资源、截图、发布说明和 SHA256 校验文件。详见 `Releases/README.md`。


## 品牌资源

- App 图标与启动封面由 `Scripts/generate-brand-assets.swift` 可复现生成。
- 品牌色：深绿 `#2E8F4F`、奶油白 `#F7F1E4`、暖橙 `#F39A4A`。
- App 图标无文字、无 Alpha；启动封面包含简体中文和英文资源，由系统语言选择。
- 中文封面文案为“饮食营养记录 / 记录每一餐，看见营养平衡”，英文为“Nutrition Diary / Track every meal. See your balance.”。
- 预览资源位于 `Docs/Brand/`。

## 真机配置

1. 使用已付费的 Apple Developer Team 配置两个 Target。
2. 为 iOS Target 启用 HealthKit 和 iCloud/CloudKit capability。
3. 将 `com.lyonzhu.NutritionDiary`、`iCloud.com.lyonzhu.NutritionDiary` 等占位标识替换为自己的 Bundle ID/Container。
4. 在 Apple Developer 后台创建 `iCloud.com.lyonzhu.NutritionDiary` CloudKit Container；否则启用 iCloud entitlement 的真机签名会因描述文件不匹配而失败。
5. Apple Intelligence 可用时可选择本机识别；不可用时会显示具体原因，并可使用自带 DeepSeek API Key 的云端 Vision 识别。
6. 在 App 设置中保存 DeepSeek Key。Key 只存本机 Keychain；每次照片识别前仍需单独确认上传。
7. HealthKit 读写必须在真机上完成授权与验收；模拟器只能验证界面和降级路径。
8. 真机 UI 测试可运行：`xcodebuild test -project NutritionDiary.xcodeproj -scheme NutritionDiary-iOS -configuration DeviceTest -destination 'platform=iOS,id=<设备UDID>' DEVELOPMENT_TEAM=<TeamID> -allowProvisioningUpdates -only-testing:NutritionDiary-iOS-UITests`。该配置不会读写真实用户数据。

已在 Lyon 的 iPhone 17（iOS 27.0.1）上使用临时 HealthKit-only entitlement 完成启动测试。正式 iCloud entitlement 仍要求先创建 CloudKit Container，再进行完整签名安装。

## 商店发布准备

- App Store 元数据草稿在 `AppStore/metadata.json`。
- 审核备注和 TestFlight/真机验收清单分别在 `AppStore/review-notes.md`、`AppStore/testflight-checklist.md`。
- `make release-audit` 检查版本源、已移除隐私文件的约束、HealthKit/CloudKit/Sandbox entitlement、目录覆盖率、疑似密钥和本地最新归档校验。
- TestFlight、App Store Connect、生产 CloudKit Schema 仍需要项目所有者使用有效 Apple Developer 账号完成；本地代码和审计通过不等同于商店审核通过。

## 当前边界

- 餐食照片只保存在拍摄设备的 Application Support/MealPhotos 中，不进入 CloudKit。
- 端侧识别只负责菜名、食材和份量建议；热量和营养始终由本地目录确定性计算，匹配不到时不使用模型营养兜底。
- CloudKit 代码、私有 Zone、记录 Payload、离线队列、墓碑和三向合并已完成，并通过 mock transport 自动化测试；使用真实 CloudKit Container 的 iPhone 17 与 Mac 双端同步仍需开发者签名后真机验收。
- Open Food Facts 扫码尚未接入 UI；照片媒体 ZIP 已接入备份与恢复。
- 已支持 CSV 食物目录导入、直接营养数据和配料配方两种复合食物模式。
- 手工记录首版支持新增、删除和每日汇总；历史记录编辑与餐次调整尚未加入。
- iOS UI 测试使用 `--ui-testing-in-memory-store`；该 Debug 模式不读写真实 SwiftData，也不请求 HealthKit 或照片分析权限。
- 真机 UI 测试可使用 XcodeGen 的 `DeviceTest` 配置；该配置只包含 HealthKit entitlement，并会编译为本地优先模式、完全禁用 CloudKit，避免无 iCloud entitlement 时启动崩溃。
- 设置页“关于”动态显示当前营销版本、构建号和完整版本，数值来自 App Bundle。
- 设置页展示 Health 来源、三项指标、最后更新时间和来源选择器。
- 健康消耗更新时间使用“X 分钟前”或“X 小时 Y 分钟前”，不显示秒数。
- 食物库和餐次添加页使用独立搜索状态与 200ms 防抖；搜索按当前语言名称、别名、拼音、前缀、FTS 和受控模糊匹配排序，并显示“名称精确、别名、拼音、前缀、模糊”等命中原因。
- 未内置完整中国食物成分表；缺少明确公开再分发许可，后续有授权文件时可通过导入器扩充。
- 当前台湾 FDA 文件未作为参考层打包；本地翻译缓存保证 13,627 / 13,627 中文名称覆盖。
- 本地机器翻译名称属于辅助信息，可能不如人工译名准确；详情页始终保留英文原名供核对。
- 系统权限弹窗、主屏幕名称和冷启动封面跟随设备系统语言，不受应用内覆盖语言影响。
- 语言偏好仅保存在当前设备，不同步到另一端的 App。
- 照片和 Apple Watch 消耗均为估算值，App 不提供医疗建议。
- 复合食物优先使用直接权威每 100 克数据；没有直接数据时按配方和成品重量计算，缺营养不会被补零。
- 照片匹配按规范菜名、候选别名和可见食材分层加权，并合并规范组、复合菜优先级与本机确认历史；最佳结果必须同时达到 0.80 分数和 0.10 领先差距，低置信度或泛化名称不会默认选中。
- DeepSeek 识别会把用户确认后的最多三张照片发送至 DeepSeek API；Vision 先检查过暗、过曝、低对比度、模糊和主体过小，差图要求补拍。包装营养标签数据在用户确认前保持估算状态，混合餐热量和营养始终由本地目录计算。
