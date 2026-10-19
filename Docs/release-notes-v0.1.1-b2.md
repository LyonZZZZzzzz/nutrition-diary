# v0.1.1-b2

真机测试修复版本。

## 修复

- 修正 XcodeGen entitlement 配置，避免重新生成工程时把 HealthKit 和 iCloud entitlement 清空。
- iOS 真机现在包含 HealthKit 写入/读取和 CloudKit 访问所需 entitlement。
- macOS 重新生成后保留 App Sandbox、网络和 iCloud entitlement。

## 验证

- 通过 Swift 包单元测试。
- 通过 iOS 27 与 macOS 15 编译。
- 在 Lyon 的 iPhone 17、iOS 27.0.1 上完成签名安装并启动。
- 真机确认 HealthKit entitlement 已进入签名产物，不再出现缺少 entitlement 错误。
- 首次尚未授权健康数据时不再弹出阻断错误，而是在设置页显示授权状态。
- HealthKit 授权、Apple Watch 数据读取和照片识别仍需用户在真机上完成权限确认后继续验收。

## 已知边界

- CloudKit 实际记录同步仍待接入。
- 本次更新不改变照片识别、营养计算或既有数据结构。
