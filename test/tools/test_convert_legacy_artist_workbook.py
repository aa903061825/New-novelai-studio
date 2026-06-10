from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


def load_converter():
    module_path = Path(__file__).resolve().parents[2] / "tool" / "convert_legacy_artist_workbook.py"
    spec = importlib.util.spec_from_file_location("convert_legacy_artist_workbook", module_path)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class FakeWorksheet:
    title = "角色名"


class ConvertLegacyArtistWorkbookTest(unittest.TestCase):
    def test_artist_prompt_like_rejects_style_only_and_negative_dumps(self):
        converter = load_converter()

        self.assertFalse(
            converter.artist_prompt_like(
                "uncensored, official art, official_style, natural, "
                "1.5::humid skin::, 1.2::detailed skin texture::, "
                "2::shiny skin::, deep skin, motion lines, speed lines"
            )
        )
        self.assertFalse(
            converter.artist_prompt_like(
                "{{bad quality, low quality, worst quality}}, "
                "bad hands, bad anatomy, missing finger, extra finger, "
                "duplicate, deformed, extra arms, extra legs, bad feet, "
                "{{artist:bkub, mosaic censoring, mosaic}}, blurry, lowres, "
                "logo, text, watermark, signature, artist collaboration"
            )
        )

    def test_artist_prompt_like_keeps_prefixed_and_weighted_artist_names(self):
        converter = load_converter()

        self.assertTrue(
            converter.artist_prompt_like(
                "1.3::artist:hakushiro::, 1.2::artist:quasarcake::, "
                "artist:wanke"
            )
        )
        self.assertTrue(
            converter.artist_prompt_like(
                "0.9:: kedama_milk ::, 1.2::ciloranko ::, "
                "0.35:: ask_(askzy)::, 0.85:: chen_bin ::"
            )
        )

    def test_header_character_ignores_unlabeled_prompt_dumps(self):
        converter = load_converter()
        labels = [
            "音律联觉",
            "艾雅法拉",
            "泳装",
            "毛茸茸",
            "童话爱丽丝",
            "羊角，耳朵",
            "",
            "",
        ]
        values = [
            "eyjafjalla (ambience synesthesia) (arknights)",
            "eyjafjalla_(arknights)",
            "eyjafjalla_(summer_flower)_(arknights)",
            "eyjafjalla (fluffy little witch) (arknights)",
            "eyjafjalla the hvit aska (a picnic before a long trip) (arknights)",
            "animal ears, sheep_horns",
            "rosmontis (arknights)\npepe_(arknights), cat_ears, cat_tail",
            "artist:quan_(kurisu_tina), artist:wanke, artist:ningen_mame",
        ]

        character = converter.import_header_character(FakeWorksheet(), labels, values)

        self.assertIsNotNone(character)
        self.assertEqual(
            [outfit["name"] for outfit in character["outfits"]],
            [
                "音律联觉",
                "泳装",
                "毛茸茸",
                "童话爱丽丝",
            ],
        )

    def test_row_character_keeps_upper_lower_prompts_out_of_outfits(self):
        converter = load_converter()
        row = [
            "缇缇",
            "titi_(arknights), cat_ears, cat_tail",
            "上装",
            "black_necktie, collared_shirt, jacket, white_shirt",
            "下装",
            "black_dress, black_thighhighs, dress, thighhighs",
        ]

        character = converter.import_row_character(FakeWorksheet(), 30, row)

        self.assertIsNotNone(character)
        self.assertEqual(character["outfits"], [])
        self.assertEqual(
            character["traits"]["front_upper"],
            "black_necktie, collared_shirt, jacket, white_shirt",
        )
        self.assertEqual(
            character["traits"]["front_lower"],
            "black_dress, black_thighhighs, dress, thighhighs",
        )


if __name__ == "__main__":
    unittest.main()
