import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../analytics/analytics_events.dart';
import '../analytics/app_analytics.dart';
import 'kando_style.dart';

const _dangerHeaderIconAsset = 'assets/ui/modal_danger_delete.svg';
const _dangerButtonIconAsset = 'assets/ui/modal_delete_button.svg';

/// Result returned by the app update modal.
///
/// 中文：版本升级弹窗的返回结果。
enum KandoUpdateModalResult { updateNow, later }

/// Shows the destructive-action confirmation modal.
///
/// Use for high-risk or irreversible operations: delete all cards, delete an
/// account, clear a portfolio, or any action where data loss is expected. This
/// modal is intentionally blocking and defaults to a non-dismissible barrier so
/// users must choose either the destructive action or cancel.
///
/// 中文：用于高风险、不可逆、会造成数据丢失的操作，例如删除全部卡牌、
/// 删除账号、清空 portfolio。默认不可点击遮罩关闭，用户必须明确选择
/// 删除或取消。
Future<bool> showKandoDangerConfirmModal(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  bool barrierDismissible = false,
  Future<bool> Function()? confirmAction,
}) async {
  _track(context, AnalyticsEvent.deleteClick);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => _KandoDangerConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmAction: confirmAction,
    ),
  );
  return result == true;
}

class _KandoDangerConfirmDialog extends StatefulWidget {
  const _KandoDangerConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.confirmAction,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final Future<bool> Function()? confirmAction;

  @override
  State<_KandoDangerConfirmDialog> createState() =>
      _KandoDangerConfirmDialogState();
}

class _KandoDangerConfirmDialogState extends State<_KandoDangerConfirmDialog> {
  bool _isConfirming = false;

  Future<void> _confirm() async {
    if (_isConfirming) return;
    _track(context, AnalyticsEvent.deleteConfirmClick);
    final action = widget.confirmAction;
    if (action == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _isConfirming = true);
    var succeeded = false;
    try {
      succeeded = await action();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'kando modal',
          context: ErrorDescription('while confirming a destructive action'),
        ),
      );
    }
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isConfirming = false);
    }
  }

  void _cancel() {
    if (_isConfirming) return;
    _track(context, AnalyticsEvent.cancelClick);
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isConfirming,
      child: KandoConfirmModal(
        title: widget.title,
        message: widget.message,
        icon: Icons.delete_outline,
        confirmLabel: widget.confirmLabel,
        cancelLabel: widget.cancelLabel,
        confirmType: KandoModalButtonType.delete,
        isConfirming: _isConfirming,
        onCancel: _cancel,
        onConfirm: _confirm,
      ),
    );
  }
}

/// Shows the single-item removal confirmation modal.
///
/// Use for removing one card from a portfolio, removing one collection item, or
/// removing one saved/wishlist object when the action should not happen
/// silently. If a future design adds undo-toast behavior for a specific flow,
/// that page may opt into it; otherwise use this modal.
///
/// 中文：用于移除单个对象，例如从 portfolio 移除一张卡、删除一个
/// collection item、移除 wishlist 对象。没有明确 undo-toast 设计时，
/// 不要静默移除，必须用这个确认弹窗。
Future<bool> showKandoRemoveConfirmModal(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Remove',
  String cancelLabel = 'Cancel',
}) async {
  _track(context, AnalyticsEvent.deleteClick);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return KandoConfirmModal(
        title: title,
        message: message,
        icon: Icons.bookmark_remove_outlined,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmType: KandoModalButtonType.primary,
        compact: true,
        onCancel: () {
          _track(context, AnalyticsEvent.cancelClick);
          Navigator.of(context).pop(false);
        },
        onConfirm: () {
          _track(context, AnalyticsEvent.deleteConfirmClick);
          Navigator.of(context).pop(true);
        },
      );
    },
  );
  return result == true;
}

void _track(BuildContext context, String event) {
  try {
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(analyticsProvider).track(event);
  } on StateError {
    // Analytics is optional for standalone modal hosts and widget tests.
  }
}

