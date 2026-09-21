import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/demo_config.dart';
import 'common.dart';

/// Demo build only: the link that rings this phone, and how to use it.
class DemoLineCard extends StatelessWidget {
  const DemoLineCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DemoConfig.enabled) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your demo line', style: text.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Open this link on a laptop and press Call. It rings this phone, and only this phone. You play Kabeer.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  DemoConfig.callLink,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Copy link',
                icon: const Icon(Icons.copy_outlined, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: DemoConfig.callLink));
                  if (context.mounted) showMessage(context, 'Link copied');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
