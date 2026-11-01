import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class CoffeeLink extends StatelessWidget {
  const CoffeeLink({super.key});

  static final Uri url = Uri.parse('https://buymeacoffee.com/anthonydouv');

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } on PlatformException {
      // A browser may be missing or blocked on this device.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open a browser. $url'),
        action: SnackBarAction(
          label: 'Copy link',
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: url.toString())),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Buy me a coffee (opens browser)',
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    onPressed: () => _open(context),
    icon: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        'assets/branding/buy_me_a_coffee.png',
        width: 32,
        height: 32,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    ),
  );
}
