import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/app_router.dart';
import '../blocs/auth/auth_bloc.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/loading_button.dart';

/// Login screen for user authentication
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPasswordField = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onSendMagicLink() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(AuthMagicLinkRequested(
        email: _emailController.text.trim(),
      ));
    }
  }

  void _onPasswordLogin() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(AuthSignInRequested(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ));
    }
  }

  Future<void> _openGmail() async {
    // Try Gmail app first, then fallback to web
    final gmailAppUri = Uri.parse('googlegmail://');
    final gmailWebUri = Uri.parse('https://mail.google.com');
    
    try {
      if (await canLaunchUrl(gmailAppUri)) {
        await launchUrl(gmailAppUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(gmailWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Fallback to opening any email app
      final mailtoUri = Uri.parse('mailto:');
      if (await canLaunchUrl(mailtoUri)) {
        await launchUrl(mailtoUri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          AppRouter.navigateAndClear(context, AppRouter.home);
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        final isMagicLinkSent = state is AuthMagicLinkSent;

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  Theme.of(context).colorScheme.secondary.withOpacity(0.05),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: isMagicLinkSent
                      ? _buildMagicLinkSentView(context, state as AuthMagicLinkSent)
                      : _buildLoginForm(context, isLoading),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build the "Check your email" view after magic link is sent
  Widget _buildMagicLinkSentView(BuildContext context, AuthMagicLinkSent state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Email icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_rounded,
            size: 50,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 32),
        
        // Title
        Text(
          'Check Your Email',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        
        // Subtitle
        Text(
          'We sent a login link to:',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        
        // Email address
        Text(
          state.email,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        
        // Instructions
        Text(
          'Click the link in your email to sign in.\nMake sure to check your spam folder too!',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        
        // Go to Gmail button
        ElevatedButton.icon(
          onPressed: _openGmail,
          icon: const Icon(Icons.mail_outline),
          label: const Text('Open Gmail'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Open any email app button
        OutlinedButton.icon(
          onPressed: () async {
            final mailtoUri = Uri.parse('mailto:');
            if (await canLaunchUrl(mailtoUri)) {
              await launchUrl(mailtoUri);
            }
          },
          icon: const Icon(Icons.email_outlined),
          label: const Text('Open Email App'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 32),
        
        // Resend link / Back button
        TextButton(
          onPressed: () {
            context.read<AuthBloc>().add(AuthSignOutRequested());
          },
          child: Text(
            'Use a different email',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  /// Build the login form
  Widget _buildLoginForm(BuildContext context, bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo section
          _buildLogo(context),
          const SizedBox(height: 48),
          
          // Welcome text
          Text(
            'Welcome Back',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to continue tracking',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          // Login form card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                // Email field
                CustomTextField(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'Enter your work email',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  enabled: !isLoading,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Password field (shown when toggle is on)
                if (_showPasswordField) ...[
                  CustomTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    prefixIcon: Icons.lock_outlined,
                    obscureText: true,
                    enabled: !isLoading,
                    validator: (value) {
                      if (_showPasswordField && (value == null || value.isEmpty)) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Password Login button
                  LoadingButton(
                    onPressed: _onPasswordLogin,
                    isLoading: isLoading,
                    label: 'Login with Password',
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _showPasswordField = false),
                    child: const Text('Use Magic Link Instead'),
                  ),
                ] else ...[
                  // Magic Link button
                  LoadingButton(
                    onPressed: _onSendMagicLink,
                    isLoading: isLoading,
                    label: 'Send Login Link',
                  ),
                  const SizedBox(height: 16),
                  
                  // Divider with OR
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Password login option
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _showPasswordField = true),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Login with Password'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Info text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "We'll send you a secure login link",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.location_on_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'BenzMobiTraq',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
