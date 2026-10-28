import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'privacy_vault.dart';

/// Returns true once the vault is open: already unlocked, biometric OK, or passcode OK.
/// First use asks the person to create a passcode.
Future<bool> ensureUnlocked(BuildContext context) async {
  final vault = context.read<PrivacyVault>();
  if (vault.unlocked) return true;

  if (!await vault.hasPasscode()) {
    if (!context.mounted) return false;
    return _createPasscode(context, vault);
  }
  if (await vault.tryBiometric()) return true;
  if (!context.mounted) return false;
  return _enterPasscode(context, vault);
}

Future<bool> _createPasscode(BuildContext context, PrivacyVault vault) async {
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Create vault passcode'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Protects hidden and locked people. If you forget it, they cannot be recovered.'),
          TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'Passcode (6+ characters)')),
          TextField(controller: b, obscureText: true, decoration: InputDecoration(labelText: 'Confirm', errorText: err)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (a.text.length < 6) {
                setState(() => err = 'Use at least 6 characters');
              } else if (a.text != b.text) {
                setState(() => err = 'Passcodes do not match');
              } else {
                await vault.setPasscode(a.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  a.dispose();
  b.dispose();
  return ok ?? false;
}

Future<bool> _enterPasscode(BuildContext context, PrivacyVault vault) async {
  final c = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Enter passcode'),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(errorText: err),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (await vault.verifyPasscode(c.text)) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              } else {
                setState(() => err = 'Wrong passcode');
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    ),
  );
  c.dispose();
  return ok ?? false;
}
