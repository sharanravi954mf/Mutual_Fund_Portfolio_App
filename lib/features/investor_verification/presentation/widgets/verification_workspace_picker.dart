import 'package:flutter/material.dart';
import '../../models/verification_workspace.dart';

Future<String?> loadVerificationWorkspace(BuildContext context,
    Future<List<VerificationWorkspace>> Function() load) async {
  try {
    final workspaces = await load();
    if (!context.mounted) return null;
    return selectVerificationWorkspace(context, workspaces);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to load advisor workspaces. Please try again.'),
      ));
    }
    return null;
  }
}

Future<String?> selectVerificationWorkspace(
  BuildContext context,
  List<VerificationWorkspace> workspaces,
) async {
  if (workspaces.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Ask your advisor for a workspace invitation before requesting verification.'),
    ));
    return null;
  }
  if (workspaces.length == 1) return workspaces.single.id;
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Choose your advisor workspace'),
      children: [
        for (final workspace in workspaces)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, workspace.id),
            child: Text(workspace.name),
          ),
      ],
    ),
  );
}
