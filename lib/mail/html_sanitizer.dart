import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Cleaned-up HTML for display, plus how many pictures were held back.
class SanitizedHtml {
  const SanitizedHtml(this.html, this.blockedRemoteImages);

  final String html;
  final int blockedRemoteImages;
}

const Set<String> _removedTags = <String>{
  'script',
  'style',
  'iframe',
  'frame',
  'frameset',
  'object',
  'embed',
  'applet',
  'link',
  'meta',
  'base',
  'form',
  'input',
  'button',
  'select',
  'textarea',
  'option',
  'audio',
  'video',
  'source',
  'track',
  'canvas',
  'svg',
  'math',
  'noscript',
  'template',
  'title',
  'head',
};

const Set<String> _safeLinkSchemes = <String>{'http', 'https', 'mailto', 'tel'};

/// Makes an HTML mail safe to show.
///
/// * scripts, frames, forms and similar elements are removed,
/// * event handlers (onclick, ...) and risky attributes are removed,
/// * links keep only http(s), mailto and tel addresses,
/// * `cid:` pictures are replaced with the attached data ([inlineDataUris]),
/// * pictures from the internet are removed unless [allowRemoteImages].
///
/// Nothing in the result can run code or contact a server by itself.
SanitizedHtml sanitizeMailHtml(
  String source, {
  required Map<String, String> inlineDataUris,
  required bool allowRemoteImages,
}) {
  final document = html_parser.parse(source);
  final body = document.body;
  if (body == null) {
    return const SanitizedHtml('', 0);
  }

  var blocked = 0;

  void clean(Element element) {
    // Work on a copy: children are removed while walking.
    for (final child in List<Element>.of(element.children)) {
      final tag = child.localName ?? '';

      if (_removedTags.contains(tag)) {
        child.remove();
        continue;
      }

      _cleanAttributes(child, allowRemoteImages);

      if (tag == 'img') {
        final result = _handleImage(child, inlineDataUris, allowRemoteImages);
        if (result == _ImageResult.blocked) {
          blocked++;
        }
        if (result != _ImageResult.kept) {
          continue;
        }
      }

      clean(child);
    }
  }

  clean(body);
  return SanitizedHtml(body.innerHtml, blocked);
}

enum _ImageResult { kept, blocked, removed }

void _cleanAttributes(Element element, bool allowRemoteImages) {
  final names = element.attributes.keys.map((k) => k.toString()).toList();

  for (final name in names) {
    final lower = name.toLowerCase();

    if (lower.startsWith('on') ||
        lower == 'srcdoc' ||
        lower == 'formaction' ||
        lower == 'ping' ||
        lower == 'srcset' ||
        lower == 'target' ||
        lower == 'poster' ||
        lower == 'dynsrc' ||
        lower == 'lowsrc') {
      element.attributes.remove(name);
      continue;
    }

    if (lower == 'background' && !allowRemoteImages) {
      element.attributes.remove(name);
      continue;
    }

    if (lower == 'href') {
      final value = element.attributes[name]!.trim();
      final uri = Uri.tryParse(value);
      final scheme = uri?.scheme.toLowerCase() ?? '';
      if (!_safeLinkSchemes.contains(scheme)) {
        element.attributes.remove(name);
      }
      continue;
    }

    if (lower == 'style') {
      final cleaned = _cleanStyle(element.attributes[name]!, allowRemoteImages);
      if (cleaned.isEmpty) {
        element.attributes.remove(name);
      } else {
        element.attributes[name] = cleaned;
      }
    }
  }
}

String _cleanStyle(String style, bool allowRemoteImages) {
  final kept = <String>[];
  for (final declaration in style.split(';')) {
    final lower = declaration.toLowerCase().replaceAll(RegExp(r'\s'), '');
    if (lower.isEmpty) {
      continue;
    }
    if (lower.contains('expression(') ||
        lower.contains('javascript:') ||
        lower.contains('behavior:') ||
        lower.contains('-moz-binding') ||
        lower.startsWith('position:') ||
        lower.startsWith('z-index:')) {
      continue;
    }
    if (lower.contains('url(') && !allowRemoteImages) {
      continue;
    }
    kept.add(declaration.trim());
  }
  return kept.join('; ');
}

_ImageResult _handleImage(
  Element image,
  Map<String, String> inlineDataUris,
  bool allowRemoteImages,
) {
  final src = (image.attributes['src'] ?? '').trim();
  final lower = src.toLowerCase();

  if (lower.startsWith('cid:')) {
    final key = src.substring(4).replaceAll(RegExp(r'^<|>$'), '').toLowerCase();
    final data = inlineDataUris[key];
    if (data != null) {
      image.attributes['src'] = data;
      return _ImageResult.kept;
    }
    image.remove();
    return _ImageResult.removed;
  }

  if (lower.startsWith('data:image/') && !lower.startsWith('data:image/svg')) {
    return _ImageResult.kept;
  }

  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    if (allowRemoteImages) {
      return _ImageResult.kept;
    }

    final tiny = _isTiny(image.attributes['width']) ||
        _isTiny(image.attributes['height']);
    final alt = (image.attributes['alt'] ?? '').trim();

    if (tiny) {
      image.remove(); // tracking pixels are dropped without a trace
      return _ImageResult.removed;
    }

    final placeholder = Element.tag('span')
      ..attributes['style'] = 'color:#8a8f98;font-size:12px'
      ..text = alt.isEmpty ? '[picture blocked]' : '[$alt]';
    image.replaceWith(placeholder);
    return _ImageResult.blocked;
  }

  image.remove();
  return _ImageResult.removed;
}

bool _isTiny(String? value) {
  if (value == null) {
    return false;
  }
  final number = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
  return number != null && number <= 2;
}