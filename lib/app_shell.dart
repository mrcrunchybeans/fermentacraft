// lib/app_shell.dart
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/utils/boxes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fermentacraft/auth_gate.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';
import 'home_page.dart';
import 'pages/batch_log_page.dart';
import 'pages/inventory_page.dart';
import 'pages/recipe_list_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';
import 'pages/shopping_list_page.dart';
import 'widgets/plan_badge.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'services/review_prompter.dart';
import 'services/local_mode_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Keep pages alive with IndexedStack
  static final List<Widget> _pages = <Widget>[
    const HomePage(),
    const RecipeListPage(),
    const BatchLogPage(),
    const InventoryPage(),
    const MorePage(),
  ];

  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: SvgPicture.asset(
          isDark
              ? 'assets/images/fermentacraft_logo_txt_darkmode.svg'
              : 'assets/images/fermentacraft_logo_txt_lightmode.svg',
          height: 36,
          semanticsLabel: 'FermentaCraft Logo',
          placeholderBuilder: (context) => const Text('FermentaCraft'),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(32),
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: PlanBadge(), // Free → opens paywall; Premium → verified chip
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _selectedIndex, children: _pages),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book_outlined),
            activeIcon: Icon(Icons.book),
            label: 'Recipes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.science_outlined),
            activeIcon: Icon(Icons.science),
            label: 'Batches',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            activeIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  Future<void> _postLogoutHiveCleanup() async {
    try {
      if (Hive.isBoxOpen(Boxes.batches)) {
        await Hive.box<BatchModel>(Boxes.batches).clear();
      }
      // Clear other boxes if you keep local state:
      // if (Hive.isBoxOpen(Boxes.inventory)) {
      //   await Hive.box<InventoryItem>(Boxes.inventory).clear();
      // }
      // if (Hive.isBoxOpen(Boxes.inventoryActions)) {
      //   await Hive.box<InventoryAction>(Boxes.inventoryActions).clear();
      // }
      // Don't close boxes - they should stay open for the app lifetime
      // await Hive.close(); // closes all boxes
    } catch (_) {
      // Swallow errors; user has already been navigated off the screen
    }
  }

  Future<void> _showAboutAppDialog(BuildContext context) async {
    // Fetch **before** showing the dialog; only use context if still mounted.
    final packageInfo = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/images/carboy.svg',
                    height: 100,
                    semanticsLabel: 'FermentaCraft Carboy Logo',
                    placeholderBuilder: (context) => const SizedBox(
                      height: 100,
                      width: 100,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'FermentaCraft',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Your Craft, Perfected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'FermentaCraft helps you design, track, and manage your homebrewing projects with precision and ease.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Version ${packageInfo.version}'
                    '${packageInfo.buildNumber.isNotEmpty ? '+${packageInfo.buildNumber}' : ''}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'Much of the inspiration and technical information in this app comes from The New Cider Maker’s Handbook by Claude Jolicoeur. It is an indispensable resource for any aspiring cider maker.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text("The New Cider Maker's Handbook"),
                      onPressed: () async {
                        final uri = Uri.parse(
                          'https://www.amazon.com/New-Cider-Makers-Handbook-Comprehensive/dp/1603584730',
                        );
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 12),
                    // Platform-specific review button
                    FilledButton.icon(
                      icon: const Icon(Icons.star_outline),
                      onPressed: () =>
                          ReviewPrompter.instance.openStoreReview(),
                      label: Text(defaultTargetPlatform == TargetPlatform.iOS
                          ? 'Rate on App Store'
                          : 'Rate on Play Store'),
                    ),
                    const SizedBox(height: 8),
                    // Feedback button (works on all platforms)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.mail_outline),
                      onPressed: () =>
                          ReviewPrompter.instance.sendFeedback(),
                      label: const Text('Send Feedback'),
                    ),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        child: const Text('View licenses'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          showLicensePage(
                            context: ctx,
                            applicationName: 'FermentaCraft',
                            applicationVersion:
                                '${packageInfo.version}${packageInfo.buildNumber.isNotEmpty ? '+${packageInfo.buildNumber}' : ''}',
                            applicationLegalese:
                                '© ${DateTime.now().year} Brian Petry',
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!
        : (user?.email ?? 'User');
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child:
                  Text(initials, style: const TextStyle(color: Colors.white)),
            ),
            title: Text(name),
            subtitle: const Text('Tap to log out'),
            onTap: () async {
              // Capture anything derived from context BEFORE the first await
              final navigator = Navigator.of(context);

              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogCtx, true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                // First, stop sync service to prevent race conditions
                try {
                  FirestoreSyncService.instance.disable();
                  await Future.delayed(const Duration(
                      milliseconds: 500)); // Give sync time to stop
                } catch (_) {
                  // ignore sync stop errors
                }

                // Ensure Local Mode is turned off so AuthGate shows LoginPage
                try {
                  await LocalModeService.instance.clearLocalOnly();
                } catch (_) {/* ignore */}

                // Sign out (no context usage here)
                try {
                  await FirebaseAuth.instance.signOut();
                } catch (_) {
                  // ignore; proceed regardless
                }

                // Wait a bit more for auth state to propagate
                await Future.delayed(const Duration(milliseconds: 500));

                // Navigate away using the captured navigator (no direct context)
                navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (_) => false,
                );

                // Fire-and-forget cleanup with delay to ensure sync has stopped
                // ignore: discarded_futures
                Future.delayed(
                    const Duration(seconds: 1), () => _postLogoutHiveCleanup());
              }
            }),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.shopping_cart_outlined),
          title: const Text('Shopping List'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ShoppingListPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.construction_outlined),
          title: const Text('Tools'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ToolsPage()),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About'),
          onTap: () => _showAboutAppDialog(context),
        ),
      ],
    );
  }
}
