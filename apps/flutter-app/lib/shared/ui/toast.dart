import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'kando_style.dart';

const genericFailureToastText = 'Something went wrong. Please try again.';
const networkFailureToastText =
    'No internet connection. Please check your network and try again.';
const portfolioCardAddedToastText = '1 card added to your portfolio';

String portfolioCardsAddedToastText(int count) {
  return count == 1
      ? portfolioCardAddedToastText
      : '$count cards added to your portfolio';
}

const kandoToastDuration = Duration(seconds: 2);
const kandoTopToastDuration = Duration(seconds: 3);
const kandoCenteredSuccessToastDuration = Duration(milliseconds: 1500);
const kandoTopToastTopGap = 28.0;

OverlayEntry? _kandoTopToastEntry;
Timer? _kandoTopToastTimer;
OverlayEntry? _kandoCenteredSuccessToastEntry;
Timer? _kandoCenteredSuccessToastTimer;

/// Visual/semantic variants for top overlay toasts.
///
/// 中文：顶部提示框类型。调用时传入 type，不同类型会展示不同的图标、
/// 图标颜色和图标底色。
enum KandoTopToastType { failure, network, success, warning, info }

/// Builds the Figma-style floating toast shell.
///
/// Use for non-blocking feedback that should not interrupt the current task:
/// generic failures, network errors, save success, form submission success, and
/// other low-risk status messages. Do not use this for irreversible actions
/// such as deleting cards or removing portfolio items; use the confirm modals in
/// `kando_modal.dart` for those flows.
///
/// 中文：用于非阻断轻提示，例如通用失败、网络错误、保存成功、表单提交
/// 成功等。不要用于删除卡牌、移除收藏项、删除账号这类需要用户确认的
/// 不可逆操作；这些场景必须使用 `kando_modal.dart` 中的确认弹窗。
SnackBar buildKandoToast(String message, {VoidCallback? onClose}) {
  return SnackBar(
    width: 350,
    elevation: 0,
    padding: EdgeInsets.zero,
    backgroundColor: Colors.transparent,
    content: KandoFloatingToast(message: message, onClose: onClose),
    duration: kandoToastDuration,
    behavior: SnackBarBehavior.floating,
  );
}

/// Shows a non-blocking floating toast and replaces any toast already visible.
///
/// Use this when the caller has a custom short message. Prefer
/// [showKandoFailureToast] and [showKandoNetworkToast] for the common failure
/// cases so copy stays consistent across the app.
///
/// 中文：显示一条非阻断 toast，并替换当前已显示的 toast。自定义短文案
/// 可以用它；通用失败和网络错误优先用专门方法，保证全局文案一致。
void showKandoToast(BuildContext context, {required String message}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      buildKandoToast(message, onClose: messenger.hideCurrentSnackBar),
    );
}

/// Shows the generic operation-failed toast.
///
/// Use when an API or local action fails and the user does not need to make an
/// immediate decision. This is the default fallback for unknown errors.
///
/// 中文：用于 API 或本地操作失败、但不需要用户马上做决策的场景。未知
/// 错误默认走这个提示。
void showKandoFailureToast(BuildContext context) {
  showKandoToast(context, message: genericFailureToastText);
}

/// Shows the no-network toast.
///
/// Use when the app can identify connectivity as the reason an action failed.
///
/// 中文：用于明确判断为网络连接问题导致操作失败的场景。
void showKandoNetworkToast(BuildContext context) {
  showKandoToast(context, message: networkFailureToastText);
}

/// Shows a Figma-style toast at the top of the screen.
///
/// Use for global status messages that should appear near the top safe area:
/// network errors, generic failures, lightweight success, warning, and info
/// messages. The newest top toast replaces the current one.
///
/// 中文：在屏幕顶部安全区下方展示提示框。用于网络错误、通用失败、轻量
/// 成功、警告、信息提示等全局状态反馈。新的顶部提示会替换旧提示。
void showKandoTopToast(
  BuildContext context, {
  required String message,
  KandoTopToastType type = KandoTopToastType.info,
  Duration duration = kandoTopToastDuration,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _removeKandoTopToast();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      final top = MediaQuery.paddingOf(context).top + kandoTopToastTopGap;
      return Positioned(
        left: 20,
        right: 20,
        top: top,
        child: IgnorePointer(
          ignoring: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: KandoTopToast(
              message: message,
              type: type,
              onClose: _removeKandoTopToast,
            ),
          ),
        ),
      );
    },
  );

  _kandoTopToastEntry = entry;
  overlay.insert(entry);
  _kandoTopToastTimer = Timer(duration, _removeKandoTopToast);
}

/// Shows the generic failure message as a top toast.
///
/// 中文：以顶部提示框展示通用失败文案。
void showKandoTopFailureToast(BuildContext context) {
  showKandoTopToast(
    context,
    message: genericFailureToastText,
    type: KandoTopToastType.failure,
  );
}

