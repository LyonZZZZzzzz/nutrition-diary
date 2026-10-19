# v0.1.0-b1

首个可运行的内部版本基线。

## 已实现

- SwiftUI iOS 27 与 macOS 15 双端工程。
- 今日营养、食物搜索、历史、拍照、设置和 JSON/CSV 导出。
- 使用 iOS 27 Apple Foundation Models 进行设备端餐食照片结构化识别，最多三张图片。
- 照片识别结果必须人工确认，热量与营养由本地食物目录确定性计算。
- 餐食原图保存在拍摄设备本地，删除记录时可选同时删除照片。
- HealthKit 读取 Apple Watch 活动与静息能量，计算活动净平衡和总热量平衡。
- HealthKit 写入膳食营养，使用同步标识和递增版本避免重复样本。
- SwiftData 本地持久化、平衡目标、每日能量汇总和冲突副本数据模型。
- 30 个带中文别名和家庭份量的常见食材种子。

## 当前边界

- CKSyncEngine 的 CloudKit 记录映射和真实三向冲突合并尚未完成。
- Open Food Facts 扫码、中国食物成分表导入器、自定义食谱编辑器和照片 ZIP 媒体包尚未接入 UI。
- 端侧照片识别和 HealthKit 真机流程需要支持 Apple Intelligence 的 iPhone、付费开发者签名和真机验收。
