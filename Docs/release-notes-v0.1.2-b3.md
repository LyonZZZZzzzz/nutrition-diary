# v0.1.2-b3

归档工具修复版本。

## 修复

- `make verify-release` 不再硬编码旧版本目录，默认校验 `Releases/index.json` 中登记的最新版本。
- 保留显式指定版本路径的能力，便于历史版本审计。

## 验证

- 通过 Swift 包单元测试。
- 通过 iOS 27 与 macOS 15 编译。
- 通过最新版本归档校验。

## 已知边界

- 本版本不改变 App 业务代码或手机端行为。
- CloudKit Container 仍需在 Apple Developer 后台创建后，才能进行包含完整 iCloud entitlement 的正式真机签名。