/// Shows the no-network message as a top toast.
///
/// 中文：以顶部提示框展示无网络文案。
void showKandoTopNetworkToast(BuildContext context) {
  showKandoTopToast(
    context,
    message: networkFailureToastText,
    type: KandoTopToastType.network,
  );
}

/// Shows the Figma centered success toast and replaces any current instance.
///
/// 中文：显示 Figma 居中成功提示，并替换当前已显示的同类提示。
void showKandoCenteredSuccessToast(
  BuildContext context, {
  String title = 'Success',
  required String message,
  Duration duration = kandoCenteredSuccessToastDuration,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _removeKandoCenteredSuccessToast();

  final entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: KandoCenteredSuccessToast(title: title, message: message),
        ),
      ),
    ),
  );
  _kandoCenteredSuccessToastEntry = entry;
  overlay.insert(entry);
  _kandoCenteredSuccessToastTimer = Timer(
    duration,
    _removeKandoCenteredSuccessToast,
  );
}

void _removeKandoTopToast() {
  _kandoTopToastTimer?.cancel();
  _kandoTopToastTimer = null;
  _kandoTopToastEntry?.remove();
  _kandoTopToastEntry = null;
}

void _removeKandoCenteredSuccessToast() {
  _kandoCenteredSuccessToastTimer?.cancel();
  _kandoCenteredSuccessToastTimer = null;
  _kandoCenteredSuccessToastEntry?.remove();
  _kandoCenteredSuccessToastEntry = null;
}

/// Figma centered success toast from node 183:10881.
class KandoCenteredSuccessToast extends StatelessWidget {
  const KandoCenteredSuccessToast({
    super.key,
    this.title = 'Success',
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    const designWidth = 320.0;
    const designHeight = 212.0;
    const viewportInset = 20.0;
    final availableWidth = math.max(0.0, viewport.width - viewportInset * 2);
    final availableHeight = math.max(0.0, viewport.height - viewportInset * 2);
    final frameScale = math.min(
      1.0,
      math.min(availableWidth / designWidth, availableHeight / designHeight),
    );
    final width = designWidth * frameScale;
    final height = designHeight * frameScale;
    const horizontalPadding = 20.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('kando-centered-success-toast'),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              offset: Offset(0, 25),
              blurRadius: 50,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: DecoratedBox(
              key: const Key('kando-centered-success-surface'),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(
                    key: Key('kando-centered-success-background'),
                    painter: _KandoCenteredSuccessBackgroundPainter(),
                    child: SizedBox.expand(),
                  ),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _KandoCenteredSuccessIcon(),
                          SizedBox(height: 24),
                          Text(
                            title,
                            key: const Key('kando-centered-success-title'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              color: Color(0xFFF1FE70),
                              fontFamily: 'Fraunces',
                              fontSize: 24,
                              height: 32 / 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            message,
                            key: const Key('kando-centered-success-message'),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            softWrap: true,
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              color: Color(0xFFE3E3D6),
                              fontSize: 15,
                              height: 22 / 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KandoCenteredSuccessBackgroundPainter extends CustomPainter {
  const _KandoCenteredSuccessBackgroundPainter();

  static const _designSize = Size(320, 212);
  static const _figmaAngle = 111.108253161755;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x0FFFFFFF),
    );
    _paintLinearLayer(canvas, size, const [
      Color(0xE6393D2D),
      Color(0xE612140E),
    ]);
    _paintLinearLayer(canvas, size, const [
      Color(0xE61C1E15),
      Color(0xE612140E),
    ]);
    _paintFigmaOverlay(canvas, size);
  }

  void _paintLinearLayer(Canvas canvas, Size size, List<Color> colors) {
    final radians = _figmaAngle * math.pi / 180;
    final direction = Offset(math.sin(radians), -math.cos(radians));
    final extent =
        size.width * direction.dx.abs() + size.height * direction.dy.abs();
    final center = size.center(Offset.zero);
    final halfVector = direction * (extent / 2);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        center - halfVector,
        center + halfVector,
        colors,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _paintFigmaOverlay(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(5, 5),
        const [
          Color(0x3DF0FE70),
          Color(0x3DB8C257),
          Color(0x3D9CA54A),
          Color(0x3D80873E),
          Color(0x3D646931),
          Color(0x3D484B24),
          Color(0x3D2C2D18),
          Color(0x3D1E1F11),
          Color(0x3D10100B),
        ],
        const [
          0,
          0.16686,
          0.25029,
          0.33372,
          0.41715,
          0.50058,
          0.58402,
          0.62573,
          0.66745,
        ],
      );

    canvas.save();
    canvas.scale(
      size.width / _designSize.width,
      size.height / _designSize.height,
    );
    canvas.transform(
      Float64List.fromList(const [
        37.477,
        36.818,
        0,
        0,
        -64.648,
        55.241,
        0,
        0,
        0,
        0,
        1,
        0,
        -118.77,
        -121.79,
        0,
        1,
      ]),
    );
    for (final scaleX in const [-1.0, 1.0]) {
      for (final scaleY in const [-1.0, 1.0]) {
        canvas.save();
        canvas.scale(scaleX, scaleY);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 73.758, 26.43), paint);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KandoCenteredSuccessBackgroundPainter oldDelegate) {
    return false;
  }
}

class _KandoCenteredSuccessIcon extends StatelessWidget {
  const _KandoCenteredSuccessIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('kando-centered-success-icon'),
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(0x1FF1FE70),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x1AFFFFFF), width: 1.4),
      ),
      child: const Icon(Icons.check_circle, size: 26, color: Color(0xFFF1FE70)),
    );
  }
}

