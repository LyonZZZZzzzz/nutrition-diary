# v0.2.0-b5

Apple Intelligence 不可用时的 DeepSeek Vision 替代版本。

## 新增

- 照片页支持“混合餐”和“包装营养标签”两种识别模式。
- 新增 DeepSeek `deepseek-flash` Vision 识别路径，使用 OpenAI 兼容 Chat Completions API。
- 新增本机 Keychain API Key 管理、保存、测试和删除。
- 每次 DeepSeek 识别前显示照片上传、费用和隐私确认。
- 混合餐由 DeepSeek 提取菜品、食材与份量，热量和营养仍由本地食物目录计算。
- 包装营养标签由 DeepSeek 提取标签数值，支持每 100 克、每 100 毫升和每份换算。
- 包装食品确认后保存为本地自定义食物，营养状态保持“估算”。
- Apple Intelligence 不可用时不再以错误弹窗阻断照片页，改为提供 DeepSeek 路径。

## 技术实现

- DeepSeek 请求固定模型 `deepseek-flash`、关闭 thinking、启用 JSON Output。
- 最多三张照片，缩放至最长边 1600 像素并转为 JPEG 后 Base64 发送。
- DeepSeek API Key 使用 Keychain，本设备可用且不同步。
- 网络请求使用 ephemeral URLSession，不保存 Cookie、磁盘缓存或响应内容日志。
- 对超时和 5xx 自动重试一次；401、402、413 和 429 提供明确错误提示。

## 验证

- Swift 测试通过，包括 DeepSeek 请求体、Authorization Header、thinking 关闭、JSON 解析、代码围栏清理、401 映射和每份转每 100 克。
- iOS 27 与 macOS 15 构建通过。
- 已在 Lyon 的 iPhone 17、iOS 27.0.1 上安装 `0.2.0-b5` 并直接打开拍照页。
- 真机确认 Apple Intelligence 不可用时不再弹出阻断错误，页面正常展示 DeepSeek 替代入口。
- 未提供真实 DeepSeek API Key，因此真实云端混合餐与包装标签识别尚未完成线上验收。

## 已知边界

- 本次未实现条码扫描、Open Food Facts 和本地营养标签 OCR。
- DeepSeek 返回的包装营养值仍需用户人工核对。
- Apple Intelligence 端侧能力继续受设备、系统语言和区域资格限制。
