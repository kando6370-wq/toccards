import 'package:flutter/material.dart';

import 'kando_style.dart';

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
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) {
      return KandoConfirmModal(
        title: title,
        message: message,
        icon: Icons.delete_outline,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmType: KandoModalButtonType.delete,
        onCancel: () => Navigator.of(context).pop(false),
        onConfirm: () => Navigator.of(context).pop(true),
      );
    },
  );
  return result == true;
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
        onCancel: () => Navigator.of(context).pop(false),
        onConfirm: () => Navigator.of(context).pop(true),
      );
    },
  );
  return result == true;
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

  @override
  Widget build(BuildContext context) {
    return KandoModalFrame(
      height: compact ? 334 : 378,
      child: Padding(
        padding: const EdgeInsets.all(33),
        child: SizedBox(
          width: 276,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _KandoModalIcon(icon: icon),
              const SizedBox(height: 20),
              _KandoModalText(title: title, message: message),
              const Spacer(),
              _KandoModalActions(
                primaryLabel: confirmLabel,
                secondaryLabel: cancelLabel,
                primaryType: confirmType,
                onPrimary: onConfirm,
                onSecondary: onCancel,
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
/// Visual contract: centered dark surface, subtle border, 24px radius, and
/// shadow. Width defaults to 342px for confirm/update modals; welcome uses
/// 260px. Use this only when building a new modal type that is already defined
/// in the design system.
///
/// 中文：Figma 弹窗基础外壳。视觉规格为居中暗色面板、弱描边、24px
/// 圆角和阴影。确认/升级弹窗默认 342px，欢迎弹窗 260px。只有新增
/// 设计系统已定义的弹窗类型时才直接使用。
class KandoModalFrame extends StatelessWidget {
  const KandoModalFrame({
    super.key,
    required this.child,
    this.width = 342,
    this.height,
  });

  final Widget child;
  final double width;
  final double? height;

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
          color: KandoColors.surface,
          border: Border.all(color: KandoColors.borderSubtle),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 32,
              offset: Offset(0, 18),
            ),
          ],
        ),
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
  });

  final String label;
  final VoidCallback? onPressed;
  final KandoModalButtonType type;

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
          disabledBackgroundColor: KandoColors.elevatedSurface,
          disabledForegroundColor: KandoColors.disabledText,
          shape: StadiumBorder(side: BorderSide(color: colors.border)),
          textStyle: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            height: 16 / 13,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _KandoModalIcon extends StatelessWidget {
  const _KandoModalIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        color: KandoColors.accentGlow10,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 26, color: KandoColors.accent),
    );
  }
}

class _KandoModalText extends StatelessWidget {
  const _KandoModalText({required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: KandoColors.text,
            fontFamily: 'Fraunces',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 32 / 22,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KandoColors.mutedText,
              fontSize: 13,
              height: 20 / 13,
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
    this.hideSecondary = false,
  });

  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;
  final KandoModalButtonType primaryType;
  final bool hideSecondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 276,
      height: hideSecondary ? 44 : 108,
      child: Column(
        children: [
          KandoModalButton(
            label: primaryLabel,
            type: primaryType,
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