/// Shows the app update modal.
///
/// Use for optional or forced version updates. Set [forceUpdate] when the user
/// cannot continue without upgrading; in that case the secondary action is
/// hidden and back navigation is disabled.
///
/// 中文：用于 App 版本升级提示。普通升级可保留 Later；强制升级时设置
/// [forceUpdate]，隐藏次按钮并禁用返回。
Future<KandoUpdateModalResult?> showKandoUpdateModal(
  BuildContext context, {
  required String title,
  required String message,
  String primaryLabel = 'Update Now',
  String secondaryLabel = 'Later',
  bool forceUpdate = false,
}) {
  return showDialog<KandoUpdateModalResult>(
    context: context,
    barrierDismissible: !forceUpdate,
    builder: (context) {
      final modal = KandoUpdateModal(
        title: title,
        message: message,
        primaryLabel: primaryLabel,
        secondaryLabel: secondaryLabel,
        forceUpdate: forceUpdate,
        onPrimary: () =>
            Navigator.of(context).pop(KandoUpdateModalResult.updateNow),
        onSecondary: () =>
            Navigator.of(context).pop(KandoUpdateModalResult.later),
      );
      return forceUpdate ? PopScope(canPop: false, child: modal) : modal;
    },
  );
}

/// Shows the centered welcome/success modal.
///
/// Use for important success states that deserve more emphasis than a toast,
/// such as account creation or first-time welcome. For routine saves and minor
/// success feedback, use `showKandoToast` instead.
///
/// 中文：用于比 toast 更重要的成功态，例如账号创建成功、首次欢迎。
/// 普通保存成功、轻量提交成功不要用弹窗，使用 `showKandoToast`。
Future<void> showKandoWelcomeModal(
  BuildContext context, {
  String title = 'Welcome',
  required String message,
  String? actionLabel,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: actionLabel == null,
    builder: (context) {
      return KandoWelcomeModal(
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: () => Navigator.of(context).pop(),
      );
    },
  );
}

