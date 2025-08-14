import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home_page.dart';
import 'batch_log_page.dart';
import 'inventory_page.dart';
import 'recipe_list_page.dart';
import 'settings_page.dart';
import 'tools_page.dart';
import 'shopping_list_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/plan_badge.dart';


class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<Widget> _pages = <Widget>[
    HomePage(),
    BatchLogPage(),
    InventoryPage(),
    RecipeListPage(),
    MorePage(),
  ];

  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: SvgPicture.asset(
          Theme.of(context).brightness == Brightness.dark
              ? 'assets/images/fermentacraft_logo_txt_darkmode.svg'
              : 'assets/images/fermentacraft_logo_txt_lightmode.svg',
          height: 36,
          semanticsLabel: 'FermentaCraft Logo',
          placeholderBuilder: (context) => const Text('FermentaCraft'),
        ),
          // ⬇️ Badge under the logo
  bottom: const PreferredSize(
    preferredSize: Size.fromHeight(32),
    child: Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: PlanBadge(), // Free → opens paywall; Premium → verified chip
    ),
  ),
      ),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
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
            icon: Icon(Icons.book_outlined),
            activeIcon: Icon(Icons.book),
            label: 'Recipes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            activeIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  void _showAboutAppDialog(BuildContext context) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final Uri bookUrl = Uri.parse('https://www.amazon.com/New-Cider-Makers-Handbook-Comprehensive/dp/1603584730');

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/images/carboy.svg',
                  height: 100,
                  semanticsLabel: 'FermentaCraft Carboy Logo',
                  placeholderBuilder: (context) => const CircularProgressIndicator(),
                ),
                const SizedBox(height: 16),
                Text('FermentaCraft', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  "Your Craft, Perfected.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 12),
                const Text(
                  "FermentaCraft helps you design, track, and manage your homebrewing projects with precision and ease.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text('Version ${packageInfo.version}', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      const TextSpan(text: "Much of the inspiration and technical information in this app comes from "),
                      TextSpan(
                        text: "The New Cider Maker's Handbook",
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => launchUrl(bookUrl, mode: LaunchMode.externalApplication),
                      ),
                      const TextSpan(text: " by Claude Jolicoeur. It is an indispensable resource for any aspiring cider maker."),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: const Text('View licenses'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (context) => const LicensePage(
                            applicationName: 'FermentaCraft',
                            applicationVersion: '1.0.0',
                            applicationLegalese: '© 2025 Brian Petry',
                          ),
                        );
                      },
                    ),
                    TextButton(child: const Text('Close'), onPressed: () => Navigator.of(context).pop()),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim().isNotEmpty == true ? user!.displayName! : user?.email ?? 'User';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ListView(
      children: [
        const SizedBox(height: 12),
        ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: Theme.of(context).colorScheme.secondary,
            child: Text(initials, style: const TextStyle(color: Colors.white)),
          ),
          title: Text(name),
          subtitle: const Text('Tap to log out'),
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Log out?'),
                content: const Text('Are you sure you want to sign out?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout')),
                ],
              ),
            );
            if (confirm == true) await FirebaseAuth.instance.signOut();
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.shopping_cart_outlined),
          title: const Text('Shopping List'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListPage())),
        ),
        ListTile(
          leading: const Icon(Icons.construction_outlined),
          title: const Text('Tools'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsPage())),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
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