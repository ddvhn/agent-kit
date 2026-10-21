import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

/// The signed-out entry point; the sign-in flow is the app's first feature.
class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(context.strings.signIn)));
}
