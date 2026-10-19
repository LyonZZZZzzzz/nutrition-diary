# v0.6.0-b14

权威食物库离线部署版本。

## 新增

- 新增构建期食物目录工具，支持 USDA Foundation、SR Legacy、FNDDS JSON。
- 生成只读 `Catalog.sqlite`，当前包含 13,498 条食物、约 30 万条营养记录，大小约 84MB。
- App 运行时改用 SQLite FTS5 搜索，不再一次加载全部权威目录。
- 保留 110 项人工种子并优先去重，补充咖啡、蔬果和混合食品。
- 食物搜索通过后台 actor 执行，支持简体中文、英文和别名。
- 照片食物匹配改用 SQLite 候选结果，不再扫描全量食物。
- 新增“食物数据来源与许可证”页面。
- 构建工具支持通过 `TAIWAN_FILE` 导入台湾 FDA 数据；缺失时必须显式允许 USDA-only 临时构建。

## 数据来源

- USDA FoodData Central Foundation Foods 2026-04-30，公共领域。
- USDA FoodData Central SR Legacy 2018-04，公共领域。
- USDA FoodData Central FNDDS 2021-2023，公共领域。
- 台湾 FDA 食品营养成分资料集接口已接入转换器，但本次官方下载主机连接失败，因此当前目录未包含台湾数据。
- Open Food Facts 不打包，继续按需在线查询并遵守 ODbL。

## 验证

- 42 个 Swift 测试全部通过。
- 验证 SQLite 记录数、manifest、中文“鸡/拿铁”搜索和照片匹配。
- iOS 27 与 macOS 15 构建通过。
- 真机安装约 84MB SQLite 资源，离线搜索“鸡”正确返回鸡蛋和鸡胸肉。

## 已知边界

- 台湾 FDA 官方主机不可用时不会自动使用第三方镜像。
- 当前 SQLite 为 USDA 加人工种子，尚非台湾 FDA 完整中文目录。
- 84MB 数据库会明显增加安装包和版本归档大小。
