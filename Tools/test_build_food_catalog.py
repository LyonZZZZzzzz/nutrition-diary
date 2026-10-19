#!/usr/bin/env python3
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_food_catalog", ROOT / "Tools/build_food_catalog.py")
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)


class FoodCatalogLocalizationTests(unittest.TestCase):
    def food(self, name="Food, raw", **extra):
        value = {
            "name": name,
            "nameEn": name,
            "nameZh": None,
            "nameZhOrigin": None,
            "aliases": [],
            "category": "Other",
        }
        value.update(extra)
        return value

    def test_manual_then_taiwan_then_machine_priority(self):
        foods = [
            self.food("Curated", nameZh="人工名称", nameZhOrigin="curated"),
            self.food("Tomatoes, raw"),
            self.food("Machine food"),
        ]
        cache = {
            "entries": {
                "Machine food": {"nameZh": "机器名称", "origin": "localMachineTranslation"},
            }
        }
        counts = catalog.apply_localizations(
            foods,
            cache,
            {"tomatoesraw": "番茄"},
        )
        self.assertEqual(foods[0]["nameZh"], "人工名称")
        self.assertEqual(foods[1]["nameZh"], "番茄")
        self.assertEqual(foods[1]["nameZhOrigin"], "taiwanFDA")
        self.assertEqual(foods[2]["nameZh"], "机器名称")
        self.assertEqual(foods[2]["nameZhOrigin"], "localMachineTranslation")
        self.assertEqual(counts["curated"], 1)
        self.assertEqual(counts["taiwanFDA"], 1)
        self.assertEqual(counts["localMachineTranslation"], 1)

    def test_missing_translation_blocks_build(self):
        with self.assertRaisesRegex(ValueError, "missing Chinese names"):
            catalog.apply_localizations([self.food("Unknown food")], {"entries": {}})

    def test_translation_rules_cover_required_terms_and_brands(self):
        rules = json.loads((ROOT / "Tools/food-name-translation-rules.json").read_text())
        self.assertEqual(rules["exactOverrides"]["Tomatoes, grape, raw"], "圣女果（生）")
        self.assertIn("McDONALD'S", rules["brands"])
        self.assertIn("Big Mac", rules["terms"])

    def test_bilingual_terms_are_indexed(self):
        terms = catalog.search_terms(["苹果", "Apple", "Red apple"])
        self.assertIn("苹果", terms)
        self.assertIn("apple", terms)
        self.assertIn("苹果苹果", catalog.search_terms(["苹果苹果"]).split())

    def test_runtime_sqlite_does_not_duplicate_payload_tables(self):
        import sqlite3
        import tempfile

        food = self.food(
            "Test food",
            id=catalog.stable_uuid("food", "test-food"),
            nameZh="测试食物",
            nameZhOrigin="curated",
            categoryZh="其他",
            categoryEn="Other",
            referenceAmount=100,
            referenceUnit="g",
            edibleRatio=1,
            densityGramsPerMilliliter=None,
            nutrients=[],
            portions=[],
            aliases=[],
            source={"title": "Test", "identifier": "test"},
            barcode=None,
            isFavorite=False,
        )
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "Catalog.sqlite"
            manifest = pathlib.Path(directory) / "catalog-manifest.json"
            catalog.build_sqlite(
                [food],
                output,
                manifest,
                {"sources": "[]"},
                {"schemaVersion": 1},
            )
            connection = sqlite3.connect(output)
            names = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            profile = connection.execute("SELECT value FROM catalog_meta WHERE key='storage_profile'").fetchone()
            connection.close()
            self.assertNotIn("nutrients", names)
            self.assertNotIn("servings", names)
            self.assertIn("food_search", names)
            self.assertEqual(profile[0], "payload_fts_only")


if __name__ == "__main__":
    unittest.main()
