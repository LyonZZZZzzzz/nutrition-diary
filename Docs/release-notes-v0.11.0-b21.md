# v0.11.0-b21

- App version: 0.11.0
- Build: 21
- Created: 2026-10-17

## 用户可见变化

- 设置页新增真实 iCloud 同步状态、iCloud 账号状态、待上传数量、冲突数量、最后成功同步时间和“立即同步”。
- 支持“删除本机与 iCloud 数据”，与“仅删除本机数据”分开二次确认。
- iCloud 账号变化时暂停同步并要求用户显式确认，避免把上一账号的数据上传到新账号。

## 技术变化

- 新增 `CloudSyncServing`、`CloudSyncState`、`CloudSyncTransport`、`SyncRecordEnvelope` 和 `SyncRecordKind`。
- 新增基于 `CKSyncEngine` 的私有自定义 Zone transport，记录键固定为 `<recordKind>:<UUID>`。
- 新增 SwiftData `SyncMetadataRecord`，保存上次同步 Payload、更新时间和删除墓碑状态。
- 日记、自定义食物、复合食物、每日能量汇总和热量目标进入同步范围；照片、Key、HealthKit 原始样本、语言偏好和凭据排除。
- 合并支持首次本机/云端合并、三向修改判断、较新记录优先、冲突副本、墓碑、幂等重复拉取和离线待上传队列。
- 预览 CloudKit 错误、账号状态和同步按钮支持中英文提示。

## 验证结果

- 新增 5 项 mock transport 同步测试，覆盖首次推送、较新云端覆盖、墓碑、离线重试、账号切换确认和重复同步幂等性。
- 新增同步相关 Swift 编译和双端构建验证。
- 现有共享测试、双语资源校验和目录构建测试继续通过。
- 真机 CloudKit 双端同步尚未执行，因为当前环境没有可用的已登录 GitHub/Apple Developer 发布身份；发布说明不将 mock 测试描述为真机验收。
