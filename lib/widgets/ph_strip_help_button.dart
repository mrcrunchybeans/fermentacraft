// lib/widgets/ph_strip_help_button.dart
import 'package:flutter/material.dart';

class PHStripHelpButton extends StatelessWidget {
  const PHStripHelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'How this tool works',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: ListView(
              children: [
                const SizedBox(height: 8),
                Text('How to read a pH strip',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  '1) Put the test strip and the bottle/key in the SAME photo.\n'
                  '2) Hold the strip beside the key squares so the camera sees both.\n'
                  '3) Take a well-lit, in-focus photo (avoid shadows or color casts).\n'
                  '4) Align the colored pad on your strip with the nearest square on the key.\n'
                  '5) If you use a custom strip/key, select it from “Custom strips.”',
                ),
                const SizedBox(height: 16),
                // Tip chips
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TipChip('Good light (daylight if possible)'),
                    _TipChip('Avoid tinted bulbs / colored countertops'),
                    _TipChip('Keep strip/key parallel to the camera'),
                  ],
                ),
                const SizedBox(height: 16),
                // Reference image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.asset(
                      'assets/phstrip_help.png',
                      fit: BoxFit.contain,
                      semanticLabel:
                          'Example: strip and bottle key in the same photo',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Reference: Example showing the strip and the key in one shot.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  final String text;
  const _TipChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      avatar: const Icon(Icons.lightbulb, size: 18),
    );
  }
}
