# v1.0.0-b23

- App version: 1.0.0
- Build: 23
- Created: 2026-10-17

## 用户可见变化

- 1.0 发布候选整合本地食物检索、餐食记录、照片识别、HealthKit 能量平衡、双语界面、备份恢复和 iCloud 同步。
- 设置页可查看真实 iCloud 同步状态，并分别删除本机数据或本机与 iCloud 数据。

## 技术变化

- 新增 `AppStore/metadata.json`、隐私问卷、审核备注和 TestFlight 发布验收清单。
- 新增 `Scripts/release-audit.sh` 与 `make release-audit`，检查版本源、隐私清单、HealthKit/CloudKit/Sandbox entitlement、目录 100% 中文覆盖、疑似密钥和最新归档。
- 确认 `NutritionSyncRecord` 私有 CloudKit Schema 文档和生产部署步骤。
- 确认 App Store 隐私说明、支持链接和数据删除链接的本地源文件。
- 目录保持 `payload_fts_only` 结构，13,498 条记录、13,498 条中文名称和 FTS 索引。

## 验证结果

- 共享单元/集成测试通过。
- iOS UI 测试和冷启动性能采样通过。
- iOS 27 与 macOS 15+ Debug 构建通过。
- v0.10.0-b20、v0.11.0-b21、v0.12.0-b22 历史归档均已校验通过。
- 本次归档会再次执行测试、UI 测试、双端构建和归档校验。

## 未完成或未验证项

- TestFlight、App Store Connect 应用记录、签名上传和商店审核未执行，因为当前环境没有项目所有者的有效 Apple Developer 凭据。
- 真实 CloudKit Container 的 iPhone 17 与 Mac 双端同步未执行；mock transport 测试不能替代真实账号验收。
- 生产 CloudKit Schema 尚未部署。
- HealthKit 真机授权、写入去重和健康数据来源仍需在 TestFlight 阶段按清单验收。
- 公开发布法务页面仍需要将 `LegalSite/` 推送到公开 GitHub Pages 仓库；本地页面源文件已准备。
