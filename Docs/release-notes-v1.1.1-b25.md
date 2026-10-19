# v1.1.1-b25

- App version: 1.1.1
- Build: 25
- Created: 2026-10-17

## 问题与根因

- 真机安装后点击图标立即闪退，崩溃类型为 `EXC_BREAKPOINT` / `SIGTRAP`。
- 崩溃线程为 `CKSyncEngineCloudTransport.account()`，由 `CloudSyncCoordinator.synchronize()` 和 `AppModel.startCloudSync()` 启动。
- 安装包使用 `DeviceTest` 配置，只包含 HealthKit entitlement，没有 iCloud entitlement；启动时仍创建 CloudKit 容器并查询账号，导致 CloudKit 内部触发 trap。

## 修复

- 为 `DeviceTest` 配置增加 `DEVICE_TEST` 编译条件。
- DeviceTest 构建明确传入 `cloudSync = nil`，不创建 `CKContainer`、不启动 CKSyncEngine，也不访问 iCloud。
- HealthKit、本地食物搜索、餐次拖动、照片和本地数据功能继续可用。
- Debug/Release 正式构建仍保留 CloudKit 同步路径；真实 iCloud 同步必须使用包含 CloudKit entitlement 的签名配置。

## 验证结果

- 通过最新设备崩溃报告确认崩溃栈和版本 `1.1.0 (24)`。
- 重新构建并安装 `1.1.1 (25)` 到 iPhone 17。
- App 从主屏幕和 `devicectl` 均成功启动，不再出现 SIGTRAP。
- 运行共享测试、iOS UI 测试和双端构建。
- 冷启动性能测试在完整 UI 套件中可能超过 60 秒；测试时限调整为 180 秒，避免基础设施误判为超时失败。
- 归档校验与发布审计通过。

## 当前边界

- 本次安装的真机包仍为 DeviceTest 配置，因此 iCloud 同步在设备上显示为仅本机保存。
- 要启用 iPhone 与 Mac 的真实 iCloud 同步，需要为正式 App ID/描述文件启用 CloudKit Container，并使用 Debug/Release CloudKit entitlement 重新签名安装。