Future<void> showKandoFailureAlert(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'OK',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => KandoModalFrame(
      height: 310,
      child: Padding(
        padding: const EdgeInsets.all(33),
        child: SizedBox(
          width: 276,
          child: Column(
            children: [
              const _KandoModalIcon(
                icon: Icons.error_outline,
                color: KandoColors.error,
              ),
              const SizedBox(height: 20),
              _KandoModalText(title: title, message: message),
              const Spacer(),
              KandoModalButton(
                label: actionLabel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Button variants supported by Figma modal actions.
///
/// 中文：Figma 弹窗按钮类型，分别对应主按钮、次按钮和危险操作按钮。
enum KandoModalButtonType { primary, secondary, delete }

/// Shared Figma confirmation modal body.
///
/// Use through [showKandoDangerConfirmModal] or [showKandoRemoveConfirmModal]
/// in app code unless a page needs a custom wrapper but the same visual system.
///
/// 中文：Figma 确认弹窗主体。业务代码优先调用
/// [showKandoDangerConfirmModal] 或 [showKandoRemoveConfirmModal]，只有在
/// 页面需要特殊包装但仍复用同一视觉系统时才直接使用。
class KandoConfirmModal extends StatelessWidget {
  const KandoConfirmModal({
    super.key,
    required this.title,
    this.message,
    required this.icon,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
    this.confirmType = KandoModalButtonType.primary,
    this.compact = false,
    this.isConfirming = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final KandoModalButtonType confirmType;
  final bool compact;
  final bool isConfirming;

  @override
  Widget build(BuildContext context) {
    final danger = confirmType == KandoModalButtonType.delete && !compact;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final frameWidth = math.min(342.0, viewportWidth - 48);
    final compactDangerLayout = danger && frameWidth < 342;
    return KandoModalFrame(
      height: compact
          ? 334
          : danger
          ? compactDangerLayout
                ? 377
                : 355
          : 378,
      danger: danger,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: danger ? 16 : 33,
          vertical: 33,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _KandoModalIcon(
                icon: icon,
                assetPath: danger ? _dangerHeaderIconAsset : null,
                danger: danger,
              ),
              const SizedBox(height: 20),
              _KandoModalText(
                title: title,
                message: message,
                danger: danger,
                dangerMessageLines: compactDangerLayout ? 3 : 2,
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: danger ? 17 : 0),
                child: _KandoModalActions(
                  primaryLabel: confirmLabel,
                  secondaryLabel: cancelLabel,
                  primaryType: confirmType,
                  primaryIconAsset: danger ? _dangerButtonIconAsset : null,
                  primaryLoading: isConfirming,
                  onPrimary: isConfirming ? null : onConfirm,
                  onSecondary: isConfirming ? null : onCancel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared Figma update modal body.
///
/// Used by [showKandoUpdateModal]. Keep app upgrade flows on this component
/// instead of Flutter's default `AlertDialog`.
///
/// 中文：Figma 版本升级弹窗主体。App 升级相关流程必须用这个组件，
/// 不要使用 Flutter 默认 `AlertDialog`。
class KandoUpdateModal extends StatelessWidget {
  const KandoUpdateModal({
    super.key,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.forceUpdate = false,
  });

  final String title;
  final String message;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;
  final bool forceUpdate;

  @override
  Widget build(BuildContext context) {
    return KandoModalFrame(
      height: 452,
      child: Padding(
        padding: const EdgeInsets.all(33),
        child: SizedBox(
          width: 276,
          child: Column(
            children: [
              const SizedBox(height: 10),
              const _KandoUpdateVisual(),
              const SizedBox(height: 40),
              _KandoModalText(title: title, message: message),
              const Spacer(),
              _KandoModalActions(
                primaryLabel: primaryLabel,
                secondaryLabel: secondaryLabel,
                hideSecondary: forceUpdate,
                primaryType: KandoModalButtonType.primary,
                onPrimary: onPrimary,
                onSecondary: onSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared Figma welcome/success modal body.
///
/// Used by [showKandoWelcomeModal]. This mirrors the Figma welcome toast/modal
/// pattern with a 260px shell and optional 44px action button.
///
/// 中文：Figma 欢迎/成功弹窗主体，260px 宽，可选 44px 操作按钮。
/// 用于重要成功态，不用于普通轻提示。
class KandoWelcomeModal extends StatelessWidget {
  const KandoWelcomeModal({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return KandoModalFrame(
      width: 260,
      height: actionLabel == null ? 210 : 274,
      child: Padding(
        padding: const EdgeInsets.all(33),
        child: SizedBox(
          width: 194,
          child: Column(
            children: [
              const _KandoModalIcon(icon: Icons.check),
              const SizedBox(height: 6),
              _KandoModalText(title: title, message: message),
              if (actionLabel != null) ...[
                const Spacer(),
                KandoModalButton(
                  label: actionLabel!,
                  type: KandoModalButtonType.primary,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Base Figma modal shell.
///
/// Visual contract: centered dark surface, subtle border, and shadow. Standard
/// frames use a 24px radius; the Figma danger variant uses 16px. Width defaults
/// to 342px for confirm/update modals; welcome uses 260px. Use this only when
/// building a new modal type that is already defined in the design system.
///
/// 中文：Figma 弹窗基础外壳。视觉规格为居中暗色面板、弱描边和阴影；
/// 普通弹窗使用 24px 圆角，危险确认弹窗使用 16px。确认/升级弹窗默认
/// 342px，欢迎弹窗 260px。只有新增设计系统已定义的弹窗类型时才直接使用。
class KandoModalFrame extends StatelessWidget {
  const KandoModalFrame({
    super.key,
    required this.child,
    this.width = 342,
    this.height,
    this.danger = false,
  });

  final Widget child;
  final double width;
  final double? height;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        key: const Key('kando-modal-frame'),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: danger ? const Color(0xFF1D1D1C) : KandoColors.surface,
          borderRadius: BorderRadius.circular(danger ? 16 : 24),
          boxShadow: danger
              ? const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 50,
                    spreadRadius: -12,
                    offset: Offset(0, 25),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 32,
                    offset: Offset(0, 18),
                  ),
                ],
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(
            color: danger ? const Color(0x1A394E2C) : KandoColors.borderSubtle,
          ),
          borderRadius: BorderRadius.circular(danger ? 16 : 24),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// Figma modal action button.
///
/// Use inside modal action stacks only. For normal page CTAs, use the app's
/// shared button system once that is extracted.
///
/// 中文：Figma 弹窗内的操作按钮，只用于弹窗按钮区。普通页面 CTA
/// 后续应使用 App 共享按钮组件。
class KandoModalButton extends StatelessWidget {
  const KandoModalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.type = KandoModalButtonType.primary,
    this.iconAsset,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final KandoModalButtonType type;
  final String? iconAsset;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = switch (type) {
      KandoModalButtonType.primary => (
        background: KandoColors.accent,
        foreground: KandoColors.primaryOnDefault,
        border: Colors.transparent,
      ),
      KandoModalButtonType.secondary => (
        background: KandoColors.elevatedSurface,
        foreground: KandoColors.text,
        border: KandoColors.borderSubtle,
      ),
      KandoModalButtonType.delete => (
        background: KandoColors.error,
        foreground: KandoColors.primaryOnDefault,
        border: KandoColors.borderSubtle,
      ),
    };

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.background,
          foregroundColor: colors.foreground,
          disabledBackgroundColor: loading
              ? colors.background
              : KandoColors.elevatedSurface,
          disabledForegroundColor: loading
              ? colors.foreground
              : KandoColors.disabledText,
          shape: StadiumBorder(side: BorderSide(color: colors.border)),
          textStyle: const TextStyle(fontSize: 13, height: 16 / 13),
        ),
        child: loading
            ? SizedBox.square(
                key: Key('kando-danger-modal-loading'),
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.foreground,
                ),
              )
            : iconAsset == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    key: const Key('kando-danger-modal-delete-icon'),
                    dimension: 20,
                    child: SvgPicture.asset(iconAsset!, fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
      ),
    );
  }
}

class _KandoModalIcon extends StatelessWidget {
  const _KandoModalIcon({
    required this.icon,
    this.color = KandoColors.accent,
    this.assetPath,
    this.danger = false,
  });

  final IconData icon;
  final Color color;
  final String? assetPath;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: danger ? const Key('kando-danger-modal-header-icon') : null,
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: danger ? const Color(0x1FF87171) : KandoColors.accentGlow10,
        shape: BoxShape.circle,
      ),
      child: assetPath == null
          ? Icon(icon, size: 26, color: color)
          : Center(
              child: SizedBox(
                width: 23.1538,
                height: 24.3207,
                child: SvgPicture.asset(assetPath!, fit: BoxFit.fill),
              ),
            ),
    );
  }
}

class _KandoModalText extends StatelessWidget {
  const _KandoModalText({
    required this.title,
    this.message,
    this.danger = false,
    this.dangerMessageLines = 2,
  });

  final String title;
  final String? message;
  final bool danger;
  final int dangerMessageLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: danger ? 1 : null,
          softWrap: !danger,
          overflow: danger ? TextOverflow.fade : TextOverflow.clip,
          style:
              const TextStyle(
                color: KandoColors.text,
                fontFamily: 'Fraunces',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 32 / 22,
              ).copyWith(
                color: danger ? KandoColors.errorText : null,
                fontSize: danger ? 24 : null,
                height: danger ? 32 / 24 : null,
              ),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: danger ? dangerMessageLines * 22 : null,
            child: Text(
              message!,
              textAlign: TextAlign.center,
              maxLines: danger ? dangerMessageLines : 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(
                    color: KandoColors.mutedText,
                    fontSize: 13,
                    height: 20 / 13,
                  ).copyWith(
                    fontSize: danger ? 15 : null,
                    height: danger ? 22 / 15 : null,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

class _KandoModalActions extends StatelessWidget {
  const _KandoModalActions({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.primaryType = KandoModalButtonType.primary,
    this.primaryIconAsset,
    this.primaryLoading = false,
    this.hideSecondary = false,
  });

  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;
  final KandoModalButtonType primaryType;
  final String? primaryIconAsset;
  final bool primaryLoading;
  final bool hideSecondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: hideSecondary ? 44 : 108,
      child: Column(
        children: [
          if (primaryIconAsset != null) const SizedBox(height: 8),
          KandoModalButton(
            label: primaryLabel,
            type: primaryType,
            iconAsset: primaryIconAsset,
            loading: primaryLoading,
            onPressed: onPrimary,
          ),
          if (!hideSecondary) ...[
            const SizedBox(height: 12),
            KandoModalButton(
              label: secondaryLabel,
              type: KandoModalButtonType.secondary,
              onPressed: onSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _KandoUpdateVisual extends StatelessWidget {
  const _KandoUpdateVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 158,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: KandoColors.accentGlow10,
              shape: BoxShape.circle,
              border: Border.all(color: KandoColors.borderFocus),
            ),
          ),
          Container(
            width: 84,
            height: 112,
            decoration: BoxDecoration(
              color: KandoColors.elevatedSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: KandoColors.borderSubtle),
            ),
            child: const Icon(
              Icons.system_update_alt,
              color: KandoColors.accent,
              size: 34,
            ),
          ),
          const Positioned(
            right: 22,
            top: 28,
            child: Icon(
              Icons.auto_awesome,
              color: KandoColors.accent,
              size: 16,
            ),
          ),
          const Positioned(
            left: 22,
            bottom: 34,
            child: Icon(
              Icons.auto_awesome,
              color: KandoColors.accent,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}
