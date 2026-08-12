import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import '../auth/ui/auth_sheet.dart';
import '../app_upgrade/app_upgrade_repository.dart';
import '../subscription/subscription_controller.dart';
import '../../shared/analytics/analytics_events.dart';
import '../../shared/analytics/app_analytics.dart';
import '../../shared/ui/toast.dart';
import 'account_page.dart';
import 'profile_actions.dart';

final profileVersionProvider = FutureProvider<String>((ref) {
  return ref.watch(installedVersionReaderProvider).currentVersion();
});

// Destructive action red from the Figma spec (no matching design token exists).
const _dangerColor = Color(0xFFFF8989);
const _menuOverlayColor = Color(0x14F0FE6F);

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return KandoTabScaffold(
      currentTab: KandoMainTab.profile,
      body: SafeArea(
        bottom: false,
        child: authState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : authState.hasError
            ? KandoFailureBlock(
                onRefresh: () {
                  ref
                      .read(analyticsProvider)
                      .track(AnalyticsEvent.refreshClick);
                  ref.read(authControllerProvider.notifier).retryStartup();
                },
              )
            : _ProfileContent(
                authState: authState,
                onRefresh: () async {
                  ref
                      .read(analyticsProvider)
                      .track(AnalyticsEvent.refreshClick);
                  ref.invalidate(profileVersionProvider);
                  await ref
                      .read(authControllerProvider.notifier)
                      .retryStartup();
                },
              ),
      ),
    );
  }
}

class _ProfileContent extends ConsumerStatefulWidget {
  const _ProfileContent({required this.authState, required this.onRefresh});

