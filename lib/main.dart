// lib/main.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 1. Go to https://aistudio.google.com/apikey
/// 2. Create an API key (looks like: AIza...)
/// 3. Paste it here:
const String geminiApiKey = 'AIzaSyClHQlfS1eUv1c71fBvNm0rYym0n-nepAM';

void main() {
  runApp(const PlaideApp());
}

class PlaideApp extends StatelessWidget {
  const PlaideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plaide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF22C55E)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFEFFCF7),
        fontFamily: 'SF Pro',
      ),
      home: const PlaideHome(),
    );
  }
}

enum PlaideView { configure, recipe }

enum DetailTab { overview, ingredients, instructions }

class PlaideHome extends StatefulWidget {
  const PlaideHome({super.key});

  @override
  State<PlaideHome> createState() => _PlaideHomeState();
}

class _PlaideHomeState extends State<PlaideHome> {
  // Flow state
  PlaideView _view = PlaideView.configure;
  DetailTab _tab = DetailTab.overview;

  // Configure controllers
  final TextEditingController _dishController =
      TextEditingController(text: 'Pasta');
  final TextEditingController _maxTimeController = TextEditingController();
  final TextEditingController _maxCaloriesController = TextEditingController();
  final TextEditingController _servingsController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _maxPrepTimeController = TextEditingController();

  bool _useCustomSettings = false;

  // API state
  bool _isLoadingText = false;
  bool _isLoadingImage = false;
  String? _errorMessage;

  // Recipe data
  String _recipeTitle = '';
  String _overviewText = '';
  List<String> _ingredients = [];
  List<String> _steps = [];
  String _timeText = '';
  String _caloriesText = '';
  String _servingsText = '';

  // Image
  Uint8List? _imageBytes;

  // -------- Helpers --------

