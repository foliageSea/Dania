import 'responsive_button.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_exception.dart';
import 'localization.dart';

class PageSafeArea extends StatelessWidget {
  const PageSafeArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: context.theme.colors.systemOverlayStyle,
    child: ColoredBox(
      color: context.theme.colors.background,
      child: SafeArea(child: child),
    ),
  );
}

class PageContent extends StatelessWidget {
  const PageContent({
    required this.children,
    this.compact = false,
    this.expandedChild,
    this.fill = false,
    super.key,
  }) : assert(!fill || expandedChild == null);
  final List<Widget> children;
  final bool compact;
  final Widget? expandedChild;
  final bool fill;
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = compact
        ? (width < 600 ? 12.0 : 20.0)
        : width < 600
        ? 16.0
        : width < 1024
        ? 24.0
        : 32.0;
    return ColoredBox(
      color: context.theme.colors.background,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: fill
                ? Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  )
                : expandedChild == null
                ? ListView(padding: EdgeInsets.all(padding), children: children)
                : Padding(
                    padding: EdgeInsets.all(padding),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: constraints.maxHeight * .65,
                            ),
                            child: SingleChildScrollView(
                              primary: false,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: children,
                              ),
                            ),
                          ),
                          Expanded(child: expandedChild!),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {this.action, this.compact = false, super.key});
  final String title;
  final Widget? action;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: compact ? 16 : 28),
    child: compact
        ? Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: context.theme.typography.display.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              ?action,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.theme.typography.display.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    required this.child,
    this.padding = 24,
    this.expand = false,
    super.key,
  });
  final Widget child;
  final double padding;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final card = FCard(
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
    return expand ? SizedBox.expand(child: card) : card;
  }
}

class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    required this.children,
    this.minWidth = 280,
    this.spacing = 16,
    this.maxColumns = 4,
    super.key,
  });
  final List<Widget> children;
  final double minWidth;
  final double spacing;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = ((box.maxWidth + spacing) / (minWidth + spacing))
          .floor()
          .clamp(1, children.length.clamp(1, maxColumns));
      final width = (box.maxWidth - (columns - 1) * spacing) / columns;
      return AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        ),
      );
    },
  );
}

String failureMessage(BuildContext context, Object error) {
  final l = context.l10n;
  return switch (error) {
    AppException(kind: FailureKind.storage) => l.storageError,
    AppException(kind: FailureKind.timeout) => l.timeoutError,
    AppException(kind: FailureKind.server) => l.serverError,
    AppException(kind: FailureKind.invalidData) => l.invalidDataError,
    AppException(kind: FailureKind.cancelled) => l.cancelledError,
    _ => l.networkError,
  };
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.error, {this.onRetry, super.key});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FAlert(
        variant: .destructive,
        title: Text(context.l10n.errorTitle),
        subtitle: Text(failureMessage(context, error)),
      ),
      if (onRetry != null) ...[
        const SizedBox(height: 12),
        FButton(
          builder: responsiveButtonContent,
          variant: .outline,
          onPress: onRetry,
          child: Text(context.l10n.retry),
        ),
      ],
    ],
  );
}

class LoadingNotice extends StatelessWidget {
  const LoadingNotice({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const FCircularProgress(),
        const SizedBox(height: 16),
        Text(context.l10n.loading),
      ],
    ),
  );
}

class EmptyNotice extends StatelessWidget {
  const EmptyNotice(this.message, {this.child, super.key});
  final String message;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      children: [
        Icon(
          FLucideIcons.inbox,
          size: 32,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        if (child != null) ...[const SizedBox(height: 16), child!],
      ],
    ),
  );
}

void notifyUser(BuildContext context, String message) => showFToast(
  context: context,
  title: Text(message),
  alignment: FToastAlignment.topCenter,
);
Future<void> openDocumentation(BuildContext context, String url) async {
  try {
    if (!await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ) &&
        context.mounted) {
      notifyUser(context, context.l10n.linkError);
    }
  } catch (_) {
    if (context.mounted) notifyUser(context, context.l10n.linkError);
  }
}

Future<void> copySource(BuildContext context, String source) async {
  await Clipboard.setData(ClipboardData(text: source));
  if (context.mounted) notifyUser(context, context.l10n.copied);
}

class EscapeDismiss extends StatelessWidget {
  const EscapeDismiss({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
    },
    child: child,
  );
}
