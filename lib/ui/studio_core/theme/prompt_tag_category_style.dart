import 'package:flutter/material.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';

Color promptTagCategoryColor(PromptTagCategory category) {
  return switch (category) {
    PromptTagCategory.character => const Color(0xFF5B8DEF),
    PromptTagCategory.upperBody => const Color(0xFF00B894),
    PromptTagCategory.lowerBody => const Color(0xFF36CFC9),
    PromptTagCategory.upperClothing => const Color(0xFF00A676),
    PromptTagCategory.lowerClothing => const Color(0xFF2E9F9F),
    PromptTagCategory.clothing => const Color(0xFF13C2C2),
    PromptTagCategory.action => const Color(0xFFF59E0B),
    PromptTagCategory.scene => const Color(0xFF8B9DC3),
    PromptTagCategory.camera => const Color(0xFF60A5FA),
    PromptTagCategory.artist => const Color(0xFFD946EF),
    PromptTagCategory.style => const Color(0xFFA78BFA),
    PromptTagCategory.quality => const Color(0xFFEAB308),
    PromptTagCategory.negativeQuality => const Color(0xFFEF4444),
    PromptTagCategory.negativeBody => const Color(0xFFDB2777),
    PromptTagCategory.negativeArtist => const Color(0xFFA855F7),
    PromptTagCategory.negativeContent => const Color(0xFFA16207),
    PromptTagCategory.promptSyntax => const Color(0xFF94A3B8),
    PromptTagCategory.other => StudioTokens.borderStrong,
  };
}
