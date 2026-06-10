import 'package:flutter/material.dart';

import 'event_log.dart';
import 'theme.dart';

/// A light-purple badge listing the RUM features exercised on a screen.
class FeatureBadge extends StatelessWidget {
  const FeatureBadge({super.key, required this.features});

  final List<String> features;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.featureBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'RUM FEATURES ON THIS SCREEN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          for (final String f in features)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '✓ $f',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF444444),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A bold section title with consistent vertical spacing.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: AppText.sectionTitle),
    );
  }
}

/// Small grey helper text under section titles.
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: AppText.hint),
    );
  }
}

/// A white surface with a thin grey border, used as the base for most cards.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 12,
    this.borderColor = AppColors.cardBorder,
    this.leftBorderColor,
    this.leftBorderWidth = 0,
    this.margin = const EdgeInsets.only(bottom: 8),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color borderColor;
  final Color? leftBorderColor;
  final double leftBorderWidth;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final Widget card = Container(
      width: double.infinity,
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
        border: Border(
          top: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
          left: BorderSide(
            color: leftBorderColor ?? borderColor,
            width: leftBorderColor != null ? leftBorderWidth : 1,
          ),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// Purple, full-width primary action button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

/// A compact white action card with an emoji/icon and a small label.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A white card with a colored 4px left border, a bold title and a subtitle.
/// Used for the error-trigger buttons on the Errors screen.
class ErrorButton extends StatelessWidget {
  const ErrorButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 10,
      leftBorderColor: color,
      leftBorderWidth: 4,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// Result of an HTTP request, rendered by [ApiResultCard].
class ApiResult {
  const ApiResult({
    required this.label,
    required this.status,
    required this.durationMs,
    required this.ok,
    this.method = 'GET',
    this.path = '',
    this.error,
    this.body,
  });

  final String label;
  final String method;
  final String path;
  final int status;
  final int durationMs;
  final bool ok;
  final String? error;
  final String? body;
}

/// A white card with a colored left border showing an API request outcome.
class ApiResultCard extends StatelessWidget {
  const ApiResultCard({super.key, required this.result});

  final ApiResult result;

  @override
  Widget build(BuildContext context) {
    final Color color = result.ok
        ? AppColors.ok
        : result.status == 0
            ? AppColors.neutral
            : AppColors.error;
    return AppCard(
      radius: 8,
      leftBorderColor: color,
      leftBorderWidth: 3,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  result.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${result.status == 0 ? 'ERR' : result.status} · ${result.durationMs}ms',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          if (result.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                result.error!,
                style: const TextStyle(fontSize: 11, color: AppColors.error),
              ),
            ),
          if (result.body != null && result.body!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                result.body!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A navigation list tile (white card) linking to another screen.
class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 10,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Text('›',
              style: TextStyle(fontSize: 20, color: Color(0xFFCCCCCC))),
        ],
      ),
    );
  }
}

/// A white "summary" card with a bold title and a list of muted body lines.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.lines,
    this.selectable = false,
  });

  final String title;
  final List<String> lines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    const TextStyle bodyStyle = TextStyle(
      fontSize: 12,
      height: 1.6,
      color: AppColors.textSecondary,
    );
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          for (final String line in lines)
            selectable
                ? SelectableText(line, style: bodyStyle)
                : Text(line, style: bodyStyle),
        ],
      ),
    );
  }
}

/// A monospace context card (used for the WebView native-context probe JSON).
class ContextCard extends StatelessWidget {
  const ContextCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 10,
      padding: const EdgeInsets.all(12),
      margin: EdgeInsets.zero,
      child: SelectableText(
        text,
        style: const TextStyle(
          fontSize: 11,
          height: 1.45,
          color: Color(0xFF333333),
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

/// The Session ID card shown on multiple tabs.
class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.sessionId, this.hint});

  final String sessionId;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Session ID',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            sessionId,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Color(0xFF333333),
            ),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: const TextStyle(fontSize: 10, color: Color(0xFFAAAAAA)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A key/value config card with hairline row dividers.
class ConfigCard extends StatelessWidget {
  const ConfigCard({super.key, required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 10,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFF5F5F5)),
                      ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(rows[i][0],
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                  Text(
                    rows[i][1],
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom-sheet rendering the global [EventLog], most-recent-first.
class DebugLogSheet extends StatelessWidget {
  const DebugLogSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const DebugLogSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.65,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('Event Log',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Text('✕',
                      style: TextStyle(fontSize: 20, color: Color(0xFF999999))),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ValueListenableBuilder<List<LogEntry>>(
                  valueListenable: EventLog.entries,
                  builder: (_, List<LogEntry> logs, _) {
                    if (logs.isEmpty) {
                      return const Align(
                        alignment: Alignment.topLeft,
                        child: Text('No events yet', style: AppText.hint),
                      );
                    }
                    return ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (_, int i) {
                        final LogEntry e = logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text.rich(
                            TextSpan(children: <InlineSpan>[
                              TextSpan(
                                text: '${e.ts} ',
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF999999)),
                              ),
                              TextSpan(
                                text: e.msg,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF333333)),
                              ),
                            ]),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