  final AuthState authState;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends ConsumerState<_ProfileContent> {
  static const _apiLogPasscode = 'testapp';

  var _versionTapCount = 0;

  @override
  Widget build(BuildContext context) {
    final session = widget.authState.session;
    final subscription = ref.watch(subscriptionControllerProvider);
    ref.listen(subscriptionControllerProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage &&
          context.mounted) {
        showKandoToast(context, message: next.errorMessage!);
      }
    });
    final isUser = session?.ownerType == OwnerType.user;
    final emailText = session?.email ?? 'Unknown email';
    final userIdText = session?.userId ?? 'Unknown user';
    final versionText = ref
        .watch(profileVersionProvider)
        .when(
          data: (version) => 'Version ${version.split('+').first}',
          error: (_, _) => 'Version unavailable',
          loading: () => 'Version',
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: RefreshIndicator(
          key: const Key('profile-pull-to-refresh'),
          onRefresh: widget.onRefresh,
          child: ListView(
            key: const Key('profile-content-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              KandoLayout.mainTabTopPadding,
              20,
              96,
            ),
            children: [
              if (!subscription.isPro) ...[
                _UpgradeBanner(
                  onTap: () => context.push(subscriptionSheetLocation),
                ),
                const SizedBox(height: 24),
              ],
              _SectionLabel('Account'),
              if (isUser)
                _MenuCard(
                  children: [
                    _AccountRow(
                      email: emailText,
                      userId: userIdText,
                      onTap: () => context.push('/account'),
                    ),
                  ],
                )
              else
                _MenuCard(
                  children: [
                    _MenuRow(
                      icon: Icons.person_outline,
                      label: 'Sign in / Sign up',
                      onTap: () => showAuthSheet(context),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              if (subscription.isPro) ...[
                _SectionLabel('Subscribe'),
                _MenuCard(
                  children: [
                    _MenuRow(
                      icon: Icons.restore,
                      label: 'Restore',
                      onTap: subscription.isLoading
                          ? null
                          : () => ref
                                .read(subscriptionControllerProvider.notifier)
                                .restore(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              _SectionLabel('Support'),
              _MenuCard(
                children: [
                  _MenuRow(
                    icon: Icons.mail_outline,
                    label: 'Customer Support',
                    onTap: () => context.push('/customer-support'),
                  ),
                  _MenuRow(
                    icon: Icons.star_outline,
                    label: 'Score',
                    onTap: () => _runProfileAction(
                      context,
                      () => ref.read(profileActionsProvider).requestScore(),
                    ),
                  ),
                  Builder(
                    builder: (shareContext) => _MenuRow(
                      icon: Icons.share_outlined,
                      label: 'Share With Friends',
                      onTap: () {
                        ref
                            .read(analyticsProvider)
                            .track(AnalyticsEvent.shareAppClick);
                        _runProfileAction(
                          context,
                          () => ref
                              .read(profileActionsProvider)
                              .shareWithFriends(
                                sharePositionOrigin: _sharePositionOrigin(
                                  shareContext,
                                ),
                              ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionLabel('Others'),
              _MenuCard(
                children: [
                  _MenuRow(
                    icon: Icons.description_outlined,
                    label: 'Terms Of Use',
                    onTap: () => _runProfileAction(
                      context,
                      () => ref.read(profileActionsProvider).openTerms(),
                    ),
                  ),
                  _MenuRow(
                    iconAsset: 'assets/profile/privacy_policy.svg',
                    label: 'Privacy Policy',
                    onTap: () => _runProfileAction(
                      context,
                      () => ref.read(profileActionsProvider).openPrivacy(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (isUser)
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      await _logout(context, ref);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: KandoColors.text,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              else
                Center(
                  child: TextButton.icon(
                    onPressed: () => _confirmAndDelete(context, ref),
                    style: TextButton.styleFrom(
                      foregroundColor: _dangerColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    label: const Text(
                      'Delete Account',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _handleVersionTap(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      versionText,
                      key: const Key('profile-version-text'),
                      style: TextStyle(
                        color: KandoColors.mutedText.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleVersionTap(BuildContext context) async {
    _versionTapCount += 1;
    if (_versionTapCount < 5) return;

    _versionTapCount = 0;
    final authorized = await _showApiLogPasscodeDialog(context);
    if (!mounted || !context.mounted) return;

    if (authorized == true) {
      context.push('/profile/api-requests');
    } else if (authorized == false) {
      showKandoToast(context, message: 'Invalid code.');
    }
  }

  Future<bool?> _showApiLogPasscodeDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return const _ApiLogPasscodeDialog(passcode: _apiLogPasscode);
      },
    );
  }

  Future<void> _runProfileAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Exception {
      if (context.mounted) {
        showKandoToast(context, message: profileActionFailureText);
      }
    }
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeleteAccountConfirmation(context);
    if (!context.mounted || !confirmed) {
      return;
    }

    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
    } on Exception {
      if (context.mounted) {
        showKandoToast(context, message: authAccountActionFailedMessage);
      }
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authControllerProvider.notifier).logout();
      if (context.mounted) {
        context.go('/profile');
      }
    } on AuthNetworkException {
      if (context.mounted) {
        showKandoNetworkToast(context);
      }
    } on Exception {
      if (context.mounted) {
        showKandoFailureToast(context);
      }
    }
  }
}

class _UpgradeBanner extends StatelessWidget {
  const _UpgradeBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF34381C), Color(0xFF1A1C14)],
        ),
        border: Border.all(color: KandoColors.borderFocus),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: KandoColors.accentGlow10,
              ),
              child: const Icon(
                Icons.workspace_premium_outlined,
                color: KandoColors.accent,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Upgrade to Pro',
                style: TextStyle(
                  color: KandoColors.text,
                  fontFamily: 'Fraunces',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(onPressed: onTap, child: const Text('Upgrade Now')),
          ],
        ),
      ),
    );
  }
}

class _ApiLogPasscodeDialog extends StatefulWidget {
  const _ApiLogPasscodeDialog({required this.passcode});

  final String passcode;

  @override
  State<_ApiLogPasscodeDialog> createState() => _ApiLogPasscodeDialogState();
}

class _ApiLogPasscodeDialogState extends State<_ApiLogPasscodeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KandoColors.surface,
      title: const Text('Access code'),
      content: TextField(
        key: const Key('api-request-log-passcode-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Enter code'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(context),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(analyticsProvider).track(AnalyticsEvent.cancelClick);
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('api-request-log-passcode-submit'),
          onPressed: () => _submit(context),
          child: const Text('Open'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    Navigator.of(context).pop(_controller.text == widget.passcode);
  }
}

Rect? _sharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: KandoColors.mutedText,
          fontSize: 13,
          letterSpacing: 1.2,
          height: 16 / 13,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            color: KandoColors.border.withValues(alpha: 0.3),
          ),
        );
      }
      rows.add(children[i]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KandoColors.elevatedSurface.withValues(alpha: 0.6),
            KandoColors.ink.withValues(alpha: 0.95),
          ],
        ),
        border: Border.all(color: KandoColors.accent.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: rows),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({this.icon, this.iconAsset, required this.label, this.onTap})
    : assert((icon == null) != (iconAsset == null));

  final IconData? icon;
  final String? iconAsset;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      overlayColor: const WidgetStatePropertyAll(_menuOverlayColor),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _IconBadge(icon: icon, iconAsset: iconAsset),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: KandoColors.text, fontSize: 16),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: KandoColors.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({this.icon, this.iconAsset})
    : assert((icon == null) != (iconAsset == null));

  final IconData? icon;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KandoColors.elevatedSurface,
      ),
      child: iconAsset == null
          ? Icon(icon, size: 18, color: KandoColors.text)
          : Center(
              child: SvgPicture.asset(
                iconAsset!,
                key: const Key('profile-privacy-policy-icon'),
                width: 16,
                height: 20,
              ),
            ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.email, required this.userId, this.onTap});

  final String email;
  final String userId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = email.trim().isNotEmpty
        ? email.trim().characters.first.toUpperCase()
        : '?';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KandoColors.ink,
                border: Border.all(
                  color: KandoColors.accent.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: KandoColors.accent.withValues(alpha: 0.15),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  color: KandoColors.accent,
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KandoColors.text,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: $userId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: KandoColors.mutedText.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: KandoColors.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}
