import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'feedback_repository.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Support')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _ChipSection(
            title: 'Type',
            options: _typeOptions,
            selectedValues: _selectedTypes,
            onToggle: _toggleType,
          ),
          const SizedBox(height: 16),
          _ChipSection(
            title: 'Function',
            options: _functionOptions,
            selectedValues: _selectedFunctions,
            onToggle: _toggleFunction,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('feedback-email-field'),
            controller: _emailController,
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'your@email.com',
              errorText: _emailError,
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('feedback-message-field'),
            controller: _messageController,
            decoration: InputDecoration(
              labelText: 'Message',
              hintText: "Tell us what's on your mind...",
              errorText: _messageError,
            ),
            minLines: 4,
            maxLines: 8,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSubmitting || isTooLong ? null : _submit,
            child: Text(_isSubmitting ? 'Submitting...' : 'Submit Feedback'),
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

    setState(() {
      _isSubmitting = true;
    });

    try {
      await ref
          .read(feedbackRepositoryProvider)
          .submit(
            FeedbackSubmission(
              email: _emailController.text.trim().toLowerCase(),
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
    final email = _emailController.text.trim().toLowerCase();
    final message = _messageController.text.trim();
    String? emailError;
    String? messageError;

    if (email.isEmpty) {
      emailError = 'Please enter your email.';
    } else if (!email.contains('@') || !email.split('@').last.contains('.')) {
      emailError = 'Please enter a valid email address.';
    }

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

class _ChipSection extends StatelessWidget {
  const _ChipSection({
    required this.title,
    required this.options,
    required this.selectedValues,
    required this.onToggle,
  });

  final String title;
  final List<String> options;
  final Set<String> selectedValues;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(option),
                selected: selectedValues.contains(option),
                onSelected: (_) => onToggle(option),
              ),
          ],
        ),
      ],
    );
  }
}
