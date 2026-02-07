import 'package:flutter/material.dart';

class GuideDialog extends StatelessWidget {
  final String title;
  final List<Map<String, String>> steps;

  const GuideDialog({super.key, required this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400, // Reasonable width for desktop dialog
        child: SingleChildScrollView(
          child: Column(
             mainAxisSize: MainAxisSize.min,
             children: steps.asMap().entries.map((entry) {
               final index = entry.key;
               final step = entry.value;
               return ListTile(
                  leading: CircleAvatar(child: Text("${index + 1}")),
                  title: Text(step['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(step['description'] ?? ''),
               );
             }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Close"))
      ],
    );
  }
}
