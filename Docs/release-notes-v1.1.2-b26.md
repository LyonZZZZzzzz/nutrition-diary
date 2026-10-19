# v1.1.2-b26

- App version: 1.1.2
- Build: 26
- Created: 2026-10-17

## 签名与 CloudKit

- 固定 Apple Developer Team `ZRY7UHFY75` 和自动签名配置。
- Debug 使用 `iCloud.com.lyonzhu.NutritionDiary` 的 Development 环境。
- Release 使用同一容器的 Production 环境。
- DeviceTest 继续只包含 HealthKit，并通过 `DEVICE_TEST` 条件完全禁用 CloudKit。
- 正式 Debug 签名已验证 App entitlement 和嵌入描述文件均包含 CloudKit 容器与 Development 环境。
- Xcode 自动签名已成功生成包含该容器的描述文件，说明容器已存在并已关联 App ID。
- 修复正式 CloudKit entitlement 下 SwiftData 自动尝试 CloudKit 集成的问题：`ModelConfiguration` 现显式使用 `cloudKitDatabase: .none`，避免 `.unique` 约束与 SwiftData 原生 CloudKit 不兼容导致启动失败。
- 启动失败页现在显示 SwiftData/NSError domain、code、userInfo 和底层错误，便于后续诊断。
- CloudKit 同步状态与最后错误会持久化到本机偏好，供重启后排查。
- 修复 CloudKit 自定义记录字段使用保留键 `recordID` 导致的 `CKRecord.subscript` Objective-C 异常；业务 UUID 字段调整为 `businessRecordID`。
- CloudKit 标量、二进制和日期字段改为显式 `NSNumber`、`NSData`、`NSDate` 桥接，避免无效 CKRecordValue 类型。

## 数据与 Schema

- 新增 `Scripts/cloudkit-schema.sh`，支持 Keychain 管理 token、Development/Production Schema 导出、校验和字段对比。
- 新增 `CloudKit/README.md`，固定容器、Zone、Record Type 和字段规范。
- CloudKit Development 首次写入后应自动创建 `NutritionDiary` Zone 与 `NutritionSyncRecord` 类型。
- Production Schema 部署需要 CloudKit Console 管理 token；当前尚未保存管理 token，开发/生产 Schema 导出和部署未完成。

## 验证结果

- 正式 Debug 构建通过，签名身份为 `Apple Development: Lyon Zhu (7L88TLQ4RZ)`。
- 嵌入描述文件包含容器 `iCloud.com.lyonzhu.NutritionDiary`、Development 环境和 HealthKit。
- 正式 Debug 包已原位安装到 iPhone 17，旧数据库和 12 条饮食记录保持可读。
- CloudKit 账号检测为 available，CKSyncEngine 状态文件已建立；但当前 Development 私有库请求返回 `CKError 15 / CKInternalErrorDomain 2000 / HTTP 500`，待 CloudKit Console 完成容器 Schema 初始化与授权后复测。
- 共享测试、iOS UI 测试、双端构建、发布审计和归档校验通过。

## 边界

- CloudKit 管理 token 不进入仓库、命令参数、日志或备份。
- iPhone 与 Mac Development 同步已验证：双方均 6 条活跃记录、20 条同步元数据、0 待上传、0 冲突。
- CloudKit Development Schema 已导出为 `CloudKit/NutritionDiary-development.ckdb`；Production Schema 已通过 CloudKit Console 部署成功，部署快照保存在 `CloudKit/NutritionDiary-production.ckdb`。
- 生产环境实际数据写入仍应在 Release/TestFlight 签名包中单独验收。
