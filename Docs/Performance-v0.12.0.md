# v0.12.0 性能与维护性记录

## 本轮优化

- 将 `Catalog.sqlite` 的 `nutrients` 和 `servings` 冗余表移除。运行时查询只依赖 `foods.payload`、`food_search` FTS5 和 `catalog_meta`。
- 目录文件从 93,880,320 字节降至 64,036,864 字节，约减少 31.8%；仍保留 13,498 条食物记录和 13,498 条 FTS 索引记录。
- 文本搜索候选上限固定为 200，空查询允许分页读取全目录用于数据审计，但不会将全目录载入内存。
- 将 `AppModel` 的同步、健康和照片职责拆到 `AppModel+CloudSync.swift`、`AppModel+Health.swift` 和 `AppModel+Photo.swift`；主文件从约 830 行降至约 406 行。
- 新增 `CatalogPerformanceTests`，覆盖目录打开、首次中文搜索和宽泛中文查询，CI 可通过 `make benchmark-catalog` 单独运行。

## 基准结果

本机 iPhone 17 模拟器/Debug 构建上的目录测试记录如下；数值是开发机观测值，不作为其他设备承诺：

| 场景 | 结果 |
| --- | --- |
| 文本搜索候选上限 | 200 |
| “鸡”宽泛搜索 | 约 0.06–0.2 秒（测试环境） |
| “营养”宽泛搜索 | 约 0.06–0.2 秒（测试环境） |
| Catalog 记录数 | 13,498 |
| Catalog FTS 记录数 | 13,498 |
| Catalog 文件大小 | 64,036,864 字节（约 61 MiB） |

## 冷启动基准

`NutritionDiaryUITests.testColdLaunchPerformance` 使用 `XCTApplicationLaunchMetric` 记录冷启动指标，结果保存在 Xcode `.xcresult` 中。本次 iPhone 17 模拟器 Debug 测试的平均启动耗时为 3.850 秒，5 次采样为 3.888、3.695、3.804、3.888、3.974 秒，相对标准差 2.448%。该测试使用隔离内存数据库和测试启动参数，不代表用户真实数据规模下的启动时间。

## 回归门槛

- `make test` 必须继续通过 13,498 条目录、中文 FTS、照片候选和每日营养汇总测试。
- 文本搜索不得绕过 200 条候选上限。
- 目录优化不得删除 `foods.payload`、FTS 表或来源许可证元数据。
- 若未来替换 SQLite schema，必须保留旧 schema 的读取迁移和 100% 中文名称覆盖。
