# v1.1.4-b28

- App version: 1.1.4
- Build: 28
- Created: 2026-10-17

## 修复

- 将 `CloudKit/`、Development Schema、Production Schema 和 CloudKit 工具纳入源码归档。
- 发布审计现在要求两个 `.ckdb` Schema 快照存在。
- 应用行为与 v1.1.3-b27 相同。

## 已验证能力

- 正式 Debug：CloudKit Development。
- Release：CloudKit Production。
- iPhone 与 Mac Development 同步成功：0 待上传、0 冲突、idle。
- Production Schema 通过 CloudKit Console 部署成功。
- DeviceTest 保持 HealthKit-only，不访问 CloudKit。
- SwiftData 使用独立 CKSyncEngine，显式关闭原生 CloudKit 集成。
- 云同步使用 `businessRecordID`，并在更新前获取 server change tag。

## 验证

- 72 项共享测试。
- 8 项 iOS UI 测试。
- iOS/macOS Debug 和 Release 签名构建。
- 发布审计与归档校验通过。
