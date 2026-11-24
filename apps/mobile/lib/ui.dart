/// The app's widget library: Material, with a `Text` that shows its words in the patient's language.
library;

import 'package:material_ui/material_ui.dart' as m;

import 'l10n/l10n.dart';

export 'package:material_ui/material_ui.dart' hide Text;

export 'l10n/l10n.dart'
    show appLanguage, appLanguages, loadAppLanguage, setAppLanguage, tr, trf;

/// Material's Text, translating its string on the way to the screen. In English it is exactly Material's Text.
class Text extends m.Text {
  const Text(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  const Text.rich(
    super.textSpan, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  }) : super.rich();

  @override
  m.Widget build(m.BuildContext context) {
    m.Localizations.maybeLocaleOf(
      context,
    ); // rebuild when the app's language changes
    final words = data;
    final shown = words == null ? null : tr(words);
    if (shown == null || shown == words) return super.build(context);
    return m.Text(
      shown,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null ? null : tr(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
