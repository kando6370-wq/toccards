import 'package:flutter/material.dart';

import 'email_auth_pages.dart';

Future<void> showAuthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _AuthSheet(),
  );
}

class _AuthSheet extends StatefulWidget {
  const _AuthSheet();

  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  var _showEmail = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _showEmail
            ? const EmailAuthPages()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Continue with Google'),
                    enabled: false,
                    onTap: null,
                  ),
                  ListTile(
                    title: const Text('Continue with Apple'),
                    enabled: false,
                    onTap: null,
                  ),
                  ListTile(
                    title: const Text('Continue with Email'),
                    onTap: () => setState(() => _showEmail = true),
                  ),
                ],
              ),
      ),
    );
  }
}
