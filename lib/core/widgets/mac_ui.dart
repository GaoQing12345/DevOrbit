import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

/// Page scaffold for the macOS tool windows: one content column, no app bar,
/// generous top inset, and an optional action row aligned with the title.
class MacPageScaffold extends StatelessWidget {
  const MacPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(28, 24, 28, 36),
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsets padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: padding,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in actions)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: action,
                    ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

/// A single control row pinned to the top of a tool window: white, hairline
/// rule underneath, 46pt tall. [leading] sits on the left, [trailing] on the
/// right, so the title and the actions never fight over the middle.
class MacToolbar extends StatelessWidget {
  const MacToolbar({
    super.key,
    this.leading = const [],
    this.trailing = const [],
    this.height = 46,
  });

  final List<Widget> leading;
  final List<Widget> trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          ...spaced(leading, 6),
          const Spacer(),
          ...spaced(trailing, 6),
        ],
      ),
    );
  }
}

/// Small icon plus label used as a tool window's toolbar title.
class MacToolbarTitle extends StatelessWidget {
  const MacToolbarTitle(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

/// The base surface of a tool page: white body, hairline border, 10pt radius,
/// optional 34pt header and footer. Set [expand] to false when the panel is
/// placed in a scroll view instead of a bounded column.
class MacPanel extends StatelessWidget {
  const MacPanel({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    this.footer,
    this.emphasized = false,
    this.expand = true,
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget? footer;

  /// Draws the border in the accent colour, for the pane that owns the caret.
  final bool emphasized;
  final bool expand;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppTheme.radiusPanel);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(
          color: emphasized ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusPanel - 1),
        child: Column(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Container(
                height: 34,
                padding: const EdgeInsets.only(left: 12, right: 3),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            if (expand)
              Expanded(
                child: Padding(padding: padding, child: child),
              )
            else
              Padding(padding: padding, child: child),
            if (footer != null)
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom strip of a tool window for status text, counters and navigation.
class MacStatusBar extends StatelessWidget {
  const MacStatusBar({
    super.key,
    this.leading = const [],
    this.trailing = const [],
    this.height = 26,
  });

  final List<Widget> leading;
  final List<Widget> trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          ...spaced(leading, 6),
          if (trailing.isNotEmpty) const Spacer(),
          ...spaced(trailing, 12),
        ],
      ),
    );
  }
}

/// Joins [items] with a fixed gap, which keeps [Row] children lists readable
/// without scattering `SizedBox` between every pair.
List<Widget> spaced(List<Widget> items, double gap) {
  return [
    for (var index = 0; index < items.length; index++) ...[
      if (index > 0) SizedBox(width: gap),
      items[index],
    ],
  ];
}

/// A macOS grouped box: white card on the window background, hairline border,
/// 10pt corner radius, and inset dividers between rows.
class MacGroup extends StatelessWidget {
  const MacGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppTheme.radiusPanel),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusPanel),
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index < children.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 12,
                      endIndent: 12,
                      color: scheme.outlineVariant.withAlpha(160),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One row inside a [MacGroup]: label (and optional caption) left, control
/// right. 44pt minimum height matches System Settings.
class MacRow extends StatelessWidget {
  const MacRow({
    super.key,
    required this.title,
    this.description,
    required this.trailing,
  });

  final String title;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  if (description != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// A small caption above a group, used when [MacGroup.title] would be too
/// heavy (for example inside tightly packed tool panels).
class MacCaption extends StatelessWidget {
  const MacCaption(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The window's brand mark, used in the toolbox header.
class OrbitMark extends StatelessWidget {
  const OrbitMark({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size * 0.46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, accent.withAlpha(150)]),
              borderRadius: BorderRadius.circular(size),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: size * 0.2),
          ),
        ],
      ),
    );
  }
}
