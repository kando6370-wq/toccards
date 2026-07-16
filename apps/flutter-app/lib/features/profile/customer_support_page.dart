import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/validation/email.dart';

import '../../shared/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'feedback_repository.dart';
import 'profile_detail_scaffold.dart';

const feedbackSubmittedToastText = 'Feedback submitted. Thank you.';
const feedbackSubmitFailureText =
    'Unable to submit feedback. Please try again later.';
const feedbackMessageMaxLength = 1000;

const _typeOptions = ['Bug Report', 'Feature Request', 'Improvement', 'Other'];

const _functionOptions = [
  'Scan',
  'Search',
  'Collection',
  'Portfolio',
  'Wishlist',
  'Account',
  'Price Data',
  'Other',
];

class CustomerSupportPage extends ConsumerStatefulWidget {
  const CustomerSupportPage({super.key});

  @override
  ConsumerState<CustomerSupportPage> createState() =>
      _CustomerSupportPageState();
}

class _CustomerSupportPageState extends ConsumerState<CustomerSupportPage> {
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  final Set<String> _selectedTypes = {};
  final Set<String> _selectedFunctions = {};
  String? _emailError;
  String? _messageError;
  var _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(authControllerProvider).session;
    if (session?.isUser == true && session?.email != null) {
      _emailController.text = session!.email!;
    }
    _messageController.addListener(_validateMessageLength);
  }

  @override
  void dispose() {
    _messageController.removeListener(_validateMessageLength);
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTooLong = _messageController.text.length > feedbackMessageMaxLength;

    return ProfileDetailScaffold(
      child: ListView(
        key: const Key('customer-support-content-list'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const Text(
            'CONNECT WITH US',
            style: TextStyle(
              color: KandoColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Send Feedback',
            style: TextStyle(
              color: KandoColors.text,
              fontFamily: 'Fraunces',
              fontSize: 32,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Help us refine the Vault experience. '
            'Your insights drive our innovation.',
            style: TextStyle(
              color: KandoColors.mutedText,
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          _ChipSection(
            title: 'Feedback Type',
            options: _typeOptions,
            selectedValues: _selectedTypes,
            onToggle: _toggleType,
          ),
          const SizedBox(height: 24),
          _ChipSection(
            title: 'Affected Function',
            options: _functionOptions,
            selectedValues: _selectedFunctions,
            onToggle: _toggleFunction,
            iconForOption: _functionIcon,
          ),
          const SizedBox(height: 24),
          _FieldLabel('Email Address'),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('feedback-email-field'),
            controller: _emailController,
            decoration: InputDecoration(
              hintText: 'collector@vault.io',
              errorText: _emailError,
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          const _FieldLabel('Your Message', fontSize: 11),
          const SizedBox(height: 8),
          SizedBox(
            height: 178,
            child: TextFormField(
              key: const ValueKey('feedback-message-field'),
              controller: _messageController,
              decoration: InputDecoration(
                hintText: "Tell us what's on your mind...",
                errorText: _messageError,
              ),
              textAlignVertical: TextAlignVertical.top,
              expands: true,
              minLines: null,
              maxLines: null,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSubmitting || isTooLong ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: KandoColors.accent,
                foregroundColor: KandoColors.ink,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSubmitting ? 'SUBMITTING...' : 'SUBMIT FEEDBACK',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.send_outlined, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleType(String value) {
    setState(() {
      _toggleValue(_selectedTypes, value);
    });
  }

  void _toggleFunction(String value) {
    setState(() {
      _toggleValue(_selectedFunctions, value);
    });
  }

  void _toggleValue(Set<String> values, String value) {
    if (!values.add(value)) {
      values.remove(value);
    }
  }

  void _validateMessageLength() {
    final error = _messageController.text.length > feedbackMessageMaxLength
        ? 'Message must be 1000 characters or less.'
        : null;
    if (error != _messageError) {
      setState(() {
        _messageError = error;
      });
    }
  }

  Future<void> _submit() async {
    if (!_validate()) {
      return;
    }

    final session = ref.read(authControllerProvider).session;
    if (session == null) {
      showKandoToast(context, message: feedbackSubmitFailureText);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await ref
          .read(feedbackRepositoryProvider)
          .submit(
            session,
            FeedbackSubmission(
              email: normalizedEmail(_emailController.text),
              types: _selectedOrOther(_selectedTypes),
              functions: _selectedOrOther(_selectedFunctions),
              message: _messageController.text.trim(),
            ),
          );
      _clearForm();
      if (!mounted) {
        return;
      }
      showKandoToast(context, message: feedbackSubmittedToastText);
      context.go('/profile');
    } on Exception {
      if (mounted) {
        showKandoToast(context, message: feedbackSubmitFailureText);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  bool _validate() {
    final email = normalizedEmail(_emailController.text);
    final message = _messageController.text.trim();
    final emailError = emailValidationMessage(email);
    String? messageError;

    if (message.isEmpty) {
      messageError = 'Please enter your feedback.';
    } else if (message.length > feedbackMessageMaxLength) {
      messageError = 'Message must be 1000 characters or less.';
    }

    setState(() {
      _emailError = emailError;
      _messageError = messageError;
    });

    return emailError == null && messageError == null;
  }

  void _clearForm() {
    _messageController.clear();
    _selectedTypes.clear();
    _selectedFunctions.clear();
  }

  List<String> _selectedOrOther(Set<String> values) {
    if (values.isEmpty) {
      return const ['Other'];
    }
    return values.toList(growable: false);
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.fontSize = 14});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: KandoColors.mutedText,
        fontSize: fontSize,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _ChipSection extends StatelessWidget {
  const _ChipSection({
    required this.title,
    required this.options,
    required this.selectedValues,
    required this.onToggle,
    this.iconForOption,
  });

  final String title;
  final List<String> options;
  final Set<String> selectedValues;
  final ValueChanged<String> onToggle;
  final IconData? Function(String option)? iconForOption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(title),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final option in options)
              _PillChip(
                label: option,
                icon: iconForOption?.call(option),
                selected: selectedValues.contains(option),
                onTap: () => onToggle(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? KandoColors.accent.withValues(alpha: 0.2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(9999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: selected
                  ? KandoColors.accent.withValues(alpha: 0.5)
                  : KandoColors.border,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: KandoColors.accent.withValues(alpha: 0.2),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: KandoColors.text),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(color: KandoColors.text, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData? _functionIcon(String option) {
  return switch (option) {
    'Scan' => Icons.document_scanner_outlined,
    'Search' => Icons.search,
    'Collection' => Icons.collections_bookmark_outlined,
    'Portfolio' => Icons.account_balance_wallet_outlined,
    'Wishlist' => Icons.favorite_border,
    'Account' => Icons.person_outline,
    'Price Data' => Icons.show_chart,
    'Other' => Icons.more_horiz,
    _ => null,
  };
}
