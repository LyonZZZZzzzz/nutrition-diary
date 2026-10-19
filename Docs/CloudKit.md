# CloudKit 同步与生产 Schema

## 容器与 Zone

- Container：`iCloud.com.lyonzhu.NutritionDiary`
- Database：私有数据库
- Custom Zone：`NutritionDiary`
- Record Type：`NutritionSyncRecord`

## 字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `recordKind` | String | 记录类型 |
| `businessRecordID` | String | 业务 UUID；避免使用 CKRecord 保留键 `recordID` |
| `schemaVersion` | Int64 | Payload 版本 |
| `payload` | Bytes | 业务 JSON |
| `updatedAt` | Date | 业务更新时间 |
| `deletedAt` | Date | 可选删除墓碑时间 |
| `deviceID` | String | 匿名设备标识，不含硬件序列号 |

## 收集范围

同步包含饮食日记、自定义食物、复合食物、每日能量汇总和热量目标。照片、DeepSeek Key、HealthKit 原始样本、语言偏好和凭据不进入 CloudKit。

## 发布步骤

1. 在开发环境启用 CloudKit 并导入 `NutritionSyncRecord` Schema。
2. 使用 iPhone 17 与 Mac 各自登录同一开发 iCloud 账号，完成新增、修改、删除、离线、冲突和账号切换测试。
3. 在 CloudKit Console 将开发 Schema 部署到生产环境。
4. 使用 Release 签名再次验证私有 Zone 创建、增量拉取和生产环境写入。
5. 将真机验证结果写入对应 `RELEASES` 发布说明；未验证时不得标记为已通过发布验收。

## 实现说明

- SwiftData 使用 `cloudKitDatabase: .none`。同步由独立 `CKSyncEngine` 完成，禁止启用 SwiftData 自带的 CloudKit 集成，因为它不支持 `SyncMetadataRecord.recordKey` 的唯一约束。
- Debug entitlement 使用 Development，Release entitlement 使用 Production。
- DeviceTest 只包含 HealthKit，并在 `DEVICE_TEST` 条件下设置 `cloudSync = nil`。

## 已知限制

- 当前 Development 容器请求已到达 CloudKit，但返回 `CKError 15 / CKInternalErrorDomain 2000 / HTTP 500`；需要 CloudKit Console 管理 token 和 Schema 初始化后继续验证。
- 当前测试同时包含 mock transport 和正式签名真机诊断；双端真实同步尚未验收。
- CloudKit 账号变化会暂停同步，用户必须在设置页显式确认。
- HealthKit 数据删除不使用 CloudKit 删除接口；已写入 Health 的膳食样本必须在 Health App 中单独处理。
