import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../smime/chain.dart';
import '../smime/contact_certs.dart';
import '../smime/identity_dialogs.dart';
import '../smime/identity_vault.dart';
import '../smime/pkcs12.dart';
import '../smime/trust_service.dart';
import '../smime/x509.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);
const Color _card = Color(0xFF111923);
const Color _border = Color(0xFF263342);

String _day(DateTime value) {
  final v = value.toLocal();
  return '${v.year}-${v.month.toString().padLeft(2, '0')}-'
      '${v.day.toString().padLeft(2, '0')}';
}

/// The Certificates tab: your own S/MIME certificate and other people's.
class CertificatesView extends ConsumerWidget {
  const CertificatesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            const Text(
              'Certificates',
              style: TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your S/MIME identity for signing and decrypting, and the '
              'certificates of people you can encrypt for.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 22),
            const _IdentityCard(),
            const SizedBox(height: 26),
            const _ContactsSection(),
            const SizedBox(height: 26),
            const _AuthoritiesNote(),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends ConsumerStatefulWidget {
  const _IdentityCard();

  @override
  ConsumerState<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends ConsumerState<_IdentityCard> {
  bool _busy = false;

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The file could not be read.')),
      );
      return;
    }
    if (!mounted) {
      return;
    }

    IdentityInfo? imported;
    final ok = await showPasswordDialog(
      context,
      title: 'Certificate password',
      message: 'Enter the password of ${file.name}. The file is kept '
          'protected on this device.',
      action: 'Import',
      submit: (password, remember) async {
        try {
          imported = await IdentityVault.instance.importP12(
            bytes,
            password,
            remember: remember,
          );
          return null;
        } on Pkcs12Exception catch (error) {
          return error.message;
        } catch (error) {
          return '$error';
        }
      },
    );

    if (ok != true || !mounted) {
      return;
    }

    ref.invalidate(identityInfoProvider);
    setState(() {});

    final info = imported;
    final account = await ref.read(authServiceProvider).savedEmail();
    if (info != null && account != null) {
      final matches = info.emails.contains(account.toLowerCase());
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            matches
                ? 'Certificate imported.'
                : 'Imported, but this certificate is not issued for '
                    '$account. Others may see a warning on your messages.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleLock() async {
    final vault = IdentityVault.instance;
    if (vault.isUnlocked) {
      vault.lock();
    } else {
      await ensureIdentityUnlocked(context);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _remove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Remove your certificate?'),
        content: const Text(
          'It is deleted from this device. Keep your original .p12 file: '
          'without it you cannot read old encrypted messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    await IdentityVault.instance.remove();
    ref.invalidate(identityInfoProvider);
    if (mounted) {
      setState(() {});
    }
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _muted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: mono ? 11 : 13.5,
              fontFamily: mono ? 'monospace' : null,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(identityInfoProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: _mint)),
      ),
      error: (error, stack) => Text('$error'),
      data: (info) {
        if (info == null) {
          return Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    size: 38, color: _mint),
                const SizedBox(height: 14),
                const Text(
                  'No certificate yet',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Import a .p12 or .pfx file (an S/MIME certificate for your '
                  'address) to sign your messages and read encrypted ones.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Import certificate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _mint,
                    foregroundColor: const Color(0xFF071311),
                  ),
                ),
              ],
            ),
          );
        }

        final unlocked = IdentityVault.instance.isUnlocked;
        final expired = info.isExpired;

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    expired
                        ? Icons.warning_amber_rounded
                        : Icons.verified_user_rounded,
                    color: expired ? const Color(0xFFE5646E) : _mint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      info.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip(
                    expired
                        ? 'Expired ${_day(info.notAfter)}'
                        : 'Valid until ${_day(info.notAfter)}',
                    expired ? const Color(0xFFE5646E) : _mint,
                  ),
                  _Chip(
                    unlocked ? 'Unlocked' : 'Locked',
                    unlocked ? _mint : _muted,
                  ),
                  if (info.remembered) const _Chip('Password remembered', _muted),
                ],
              ),
              if (info.emails.isNotEmpty)
                _row('E-mail address', info.emails.join(', ')),
              _row('Issued by', info.issuer),
              _row('Fingerprint (SHA-256)', info.fingerprint, mono: true),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _toggleLock,
                    icon: Icon(
                      unlocked ? Icons.lock_outline : Icons.lock_open_outlined,
                    ),
                    label: Text(unlocked ? 'Lock' : 'Unlock'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Replace'),
                  ),
                  TextButton(
                    onPressed: _remove,
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Color(0xFFFF8A94)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ContactsSection extends ConsumerWidget {
  const _ContactsSection();

  Future<void> _addFile(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The file could not be read.')),
      );
      return;
    }

    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final certs = text.contains('BEGIN CERTIFICATE')
          ? X509Certificate.fromPem(text)
          : <X509Certificate>[X509Certificate.fromDer(bytes)];

      var added = 0;
      for (final cert in certs) {
        if (cert.emails.isEmpty) {
          continue;
        }
        await ContactCerts.instance.save(cert);
        added++;
      }

      ref.invalidate(contactCertsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            added == 0
                ? 'No certificate with an e-mail address was found.'
                : 'Added $added certificate(s).',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('That is not a certificate file: $error')),
      );
    }
  }

  Future<void> _showSheet(
    BuildContext context,
    WidgetRef ref,
    String email,
    X509Certificate cert,
  ) async {
    final trust = await TrustService.instance.load();
    if (!context.mounted) {
      return;
    }
    final chain =
        buildChain(cert, const <X509Certificate>[], trust, DateTime.now());
    final pinned = trust.pinnedFingerprints.contains(cert.fingerprint);

    final status = pinned
        ? 'You trust this certificate.'
        : (chain.trusted
            ? 'Issued by a known authority.'
            : (chain.problem ?? 'Not verified.'));

    Widget line(String label, String value, {bool mono = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: _muted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              value,
              style: TextStyle(
                fontSize: mono ? 11 : 13.5,
                fontFamily: mono ? 'monospace' : null,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101720),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cert.commonName,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              line('E-mail address', email),
              line('Issued by', cert.issuerName),
              line('Valid', '${_day(cert.notBefore)}  to  ${_day(cert.notAfter)}'),
              line('Status', status),
              line('Fingerprint (SHA-256)', cert.fingerprintDisplay, mono: true),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (pinned)
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await TrustService.instance.unpin(cert.fingerprint);
                        ref.invalidate(contactCertsProvider);
                      },
                      child: const Text('Stop trusting'),
                    )
                  else if (!chain.trusted)
                    FilledButton(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await TrustService.instance.pin(cert.fingerprint);
                        ref.invalidate(contactCertsProvider);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _mint,
                        foregroundColor: const Color(0xFF071311),
                      ),
                      child: const Text('Trust this certificate'),
                    ),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await ContactCerts.instance.remove(email);
                      ref.invalidate(contactCertsProvider);
                    },
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Color(0xFFFF8A94)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactCertsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'PEOPLE\'S CERTIFICATES',
                style: TextStyle(
                  color: _muted,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _addFile(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add file'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        contacts.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: _mint)),
          ),
          error: (error, stack) => Text('$error'),
          data: (map) {
            if (map.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: const Text(
                  'None yet. When you open a signed message from someone, '
                  'their certificate is saved here, and you can then '
                  'encrypt messages to them.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
                ),
              );
            }

            final entries = map.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));

            return Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: _border),
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text(
                        entries[i].value.commonName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${entries[i].key} · '
                        '${entries[i].value.isValidAt(DateTime.now()) ? 'valid until ${_day(entries[i].value.notAfter)}' : 'expired'}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showSheet(
                        context,
                        ref,
                        entries[i].key,
                        entries[i].value,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AuthoritiesNote extends StatelessWidget {
  const _AuthoritiesNote();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TrustStore>(
      future: TrustService.instance.load(),
      builder: (context, snapshot) {
        final store = snapshot.data;
        final text = store == null
            ? 'Loading the list of known certificate authorities…'
            : '${store.roots.length} public certificate authorities and '
                '${store.pinnedFingerprints.length} certificate(s) you trust '
                'are used to check signatures. Revocation is not checked.';
        return Text(
          text,
          style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.45),
        );
      },
    );
  }
}