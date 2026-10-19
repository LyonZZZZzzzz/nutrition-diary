# v1.1.3-b27

- App version: 1.1.3
- Build: 27
- Created: 2026-10-17

## CloudKit 正式签名

- 固定 Team `ZRY7UHFY75`；Debug 使用 CloudKit Development，Release 使用 Production。
- 新增可复现 `SystemCapabilities` 后处理，正确启用 iOS HealthKit/iCloud 与 macOS iCloud。
- iOS 正式 Debug 和 macOS Debug 描述文件均包含 `iCloud.com.lyonzhu.NutritionDiary`。
- DeviceTest 继续保持 HealthKit-only，并禁用 CloudKit。

## 启动与同步修复

- 显式设置 SwiftData `cloudKitDatabase: .none`，避免原生 SwiftData CloudKit 与 `.unique` 约束冲突导致启动失败。
- 启动错误页显示完整 NSError domain、code、userInfo 和底层错误。
- CloudKit 自定义业务 UUID 字段改为 `businessRecordID`，避免使用 CKRecord 保留键 `recordID`。
- CloudKit 字段使用 `NSNumber`、`NSData`、`NSDate` 显式桥接。
- 推送前批量读取已有 CKRecord，保留 server change tag，修复 `Server Record Changed`。

## Development 验收

- iPhone 17 正式 Debug 包原位安装，现有 6 条活跃饮食记录和本地照片保留。
- iPhone CloudKit 状态：account available、20 条同步元数据、0 待上传、0 冲突、idle。
- Mac Development 包拉取并合并相同数据，状态同为 0 待上传、0 冲突、idle。
- Development Schema 已导出为 `CloudKit/NutritionDiary-development.ckdb`。
- Production Schema 已通过 CloudKit Console 部署成功，部署快照为 `CloudKit/NutritionDiary-production.ckdb`。

## 验证结果

- 72 项共享测试通过。
- 8 项 iOS UI 测试通过。
- iOS/macOS Debug 与 Release 签名构建通过。
- CloudKit 发布审计和归档校验通过。
- 生产容器数据写入仍需 Release/TestFlight 包单独验收。
