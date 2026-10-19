# v0.1.3-b4

HealthKit 授权闪退修复版本。

## 修复

- 修复 XcodeGen 重写 `Info.plist` 后丢失 `NSHealthShareUsageDescription` 和 `NSHealthUpdateUsageDescription` 的问题。
- 恢复相机、照片库、健康读取、健康写入和界面方向说明。
- 恢复正确的 App 显示版本和构建号，不再使用默认 `1.0 (1)`。
- 增加仅 Debug 构建可用的健康授权测试启动参数，正式运行不会自动弹出权限。

## 验证

- 通过 Swift 包单元测试。
- 通过 iOS 27 与 macOS 15 编译。
- 安装到 Lyon 的 iPhone 17、iOS 27.0.1，并使用测试参数触发 HealthKit 授权路径。
- 真机确认系统“访问健康数据”权限页正常出现，App 进程持续运行，不再闪退。

## 已知边界

- HealthKit 授权仍需用户在系统权限页确认。
- iCloud CloudKit Container 尚未在开发者账号中创建，正式包含 iCloud entitlement 的真机构建仍需要该配置。
