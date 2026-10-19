# TestFlight 与发布验收清单

当前状态：**未执行**。需要有权限的 Apple Developer 账号、签名描述文件和 App Store Connect 应用记录。

## 构建与上传

- [ ] 使用 Release 配置归档 iOS 和 macOS Target。
- [ ] 确认 iOS Bundle ID 为 `com.lyonzhu.NutritionDiary`，macOS Bundle ID 为 `com.lyonzhu.NutritionDiary.mac`。
- [ ] 确认版本 `1.1.4 (28)` 与 `project.yml` 一致。
- [ ] 确认 iOS HealthKit、iCloud/CloudKit entitlement 和 macOS App Sandbox 均通过签名。
- [ ] 在 CloudKit Console 部署 `NutritionSyncRecord` 生产 Schema。
- [ ] 上传 iOS 和 macOS 构建到 App Store Connect，创建 Internal Testing 组。

## 真机功能回归

- [ ] 首次安装和启动，冷启动封面显示正常。
- [ ] 食物搜索“鸡蛋”“地瓜”“拿铁”和英文 “apple”可命中。
- [ ] 记录鸡蛋家庭份量后今日营养和热量汇总正确。
- [ ] JSON 合并恢复和完整替换恢复各完成一次。
- [ ] 媒体 ZIP 导出并在另一安装实例恢复照片和记录。
- [ ] 删除本机数据与删除本机+iCloud 数据分别验证。
- [ ] 两台设备使用同一 iCloud 账号完成首次合并、增量同步和删除。
- [ ] 离线修改在恢复网络后上传。
- [ ] 制造同一条记录双端不同修改，确认冲突副本不参与统计。
- [ ] 切换 iCloud 账号时同步暂停并要求确认。
- [ ] Apple Watch 活动/静息能量、锻炼时间和来源选择与 Health App 对齐。
- [ ] HealthKit 写入后再次修改餐次，不生成重复膳食样本。
- [ ] DeepSeek Key 缺失、网络失败、401、余额不足和取消上传均安全降级。
- [ ] 确认照片、Key、HealthKit 原始样本不出现在 CloudKit、备份和日志中。

## 发布审计

- [ ] 运行 `make test`、`make test-ios-ui`、`make build-ios`、`make build-mac`。
- [ ] 运行 `make release-audit`。
- [ ] 运行 `./Scripts/archive-version.sh verify Releases/v1.1.4-b28`。
- [ ] 在 App Store Connect 填写年龄分级、隐私问卷、HealthKit 用途和审核备注。
- [ ] 完成 TestFlight 内测后记录设备、系统版本、日期和结果。
