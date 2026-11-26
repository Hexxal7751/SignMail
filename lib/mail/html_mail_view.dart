import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/mail_service.dart';
import 'html_sanitizer.dart';

const Color _mint = Color(0xFF69E0D0);
const Color _muted = Color(0xFF8F9EAE);

/// Shows an HTML mail safely: no scripts, pictures from the internet only on
/// request, and links are confirmed before they open.
class HtmlMailView extends StatefulWidget {
  const HtmlMailView({
    super.key,
    required this.html,
    required this.inlineImages,
  });

  final String html;
  final Map<String, InlineImage> inlineImages;

  @override
  State<HtmlMailView> createState() => _HtmlMailViewState();
}

class _HtmlMailViewState extends State<HtmlMailView> {
  bool _allowImages = false;
  late Map<String, String> _dataUris = _buildUris();
  SanitizedHtml? _result;
  bool? _resultAllow;

  Map<String, String> _buildUris() {
    return <String, String>{
      for (final entry in widget.inlineImages.entries)
        entry.key: entry.value.dataUri,
    };
  }

  @override
  void didUpdateWidget(HtmlMailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inlineImages != widget.inlineImages) {
      _dataUris = _buildUris();
      _result = null;
    }
    if (oldWidget.html != widget.html) {
      _result = null;
    }
  }

  SanitizedHtml _sanitized() {
    if (_result == null || _resultAllow != _allowImages) {
      _result = sanitizeMailHtml(
        widget.html,
        inlineDataUris: _dataUris,
        allowRemoteImages: _allowImages,
      );
      _resultAllow = _allowImages;
    }
    return _result!;
  }

  bool _handleTap(String url) {
    _confirmOpen(url);
    return true;
  }

  Future<void> _confirmOpen(String url) async {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';

    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open this link?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (host.isNotEmpty)
              Text(
                host,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            const SizedBox(height: 8),
            SelectableText(
              url,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            const Text(
              'Check that the address is what you expect before continuing.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open'),
          ),
        ],
      ),
    );

    if (open != true || uri == null) {
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _sanitized();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.blockedRemoteImages > 0 && !_allowImages)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: const Color(0xFF19252F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF263342)),
            ),
            child: Row(
              children: [
                const Icon(Icons.image_not_supported_outlined,
                    size: 18, color: _muted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Pictures from the internet are blocked to protect your '
                    'privacy.',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _allowImages = true),
                  child: const Text(
                    'Load pictures',
                    style: TextStyle(color: _mint),
                  ),
                ),
              ],
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: HtmlWidget(
            result.html,
            textStyle: const TextStyle(
              color: Color(0xFF1B1F23),
              fontSize: 15,
              height: 1.4,
            ),
            onTapUrl: _handleTap,
          ),
        ),
      ],
    );
  }
}