# App Review 备注草稿

饮食营养记录是一款本地优先的饮食、营养和热量平衡 App。

- HealthKit 仅用于读取活动/静息能量和 Apple 锻炼时间，以及在用户确认后写入膳食营养。不会读取 Health 中的膳食能量来重复计算。
- Apple Watch 和照片识别数据均为估算值；App 不提供疾病诊断、治疗或自动医学建议。
- 餐食照片默认在本机处理。DeepSeek 需要用户自行配置 API Key，并在每次上传前明确确认；不配置时仍可使用本地搜索和手动记录。
- CloudKit 使用私有数据库，只同步非照片业务记录。没有可用 iCloud 账号时，App 仍完整支持本地记录。
- 演示账号不需要外部凭据。审核人员可在不配置 DeepSeek Key 的情况下完成搜索、份量确认和本地记录流程。

联系支持：https://lyonzhu.github.io/nutrition-diary-legal/support.html
