// lib/main.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// IMPORTANT: Replace this with your actual API key.
const String geminiApiKey = "AXXXX";

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
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
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
  PlaideView _view = PlaideView.configure;
  DetailTab _tab = DetailTab.overview;

  // Controllers for all input fields
  final TextEditingController _dishController = TextEditingController();
  final TextEditingController _maxTimeController = TextEditingController();
  final TextEditingController _maxCaloriesController = TextEditingController();
  final TextEditingController _servingsController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _maxPrepTimeController = TextEditingController();

  bool _useCustomSettings = false;
  bool _isLoadingText = false;
  bool _isLoadingImage = false;
  String? _errorMessage;

  // Recipe data fields
  String _recipeTitle = '';
  String _overviewText = '';
  List<String> _ingredients = [];
  List<String> _steps = [];
  String _timeText = '';
  String _caloriesText = '';
  String _servingsText = '';
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _dishController.addListener(() => setState(() {}));
  }

  // Utility to limit generated text length
  String _limitTo200Words(String text) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= 200) return text;
    return words.take(200).join(' ') + ' …';
  }

  // Resets all dynamic recipe data
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

  // Parse Gemini text using clear section labels
  void _parseRecipeText(String raw) {
    final text = _limitTo200Words(raw);

    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String _extractValue(String label) {
      final i = lines.indexWhere(
          (l) => l.toUpperCase().startsWith('$label:'.toUpperCase()));
      if (i == -1) return '';
      final parts = lines[i].split(':');
      if (parts.length <= 1) return '';
      return parts.sublist(1).join(':').trim();
    }

    _recipeTitle = _extractValue("TITLE");
    _timeText = _extractValue("TIME");
    _servingsText = _extractValue("SERVINGS");
    _caloriesText = _extractValue("CALORIES");

    final overviewIndex =
        lines.indexWhere((l) => l.toUpperCase().startsWith("OVERVIEW:"));
    final ingredientsIndex =
        lines.indexWhere((l) => l.toUpperCase().startsWith("INGREDIENTS:"));
    final instructionsIndex =
        lines.indexWhere((l) => l.toUpperCase().startsWith("INSTRUCTIONS:"));

    // OVERVIEW
    _overviewText = '';
    if (overviewIndex != -1) {
      final end = (ingredientsIndex != -1
              ? ingredientsIndex
              : (instructionsIndex != -1 ? instructionsIndex : lines.length));
      final overLines = lines.sublist(overviewIndex + 1, end);
      _overviewText = overLines.join('\n');
    }

    // INGREDIENTS
    _ingredients = [];
    if (ingredientsIndex != -1) {
      final end =
          instructionsIndex != -1 ? instructionsIndex : lines.length;
      final ingLines = lines.sublist(ingredientsIndex + 1, end);
      _ingredients = ingLines
          .map((l) =>
              l.replaceFirst(RegExp(r'^[-•\d\.\)\s]+'), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    // INSTRUCTIONS
    _steps = [];
    if (instructionsIndex != -1) {
      final stepLines = lines.sublist(instructionsIndex + 1);
      _steps = stepLines
          .map(
              (l) => l.replaceFirst(RegExp(r'^\d+[\).\s]+'), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    // Fallback title if Gemini forgets it
    if (_recipeTitle.isEmpty && _dishController.text.isNotEmpty) {
      _recipeTitle = _dishController.text;
    }
  }

  // Generate recipe text using Gemini Flash
  Future<void> _generateRecipe({required String presetLabel}) async {
    final dish = _dishController.text.trim();

    if (dish.isEmpty) {
      setState(() => _errorMessage = "Please enter a dish.");
      return;
    }

    _resetRecipe();

    setState(() {
      _isLoadingText = true;
      _isLoadingImage = true;
      _errorMessage = null;
    });

    const model = "gemini-2.5-flash";

    final uri = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiApiKey");

    // Prompt designed to keep <= 200 words and match tabs
    final prompt = """
You are Plaide, an AI recipe assistant.

Create a recipe for: "$dish".

Preset selected: $presetLabel
- If preset is QuickAndLight, keep time short and calories lower.
- If FamilyFeast, serve 4–6.
- If HealthyPower, emphasise high protein.
- If BudgetFriendly, keep ingredients affordable.
- If DishInput or CustomSettings, just respect the dish name and be balanced.

HARD CONSTRAINT:
- TOTAL response MUST be 200 words or less.

OUTPUT FORMAT – use these exact labels and line breaks:

TITLE: Chicken Rice Bowl
TIME: 25 min
SERVINGS: 2
CALORIES: approx 480

OVERVIEW:
2–3 sentences describing the dish.

INGREDIENTS:
- item
- item
- item

INSTRUCTIONS:
1. step
2. step
3. step
""";

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ]
    });

    try {
      final resp = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      final data = jsonDecode(resp.body);
      final text =
          data["candidates"][0]["content"]["parts"][0]["text"] ?? "";

      _parseRecipeText(text);

      setState(() => _view = PlaideView.recipe);

      // Trigger image generation asynchronously after text is received
      await _generateRecipeImage("$dish, professional food photography");
    } catch (e) {
      print("Text Generation Error: $e");
      setState(() => _errorMessage = "Could not generate recipe text.");
    } finally {
      setState(() => _isLoadingText = false);
    }
  }

  // Image generation using Gemini Flash Image
  Future<void> _generateRecipeImage(String description) async {
    setState(() => _isLoadingImage = true);

    const model = "gemini-2.5-flash-image";

    final uri = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent");

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {
              "text":
                  "Generate a high-quality, realistic food photo of: $description. Use vibrant colors and clean lighting."
            }
          ]
        }
      ]
    });

    try {
      final resp = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": geminiApiKey
        },
        body: body,
      );

      final parts =
          jsonDecode(resp.body)["candidates"][0]["content"]["parts"];

      for (final p in parts) {
        final data = p["inlineData"] ?? p["inline_data"];
        if (data != null && data["data"] is String) {
          _imageBytes = base64Decode(data["data"]);
        }
      }
    } catch (e) {
      print("Image Generation Error: $e");
    } finally {
      setState(() => _isLoadingImage = false);
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildMainCard(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5FFFB),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        children: [
          _buildTopBar(),
          const SizedBox(height: 12),
          Expanded(
            child: _view == PlaideView.configure
                ? _buildConfigureScreen()
                : _buildRecipeScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: const [
            Icon(Icons.restaurant_menu, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text(
              "plaide",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF16A34A),
                fontSize: 18,
              ),
            )
          ],
        ),
        Row(
          children: const [
            Icon(Icons.search, size: 20, color: Color(0xFF4B5563)),
            SizedBox(width: 8),
            Icon(Icons.notifications_none, size: 20, color: Color(0xFF4B5563)),
            SizedBox(width: 8),
            Icon(Icons.favorite_border, size: 20, color: Color(0xFF4B5563)),
          ],
        )
      ],
    );
  }

  // CONFIGURE SCREEN (matches wireframe)
  Widget _buildConfigureScreen() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.arrow_back_ios_new, size: 14),
            label: const Text("Back to Search"),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Configure your recipe",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dishController,
            decoration: InputDecoration(
              labelText: "e.g: Pasta with tomato sauce",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              "Pasta",
              "Chicken",
              "Salad",
              "Rice Bowl",
              "Stir Fry",
              "Soup",
              "Pizza",
              "Tacos",
              "Curry",
              "Ramen",
              "Sushi",
              "Burrito",
              "Seafood",
              "Vegan",
              "Mediterranean",
            ].map((label) {
              final isSelected = _dishController.text == label;
              return GestureDetector(
                onTap: () {
                  _dishController.text = isSelected ? "" : label;
                },
                child: Chip(
                  label: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF4B5563),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  backgroundColor:
                      isSelected ? const Color(0xFF22C55E) : Colors.white,
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFE5E7EB),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _dishController.text.trim().isNotEmpty && !_isLoadingText
                ? () => _generateRecipe(presetLabel: "DishInput")
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              disabledBackgroundColor: const Color(0xFFB9E5C5),
            ),
            child: Text(
              _isLoadingText ? "Generating..." : "Generate Recipe",
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          _buildPresetSelector(theme),
          const SizedBox(height: 16),
          _useCustomSettings ? _buildCustomSettings() : _buildQuickPresets(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }

  // Quick Presets UI
  Widget _buildQuickPresets() {
    final presets = [
      {
        'icon': Icons.flash_on,
        'title': 'Quick & Light',
        'subtitle': '20 min • <400 cal',
        'label': 'QuickAndLight'
      },
      {
        'icon': Icons.group,
        'title': 'Family Feast',
        'subtitle': '60 min • serves 4-6',
        'label': 'FamilyFeast'
      },
      {
        'icon': Icons.accessibility_new,
        'title': 'Healthy Power',
        'subtitle': '<350 cal • high protein',
        'label': 'HealthyPower'
      },
      {
        'icon': Icons.attach_money,
        'title': 'Budget Friendly',
        'subtitle': '< \$10 per serving',
        'label': 'BudgetFriendly'
      },
    ];

    return Column(
      children: presets.map((preset) {
        final enabled =
            _dishController.text.trim().isNotEmpty && !_isLoadingText;
        return _PresetTile(
          icon: preset['icon'] as IconData,
          title: preset['title'] as String,
          subtitle: preset['subtitle'] as String,
          onGenerate: enabled
              ? () => _generateRecipe(
                  presetLabel: preset['label'] as String,
                )
              : null,
          isEnabled: enabled,
        );
      }).toList(),
    );
  }

  // Custom Settings UI
  Widget _buildCustomSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCustomInputField(
            _maxPrepTimeController, "Max Prep Time (min)", "e.g. 15"),
        const SizedBox(height: 12),
        _buildCustomInputField(
            _maxCaloriesController, "Max Calories", "e.g. 500"),
        const SizedBox(height: 12),
        _buildCustomInputField(_servingsController, "Servings", "e.g. 4"),
        const SizedBox(height: 12),
        _buildCustomInputField(_budgetController, "Max Budget (\$)", "e.g. 15"),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _dishController.text.trim().isNotEmpty && !_isLoadingText
              ? () => _generateRecipe(presetLabel: "CustomSettings")
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            disabledBackgroundColor: const Color(0xFFB9E5C5),
          ),
          child: const Text("Generate Custom Recipe"),
        )
      ],
    );
  }

  Widget _buildCustomInputField(
      TextEditingController controller, String label, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF4B5563)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildPresetSelector(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE5F9EF),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _SegmentButton(
            label: "Quick Presets",
            isActive: !_useCustomSettings,
            onTap: () => setState(() => _useCustomSettings = false),
          ),
          _SegmentButton(
            label: "Custom Settings",
            isActive: _useCustomSettings,
            onTap: () => setState(() => _useCustomSettings = true),
          ),
        ],
      ),
    );
  }

  // RECIPE RESULT SCREEN (matches wireframe)
  Widget _buildRecipeScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _view = PlaideView.configure),
          icon: const Icon(Icons.arrow_back_ios_new, size: 14),
          label: const Text("Back to Search"),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF6B7280),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _imageBytes != null
                      ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                      : Center(
                          child: Text(
                            _isLoadingImage
                                ? "Generating image..."
                                : "Your food photo will appear here",
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        if (_dishController.text.isNotEmpty)
                          _TagPill(_dishController.text),
                        const _TagPill("recipe"),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _recipeTitle.isEmpty
                                ? "Your AI Recipe"
                                : _recipeTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.favorite_border),
                          onPressed: () {},
                        )
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _InfoTag(Icons.schedule,
                            _timeText.isEmpty ? "Time" : _timeText),
                        const SizedBox(width: 6),
                        _InfoTag(
                          Icons.local_fire_department,
                          _caloriesText.isEmpty
                              ? "Calories"
                              : _caloriesText,
                        ),
                        const SizedBox(width: 6),
                        _InfoTag(Icons.restaurant,
                            _servingsText.isEmpty ? "Servings" : _servingsText),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Tab("Overview", _tab == DetailTab.overview,
                () => setState(() => _tab = DetailTab.overview)),
            const SizedBox(width: 16),
            _Tab("Ingredients", _tab == DetailTab.ingredients,
                () => setState(() => _tab = DetailTab.ingredients)),
            const SizedBox(width: 16),
            _Tab("Instructions", _tab == DetailTab.instructions,
                () => setState(() => _tab = DetailTab.instructions)),
          ],
        ),
        const Divider(),
        Expanded(child: _buildTabContent()),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _recipeTitle.isEmpty
                    ? null
                    : () => _openFeedbackDialog(liked: true),
                icon: const Icon(Icons.thumb_up),
                label: const Text("Support"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _recipeTitle.isEmpty
                    ? null
                    : () => _openFeedbackDialog(liked: false),
                icon: const Icon(Icons.thumb_down),
                label: const Text("Don’t Support"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97373),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () =>
                    _generateRecipe(presetLabel: "TryAnother"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF22C55E),
                  side: const BorderSide(color: Color(0xFF22C55E)),
                ),
                child: const Text("Try Another Recipe"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _view = PlaideView.configure),
                child: const Text("New Search"),
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
        return SingleChildScrollView(
          child: Text(
            _overviewText.isEmpty && !_isLoadingText
                ? "Overview text will appear here."
                : _overviewText,
            style: const TextStyle(fontSize: 13),
          ),
        );
      case DetailTab.ingredients:
        if (_ingredients.isEmpty) {
          return const Center(
            child: Text(
              "Ingredients will appear here.",
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          itemCount: _ingredients.length,
          itemBuilder: (_, i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.circle,
                      size: 6, color: Color(0xFF22C55E)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_ingredients[i])),
                ],
              ),
            );
          },
        );
      case DetailTab.instructions:
        if (_steps.isEmpty) {
          return const Center(
            child: Text(
              "Instructions will appear here.",
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          itemCount: _steps.length,
          itemBuilder: (_, i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      "${i + 1}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_steps[i])),
                ],
              ),
            );
          },
        );
    }
  }

  // Custom modal for feedback (Support / Don’t Support)
  void _openFeedbackDialog({required bool liked}) {
    if (_recipeTitle.isEmpty) return;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(liked ? Icons.thumb_up : Icons.thumb_down,
                    color: liked ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    liked ? "Tell us what you liked!" : "Help us improve",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: liked
                    ? "What worked well for you?"
                    : "What didn’t work for you?",
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                ),
                child: const Text("Submit"),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// SMALL UI COMPONENTS
// ----------------------------------------------------------

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SegmentButton(
      {required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color:
                  isActive ? const Color(0xFF10B981) : const Color(0xFF6B7280),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onGenerate;
  final bool isEnabled;

  const _PresetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onGenerate,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isEnabled ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onGenerate,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(0, 0),
              disabledBackgroundColor: const Color(0xFFB9E5C5),
            ),
            child: const Text("Generate"),
          ),
        ],
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  final String label;
  const _TagPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

class _InfoTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoTag(this.icon, this.label);

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
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab(this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color:
                  active ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 60,
            height: 2,
            color: active ? const Color(0xFF22C55E) : Colors.transparent,
          )
        ],
      ),
    );
  }
}