  String _limitTo200Words(String text) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= 200) return text;
    return words.take(200).join(' ') + ' ...';
  }

  void _resetRecipe() {
    setState(() {
      _recipeTitle = '';
      _overviewText = '';
      _ingredients = [];
      _steps = [];
      _timeText = '';
      _caloriesText = '';
      _servingsText = '';
      _imageBytes = null;
      _errorMessage = null;
    });
  }

  void _parseRecipeText(String raw) {
    final text = _limitTo200Words(raw);
    final lines = text.split('\n').map((l) => l.trim()).toList();

    int idx = 0;

    // Title: first non-empty line
    while (idx < lines.length && lines[idx].isEmpty) {
      idx++;
    }
    if (idx < lines.length) {
      _recipeTitle = lines[idx];
      idx++;
    }

    // Collect lines until "Ingredients:"
    final bufferOverview = <String>[];
    final lowerLines = lines.map((e) => e.toLowerCase()).toList();
    final ingIndex = lowerLines.indexWhere((l) => l.startsWith('ingredients'));
    final stepsIndex = lowerLines.indexWhere((l) => l.startsWith('steps'));

    // Extract Time / Servings / Calories from lines near the top
    for (int i = idx; i < lines.length; i++) {
      final l = lines[i];
      final lower = l.toLowerCase();
      if (lower.startsWith('time:')) {
        _timeText = l.substring(5).trim();
      } else if (lower.startsWith('servings:')) {
        _servingsText = l.substring(9).trim();
      } else if (lower.startsWith('calories:')) {
        _caloriesText = l.substring(9).trim();
      }
      if (i == ingIndex || i == stepsIndex) break;
    }

    if (ingIndex != -1) {
      for (int i = idx; i < ingIndex; i++) {
        if (lines[i].isNotEmpty) {
          bufferOverview.add(lines[i]);
        }
      }
    } else {
      for (int i = idx; i < lines.length; i++) {
        if (lines[i].isNotEmpty) bufferOverview.add(lines[i]);
      }
    }
    _overviewText = bufferOverview.join('\n');

    // Ingredients
    _ingredients = [];
    if (ingIndex != -1) {
      final end = stepsIndex != -1 ? stepsIndex : lines.length;
      for (int i = ingIndex + 1; i < end; i++) {
        final l = lines[i];
        if (l.isEmpty) continue;
        final cleaned = l.replaceFirst(RegExp(r'^[-•\d\.\) ]+'), '').trim();
        if (cleaned.isNotEmpty) {
          _ingredients.add(cleaned);
        }
      }
    }

    // Steps
    _steps = [];
    if (stepsIndex != -1) {
      for (int i = stepsIndex + 1; i < lines.length; i++) {
        final l = lines[i];
        if (l.isEmpty) continue;
        final cleaned = l.replaceFirst(RegExp(r'^\d+[\).\s]+'), '').trim();
        if (cleaned.isNotEmpty) {
          _steps.add(cleaned);
        }
      }
    }

    if (_ingredients.isEmpty && _steps.isEmpty && _overviewText.isEmpty) {
      _overviewText = text;
    }
  }

  // -------- Gemini TEXT --------

  Future<void> _generateRecipe({required String presetLabel}) async {
    final dish = _dishController.text.trim();
    if (dish.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a dish or ingredient.';
      });
      return;
    }

    if (geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE' ||
        geminiApiKey.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please paste your real Gemini API key in main.dart.';
      });
      return;
    }

    _resetRecipe();

    setState(() {
      _isLoadingText = true;
      _isLoadingImage = true;
      _view = PlaideView.configure; // keep here until recipe text arrives
      _tab = DetailTab.overview;
    });

    const modelName = 'gemini-2.5-flash';
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$geminiApiKey',
    );

    final description = StringBuffer()
      ..write('User wants a recipe for: $dish.\n')
      ..write('Preset: $presetLabel.\n');

    if (_useCustomSettings) {
      if (_maxTimeController.text.trim().isNotEmpty) {
        description
          ..write('Max cooking time (minutes): ')
          ..writeln(_maxTimeController.text.trim());
      }
      if (_maxCaloriesController.text.trim().isNotEmpty) {
        description
          ..write('Max calories per serving: ')
          ..writeln(_maxCaloriesController.text.trim());
      }
      if (_servingsController.text.trim().isNotEmpty) {
        description
          ..write('Servings: ')
          ..writeln(_servingsController.text.trim());
      }
      if (_budgetController.text.trim().isNotEmpty) {
        description
          ..write('Max budget (USD): ')
          ..writeln(_budgetController.text.trim());
      }
      if (_maxPrepTimeController.text.trim().isNotEmpty) {
        description
          ..write('Max prep time (minutes): ')
          ..writeln(_maxPrepTimeController.text.trim());
      }
    }

    final prompt = '''
You are a recipe assistant in a mobile app called Plaide.

Goal:
- Return ONE recipe that matches the description and constraints.
- Keep the TOTAL response UNDER 200 words.
- Make it simple and easy for a busy college student.

Format (VERY IMPORTANT):
Title
Time: xx min
Servings: x
Calories: (approximate, if possible)

Ingredients:
- item
- item

Steps:
1. step
2. step
3. step

$description
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    });

    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (resp.statusCode == 200) {
        final jsonResp =
            jsonDecode(resp.body) as Map<String, dynamic>? ?? {};
        String text = 'No recipe text returned.';

        final candidates = jsonResp['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final first = candidates[0];
          final content = first['content'];
          if (content is Map && content['parts'] is List) {
            final buffer = StringBuffer();
            for (final part in (content['parts'] as List)) {
              if (part is Map && part['text'] is String) {
                buffer.write(part['text']);
              }
            }
            if (buffer.isNotEmpty) {
              text = buffer.toString();
            }
          }
        }

        setState(() {
          _parseRecipeText(text);
          _view = PlaideView.recipe;
          _errorMessage = null;
        });

        // Fire image generation with combined description
        final imageDesc = '$dish recipe. $presetLabel. '
            '${_timeText.isNotEmpty ? "Time: $_timeText. " : ""}'
            '${_caloriesText.isNotEmpty ? "Calories: $_caloriesText. " : ""}'
            '${_servingsText.isNotEmpty ? "Servings: $_servingsText. " : ""}';
        await _generateRecipeImage(imageDesc);
      } else {
        setState(() {
          _errorMessage =
              'Gemini text error: ${resp.statusCode}\n${resp.body}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error while calling Gemini: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingText = false;
        });
      }
    }
  }

  // -------- Gemini IMAGE --------

  Future<void> _generateRecipeImage(String description) async {
    setState(() {
      _isLoadingImage = true;
      _imageBytes = null;
    });

    const imageModelName = 'gemini-2.5-flash-image';
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$imageModelName:generateContent',
    );

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text':
                  'Create a clear, bright, photorealistic food photo for a mobile recipe app. '
                      'Top-down or 3/4 angle, shallow depth of field, crisp focus on the dish, soft background, '
                      'natural lighting, 1024x1024 quality. Dish description: $description'
            }
          ]
        }
      ]
    });

    try {
      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          // For image we send the key as header (works reliably)
          'x-goog-api-key': geminiApiKey,
        },
        body: body,
      );

      if (resp.statusCode != 200) {
        debugPrint('Image generation error: ${resp.statusCode} ${resp.body}');
        if (mounted && _errorMessage == null) {
          setState(() {
            _errorMessage =
                'Could not generate image (code ${resp.statusCode}). Check Gemini billing / image access.';
          });
        }
        return;
      }

      final jsonResp =
          jsonDecode(resp.body) as Map<String, dynamic>? ?? {};
      String? base64Image;

      final candidates = jsonResp['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final first = candidates[0];
        final content = first['content'];
        if (content is Map && content['parts'] is List) {
          for (final part in (content['parts'] as List)) {
            if (part is Map) {
              final inline =
                  (part['inlineData'] ?? part['inline_data']);
              if (inline is Map && inline['data'] is String) {
                base64Image = inline['data'] as String;
                break;
              }
            }
          }
        }
      }

      if (base64Image != null) {
        final bytes = base64Decode(base64Image);
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
          });
        }
      } else {
        debugPrint('No inline image data in response: $jsonResp');
      }
    } catch (e) {
      debugPrint('Image generation network error: $e');
      if (mounted && _errorMessage == null) {
        setState(() {
          _errorMessage = 'Network error while generating image: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });
      }
    }
  }

  // -------- Feedback --------

  void _openFeedbackDialog({required bool liked}) {
    if (_recipeTitle.isEmpty && _overviewText.isEmpty) return;

    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.all(20),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      liked
                          ? Icons.thumb_up_alt_rounded
                          : Icons.thumb_down_alt_rounded,
                      color: liked
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        liked
                            ? 'Tell us what you liked!'
                            : 'Help us improve',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  liked
                      ? 'What made this recipe appealing to you? Your feedback helps us suggest better recipes.'
                      : 'What didn\'t work for you? Your feedback helps us improve our suggestions.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: liked
                        ? 'e.g., Perfect cooking time, loved the ingredients, easy to follow...'
                        : 'e.g., Too many ingredients, cooking time too long, not my taste...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Skip'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        final snack = liked
                            ? 'Support 👍 feedback recorded (demo).'
                            : 'Don’t Support 👎 feedback recorded (demo).';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(snack)),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text('Submit Feedback'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------- UI --------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5FFFB),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                child: Column(
                  children: [
                    _buildTopBar(context),
                    const SizedBox(height: 12),
                    if (_view == PlaideView.configure)
                      Expanded(child: _buildConfigureScreen(context))
                    else
                      Expanded(child: _buildRecipeScreen(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(Icons.restaurant_menu, color: Color(0xFF10B981)),
            const SizedBox(width: 4),
            Text(
              'plaide',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE0FDF2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Lv1',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16A34A),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFDE68A),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '30pts',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF854D0E),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: const [
            Icon(Icons.search, size: 20, color: Color(0xFF4B5563)),
            SizedBox(width: 8),
            Icon(Icons.notifications_none,
                size: 20, color: Color(0xFF4B5563)),
            SizedBox(width: 8),
            Icon(Icons.favorite_border,
                size: 20, color: Color(0xFF4B5563)),
          ],
        )
      ],
    );
  }

  // -------- Configure Screen --------

  Widget _buildConfigureScreen(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton.icon(
            onPressed: () {},
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.arrow_back_ios_new, size: 14),
            label: const Text('Back to Search'),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure your ${_dishController.text.isEmpty ? "recipe" : _dishController.text} recipe',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),

          // Dish text field
          TextField(
            controller: _dishController,
            decoration: InputDecoration(
              labelText: 'Dish',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),

          // Tag chips row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              'Pasta',
              'Chicken',
              'Salad',
              'Rice Bowl',
              'Stir Fry',
              'Soup',
              'Pizza',
              'Tacos',
              'Curry',
              'Ramen',
              'Sushi',
              'Burrito',
              'Seafood',
              'Vegan',
              'Mediterranean',
            ]
                .map(
                  (label) => GestureDetector(
                    onTap: () {
                      _dishController.text = label;
                      setState(() {});
                    },
                    child: Chip(
                      label: Text(label),
                      backgroundColor: Colors.white,
                      labelStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 0),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),

          // Segmented: Quick Presets / Custom Settings
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE5F9EF),
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _SegmentedButton(
                  label: 'Quick Presets',
                  isActive: !_useCustomSettings,
                  onTap: () {
                    setState(() {
                      _useCustomSettings = false;
                    });
                  },
                ),
                _SegmentedButton(
                  label: 'Custom Settings',
                  isActive: _useCustomSettings,
                  onTap: () {
                    setState(() {
                      _useCustomSettings = true;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (!_useCustomSettings) _buildPresetCards(context),
          if (_useCustomSettings) _buildCustomSettings(context),

          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetCards(BuildContext context) {
    Widget presetCard(
        {required IconData icon,
        required String title,
        required String subtitle,
        required String presetLabel}) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF16A34A)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _isLoadingText
                  ? null
                  : () => _generateRecipe(presetLabel: presetLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: _isLoadingText
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Generate'),
            )
          ],
        ),
      );
    }

    return Column(
      children: [
        presetCard(
          icon: Icons.bolt,
          title: 'Quick & Light',
          subtitle: '20 min  •  <400 cal',
          presetLabel: 'Quick & Light (<30 min, <400 cal)',
        ),
        presetCard(
          icon: Icons.family_restroom,
          title: 'Family Feast',
          subtitle: '60 min  •  serves 4–6',
          presetLabel: 'Family Feast',
        ),
        presetCard(
          icon: Icons.fitness_center,
          title: 'Healthy Power',
          subtitle: '<350 cal  •  high protein',
          presetLabel: 'Healthy Power',
        ),
        presetCard(
          icon: Icons.attach_money,
          title: 'Budget Friendly',
          subtitle: '< \$10 per serving',
          presetLabel: 'Budget Friendly',
        ),
      ],
    );
  }

  Widget _buildCustomSettings(BuildContext context) {
    Widget field(
        {required String label,
        required String hint,
        required TextEditingController controller,
        TextInputType keyboardType = TextInputType.number}) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            field(
              label: 'Max Cooking Time (minutes)',
              hint: 'e.g., 30',
              controller: _maxTimeController,
            ),
            const SizedBox(width: 10),
            field(
              label: 'Max Calories',
              hint: 'e.g., 500',
              controller: _maxCaloriesController,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            field(
              label: 'Servings',
              hint: 'e.g., 4',
              controller: _servingsController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(width: 10),
            field(
              label: 'Max Budget (\$)',
              hint: 'e.g., 15',
              controller: _budgetController,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            field(
              label: 'Max Prep Time (minutes)',
              hint: 'e.g., 15',
              controller: _maxPrepTimeController,
            ),
            const SizedBox(width: 10),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoadingText
                ? null
                : () => _generateRecipe(presetLabel: 'Custom Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: _isLoadingText
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Generate Custom Recipe'),
          ),
        ),
      ],
    );
  }

  // -------- Recipe Screen --------

  Widget _buildRecipeScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () {
            setState(() {
              _view = PlaideView.configure;
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF6B7280),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          icon: const Icon(Icons.arrow_back_ios_new, size: 14),
          label: const Text('Back to Search'),
        ),
        const SizedBox(height: 4),

        // Hero card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              // Image
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_imageBytes != null)
                        Image.memory(
                          _imageBytes!,
                          fit: BoxFit.cover,
                        )
                      else
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFE0F2FE), Color(0xFFD1FAE5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _isLoadingImage
                                  ? 'Generating image...'
                                  : 'Your dish photo will appear here.',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      if (_isLoadingImage)
                        const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Title + tags
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: const [
                        _SmallPill(label: 'pasta'),
                        _SmallPill(label: 'italian'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _recipeTitle.isEmpty
                                ? 'Your AI recipe'
                                : _recipeTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.favorite_border),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _TagChip(
                          icon: Icons.schedule,
                          label: _timeText.isEmpty
                              ? '24 min'
                              : _timeText,
                        ),
                        const SizedBox(width: 6),
                        _TagChip(
                          icon: Icons.local_fire_department,
                          label: _caloriesText.isEmpty
                              ? '540 cal'
                              : _caloriesText,
                        ),
                        const SizedBox(width: 6),
                        _TagChip(
                          icon: Icons.restaurant,
                          label: _servingsText.isEmpty
                              ? '4 servings'
                              : _servingsText,
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Easy',
                            style: TextStyle(
                              color: Color(0xFF15803D),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Tabs
        Row(
          children: [
            _TabLabel(
              label: 'Overview',
              isActive: _tab == DetailTab.overview,
              onTap: () {
                setState(() {
                  _tab = DetailTab.overview;
                });
              },
            ),
            const SizedBox(width: 16),
            _TabLabel(
              label: 'Ingredients',
              isActive: _tab == DetailTab.ingredients,
              onTap: () {
                setState(() {
                  _tab = DetailTab.ingredients;
                });
              },
            ),
            const SizedBox(width: 16),
            _TabLabel(
              label: 'Instructions',
              isActive: _tab == DetailTab.instructions,
              onTap: () {
                setState(() {
                  _tab = DetailTab.instructions;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),

        const SizedBox(height: 6),
        Expanded(
          child: _buildTabContent(),
        ),

        const SizedBox(height: 8),

        // Feedback buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _recipeTitle.isEmpty
                      ? null
                      : () => _openFeedbackDialog(liked: true),
                  icon: const Icon(Icons.thumb_up, size: 18),
                  label: const Text(
                    'I Like This',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _recipeTitle.isEmpty
                      ? null
                      : () => _openFeedbackDialog(liked: false),
                  icon: const Icon(Icons.thumb_down, size: 18),
                  label: const Text(
                    'Not for Me',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97373),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Bottom actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  // Try another recipe (same settings)
                  _generateRecipe(
                      presetLabel:
                          _useCustomSettings ? 'Custom Settings' : 'Quick & Light');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF22C55E),
                  side: const BorderSide(color: Color(0xFF22C55E)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text('Try Another Recipe'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _view = PlaideView.configure;
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4B5563),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text('New Search'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTabContent() {
    switch (_tab) {
      case DetailTab.overview:
        return _buildOverviewTab();
      case DetailTab.ingredients:
        return _buildIngredientsTab();
      case DetailTab.instructions:
        return _buildInstructionsTab();
    }
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_overviewText.isNotEmpty)
            Text(
              _overviewText,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFFDF5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recipe Highlights',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _HighlightRow(
                      icon: Icons.schedule,
                      label: _timeText.isEmpty ? '≈ 24 min total' : _timeText,
                    ),
                    _HighlightRow(
                      icon: Icons.local_fire_department,
                      label: _caloriesText.isEmpty
                          ? '≈ 560 calories'
                          : _caloriesText,
                    ),
                    _HighlightRow(
                      icon: Icons.restaurant,
                      label: _servingsText.isEmpty
                          ? 'Serves 4'
                          : _servingsText,
                    ),
                    const _HighlightRow(
                      icon: Icons.emoji_emotions_outlined,
                      label: 'Easy',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Estimated cost:  \$12–20',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsTab() {
    if (_ingredients.isEmpty) {
      return const Center(
        child: Text(
          'Ingredients will appear here.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
      );
    }

    return ListView.separated(
      itemCount: _ingredients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.circle,
                size: 6, color: Color(0xFF16A34A)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _ingredients[index],
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInstructionsTab() {
    if (_steps.isEmpty) {
      return const Center(
        child: Text(
          'Instructions will appear here.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
      );
    }

    return ListView.separated(
      itemCount: _steps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final stepNumber = index + 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$stepNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _steps[index],
                style: const TextStyle(fontSize: 13, height: 1.3),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------- Small UI components ----------

class _SegmentedButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SegmentedButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color:
                isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive
                  ? const Color(0xFF10B981)
                  : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  final String label;

  const _SmallPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TagChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF4B5563)),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabLabel(
      {required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive
                  ? const Color(0xFF111827)
                  : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 60,
            height: 2,
            color: isActive
                ? const Color(0xFF22C55E)
                : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HighlightRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF16A34A)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
