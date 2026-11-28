import 'package:flutter/material.dart';

import 'identity_vault.dart';
import 'pkcs12.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);

/// Asks for a password. [submit] does the work and returns an error text,
/// or null on success. Resolves to true when [submit] succeeded.
Future<bool?> showPasswordDialog(
  BuildContext context, {
  required String title,
  required String message,
  required Future<String?> Function(String password, bool remember) submit,
  bool showRemember = true,
  String action = 'Continue',
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(
      title: title,
      message: message,
      submit: submit,
      showRemember: showRemember,
      action: action,
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.message,
    required this.submit,
    required this.showRemember,
    required this.action,
  });

  final String title;
  final String message;
  final Future<String?> Function(String password, bool remember) submit;
  final bool showRemember;
  final String action;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _remember = false;
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // Let the spinner appear before the (CPU heavy) key derivation starts.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final error = await widget.submit(_controller.text, _remember);
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111923),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              obscureText: _hidden,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'Show' : 'Hide',
                  icon: Icon(
                    _hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
            ),
            if (widget.showRemember) ...[
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _remember,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _remember = value ?? false),
                title: const Text(
                  'Remember on this device',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'Kept in the system\'s secure storage.',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF8A94),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(color: _mint),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _mint,
            foregroundColor: const Color(0xFF071311),
          ),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Makes sure the user's certificate is open, asking for the password if
/// needed. Returns null when there is no certificate or the user cancelled.
Future<SmimeIdentity?> ensureIdentityUnlocked(BuildContext context) async {
  final vault = IdentityVault.instance;
  final messenger = ScaffoldMessenger.of(context);

  await vault.tryAutoUnlock();
  if (vault.unlocked != null) {
    return vault.unlocked;
  }

  final info = await vault.info();
  if (info == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Import your certificate on the Certificates tab first.',
        ),
      ),
    );
    return null;
  }

  if (!context.mounted) {
    return null;
  }

  final ok = await showPasswordDialog(
    context,
    title: 'Unlock your certificate',
    message: 'Enter the password for ${info.name}.',
    action: 'Unlock',
    submit: (password, remember) async {
      try {
        await vault.unlock(password, remember: remember);
        return null;
      } on Pkcs12Exception catch (error) {
        return error.message;
      } catch (error) {
        return '$error';
      }
    },
  );

  return ok == true ? vault.unlocked : null;
}