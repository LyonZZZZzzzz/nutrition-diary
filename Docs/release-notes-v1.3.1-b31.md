# 1.3.1 (31)

## 用户可见变化

- 移除设置页中的隐私政策与数据删除说明链接，保留食物数据来源、支持反馈和本地数据删除功能。
- 食物数据来源分组更名为“数据与来源”，不再依赖已删除的公开法律页面。

## 开源与仓库变化

- 删除 `PrivacyInfo.xcprivacy`、App Store 隐私问卷、公开隐私政策和数据删除页面。
- 新增 MIT License，版权人 `lyonzhu`。
- 新增第三方声明，区分 MIT 软件许可与 USDA、台湾 FDA、Open Food Facts、Apple 和 DeepSeek 的独立条款。
- `Releases/` 改为仅本地归档并从开源仓库排除；历史版本不会被推送。
- 移除 Git LFS 规则，SQLite 目录作为普通 Git 文件提交。
- 增加证书、描述文件、环境文件和本地密钥的忽略规则。

## 验证结果

- 共享测试、iOS UI 测试、双端构建、发布审计和归档校验结果以本版本归档 manifest 为准。
- 发布审计会主动确认四个已删除隐私文件没有重新进入工作区。
- 开源仓库扫描将另外检查旧隐私 URL、构建缓存、密钥、证书和大文件。

## 已知边界

- 删除 `PrivacyInfo.xcprivacy` 后，本项目不再满足 App Store 隐私清单要求，不能以当前开源状态直接提交 App Store。
- 删除公开隐私政策和数据删除页面后，现有 App Store 隐私 URL 与数据删除 URL 不再可用；`AppStore/metadata.json` 已同步移除对应字段。
- 本版本未完成新的 App Store、TestFlight 或真实设备验收；公开仓库只代表源码共享状态。
