# v0.10.0-b20

- App version: 0.10.0
- Build: 20
- Created: 2026-10-17

## 用户可见变化

- 设置页新增 JSON 备份恢复，支持安全合并和经二次确认的完整替换。
- 新增含本地 MealPhotos 的媒体备份 ZIP 导出与恢复。
- 新增“删除本机数据”，清除当前设备上的饮食记录、自定义食物、复合食物、目标、能量汇总、冲突副本和本地照片。
- 数据删除说明明确 Health App 中已写入的膳食样本不会被自动删除。
- 数据库启动失败不再直接崩溃，改为显示诊断、重试和经确认后重建本地数据库。
- 设置页增加隐私政策、支持反馈和数据删除说明链接。

## 技术变化

- 新增 `PrivacyInfo.xcprivacy`，声明 Health、Fitness、Photos/User Content 和 UserDefaults Required Reason API 用途。
- 权限说明更新为：照片默认本地处理，仅在用户逐次确认后发送至 DeepSeek。
- 备份格式升级到 v2，包含自定义食物和复合食物，同时兼容 v1。
- 新增无第三方依赖的 ZIP 存储实现和 `MediaBackupService`。
- 新增 `AppStartupState` 对应的启动恢复界面，并固定 SwiftData 数据库路径以支持安全重置。
- 3.1MB 本地翻译缓存移出 App Bundle，改放到 `CatalogData/`。
- 安装并配置 Git LFS；源码 ZIP、截图和 SQLite 资源使用 LFS 跟踪。
- 新增私有 GitHub Actions 验证工作流和统一 `make verify`。
- 新增可独立部署的 GitHub Pages 法务与支持站点源文件。

## 验证结果

- 63 项共享单元/集成测试通过。
- 4 项 Python 目录本地化测试通过。
- 6 项 iOS UI 测试通过，包括备份入口、机器翻译记录和启动失败恢复。
- iOS 27 和 macOS 15+ 构建通过。
- 13,498 / 13,498 条食物中文名称覆盖保持不变。

## 已知边界与未验证项

- Git LFS 和本地 Git 配置已完成；GitHub CLI 当前未登录，因此私有远端仓库、推送和 GitHub Actions 实际运行尚未完成。
- GitHub Pages 法务站点文件已准备，但尚未创建公开远端仓库和发布 URL。
- CloudKit 真实 `CKSyncEngine`、云端数据删除和双端同步属于下一阶段 `0.11.0-b21`。
- JSON 恢复的自动测试已覆盖合并、替换、冲突和本地删除；文件选择器的人工操作仍需发布前真机验收。
