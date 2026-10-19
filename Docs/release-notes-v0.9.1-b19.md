# v0.9.1-b19

- App version: 0.9.1
- Build: 19
- Created: 2026-10-17

## 修正内容

- 修正源码归档遗漏 `Tools/` 目录的问题，确保目录构建器、翻译规则和 Python 测试可以从版本 ZIP 完整复现。
- 本补丁不改变 App 功能、中文名称、营养数据、目录 schema 或用户数据格式。
- `v0.9.0-b18` 保持不可变，不覆盖其源码包或校验文件。

## 验证结果

- 13,498 / 13,498 条目录记录保持完整中文名称覆盖。
- 58 项共享单元/集成测试、4 项 Python 目录本地化测试和 5 项 iOS UI 测试通过。
- iOS 27 和 macOS 15+ 构建通过。
- 新源码 ZIP 包含 `Tools/build_food_catalog.py`、`Tools/food-name-translation-rules.json`、`Tools/test_build_food_catalog.py` 和全部翻译缓存。

## 兼容性

- 与 0.9.0 完全兼容。
