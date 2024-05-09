import 'package:beamer/beamer.dart';
import 'package:buddy/components/buttons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox(
        width: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Image.asset("assets/logo-with-shadow.png")),
                Button(
                  onPressed: () {
                    Beamer.of(context).beamToNamed("/welcome/login");
                  },
                  child: const Text("Log In"),
                ),
                const SizedBox(height: 16),
                TonalButton(
                  onPressed: () {},
                  child: const Text("Register"),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