/// Figma floating toast content.
///
/// Visual contract: 350x74, dark floating surface, 40px icon overlay, two-line
/// message, and a small close affordance. This widget is intentionally wrapped
/// by [buildKandoToast] so current app call sites can keep using
/// `ScaffoldMessenger` while matching the Figma toast style.
///
/// 中文：Figma 视觉规格为 350x74、暗色浮层、左侧 40px 图标区、最多
/// 两行文案和右侧小关闭按钮。当前通过 [buildKandoToast] 包装，保留
/// 现有 `ScaffoldMessenger` 调用方式，同时统一视觉。
class KandoFloatingToast extends StatelessWidget {
  const KandoFloatingToast({
    super.key,
    required this.message,
    this.icon = Icons.error_outline,
    this.onClose,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('kando-floating-toast'),
      width: 350,
      height: 74,
      decoration: BoxDecoration(
        color: KandoColors.surface,
        border: Border.all(color: KandoColors.borderSubtle),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 17),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: KandoColors.accentGlow10,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: KandoColors.accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KandoColors.text,
                fontSize: 13,
                height: 20 / 13,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            height: 40,
            child: IconButton(
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(
                Icons.close,
                size: 12,
                color: KandoColors.mutedText,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// Figma top overlay toast content.
///
/// Visual contract: 350x74, dark rounded surface, 40px type icon overlay,
/// two-line ellipsized message, swipe-up dismiss on the toast itself, and
/// right-side close affordance. Use through [showKandoTopToast] so replacement
/// and auto-dismiss behavior stays global.
///
/// 中文：顶部 Overlay Toast 内容组件。视觉规格为 350x74、暗色圆角面板、
/// 左侧 40px 类型图标区、文案最多两行且超出显示省略号。只有触摸到
/// 提示框本身并向上滑动才会关闭；点击右侧关闭图标也会关闭。业务代码
/// 优先调用 [showKandoTopToast]，保证全局替换和自动关闭逻辑一致。
class KandoTopToast extends StatelessWidget {
  const KandoTopToast({
    super.key,
    required this.message,
    this.type = KandoTopToastType.info,
    this.onClose,
  });

  final String message;
  final KandoTopToastType type;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final style = _KandoTopToastStyle.fromType(type);
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity;
          if (velocity != null && velocity < -120) {
            onClose?.call();
          }
        },
        child: Container(
          key: const Key('kando-top-toast'),
          width: 350,
          height: 74,
          decoration: BoxDecoration(
            color: KandoColors.surface,
            border: Border.all(color: KandoColors.borderSubtle),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 17),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, size: 20, color: style.iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KandoColors.text,
                    fontSize: 13,
                    height: 20 / 13,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 40,
                child: IconButton(
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close,
                    size: 12,
                    color: KandoColors.mutedText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _KandoTopToastStyle {
  const _KandoTopToastStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;

  factory _KandoTopToastStyle.fromType(KandoTopToastType type) {
    return switch (type) {
      KandoTopToastType.failure => const _KandoTopToastStyle(
        icon: Icons.priority_high_rounded,
        iconColor: KandoColors.errorText,
        iconBackground: Color(0x33FF8989),
      ),
      KandoTopToastType.network => const _KandoTopToastStyle(
        icon: Icons.wifi_off_rounded,
        iconColor: KandoColors.mutedText,
        iconBackground: Color(0x1FFFFFFF),
      ),
      KandoTopToastType.success => const _KandoTopToastStyle(
        icon: Icons.check_rounded,
        iconColor: KandoColors.gain,
        iconBackground: Color(0x334ADE80),
      ),
      KandoTopToastType.warning => const _KandoTopToastStyle(
        icon: Icons.priority_high_rounded,
        iconColor: KandoColors.money,
        iconBackground: Color(0x33FFF6AF),
      ),
      KandoTopToastType.info => const _KandoTopToastStyle(
        icon: Icons.info_outline_rounded,
        iconColor: KandoColors.accent,
        iconBackground: KandoColors.accentGlow10,
      ),
    };
  }
}
