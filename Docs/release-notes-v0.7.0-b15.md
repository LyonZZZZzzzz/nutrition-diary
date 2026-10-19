# v0.7.0-b15

- App version: 0.7.0
- Build: 15
- Created: 2026-10-17

## 用户可见变化

- 设置页新增“语言 / Language”，支持跟随系统、简体中文和 English。应用内切换即时生效，无需重启。
- 主界面、食物库、餐次添加、照片确认、健康明细、营养名称、导入导出、错误提示和版本信息支持中英双语。
- 中文模式下，默认食物列表优先显示有可靠中文名称的食物；长尾 USDA 食物保留英文原名并标注“英文原名”。
- 搜索同时索引中英文名称、别名和来源原名；中文“苹果”与英文“apple”都可命中同一食物。
- 新建复合食物时可分别填写中文名称、英文名称、中文分类和英文分类。
- 新饮食记录保存中英文食物名称和份量描述快照，旧记录继续使用原有名称安全回退。
- iOS 冷启动封面增加英文资源，并根据设备系统语言选择；应用内语言覆盖不会改变系统启动页、权限弹窗或主屏幕名称。
- 食物数据来源页显示当前目录的中英文名称覆盖统计。

## 技术变化

- 新增 `AppLanguage`、`AppLanguagePreference` 和 `AppLanguageResolver`；语言偏好保存在本机 `UserDefaults`，不进入 CloudKit 或备份。
- 新增 `Localizable.xcstrings`、`InfoPlist.xcstrings` 和 `Scripts/verify_localizations.py`，本地化覆盖率校验已加入 `make test`。
- `FoodItem`、`ServingPortion`、`FoodSource`、`DiaryEntry` 和 `CompositeFoodDefinition` 增加可选双语字段，缺失字段保持旧数据兼容。
- `Catalog.sqlite` 升级到 schema v2，新增 `name_zh`、`name_en`、`category_zh`、`category_en`；FTS 同时索引中英文文本。
- 新增 `FoodLocalizationOverlay.json`，为 110 项人工种子提供完整英文名称、分类、来源和份量标签。
- 当前离线目录记录数为 13,498；中文名称覆盖 110 条人工种子，英文名称覆盖 13,697 条。
- Apple 本机识别和 DeepSeek Vision 请求会按当前应用语言输出菜品名称；包装标签品牌与原文不被强制改写。
- 健康来源类型、覆盖说明、相对更新时间和共享计算错误支持英文显示。

## 验证结果

- `make test`：50 项共享包测试通过，本地化完整性校验通过，共 245 个 String Catalog 键。
- iOS 27 模拟器构建通过；macOS 15+ 构建通过。
- iPhone 17 模拟器英文设置页与英文食物库检查通过；中文食物库检查显示中文种子列表，不再默认显示 USDA 英文长尾。
- iPhone 17 真机安装并启动通过；真机英文设置页显示完整英文，健康来源与更新时间正常；中文食物库显示中文种子列表。
- `devicectl` 确认真机安装版本为 0.7.0、构建号 15；本次使用临时 HealthKit-only entitlement 完成安装，占位 iCloud 容器未用于真机签名。
- 安装包确认包含 `en.lproj/Localizable.strings`、`zh-Hans.lproj/InfoPlist.strings` 和 `en.lproj/InfoPlist.strings`。

## 已知边界

- 台湾 FDA 数据未包含在当前离线目录；构建工具支持通过 `--taiwan-file` 导入，manifest 已记录缺失状态。
- 13,498 条目录中仅 110 条有审核中文名称；其余长尾按方案保留英文原名，不进行自动机器翻译。
- 系统权限弹窗、主屏幕名称和冷启动封面由系统语言决定，不能跟随应用内强制语言。
- 语言偏好仅在当前设备生效，不同步到另一端的 App。
- 本轮未调用真实 DeepSeek 服务验证英文输出；请求构造和提示语言由 URLProtocol 单元测试覆盖。
