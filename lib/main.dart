import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'providers.dart';
import 'notification_service.dart';
import 'views/notes_view.dart';
import 'views/expenses_view.dart';
import 'views/links_view.dart';
import 'views/tables_view.dart';
import 'views/cards_view.dart';
import 'views/recycle_bin_view.dart';
import 'views/note_editor.dart';
import 'views/reminders_view.dart';
import 'views/bills_view.dart';
import 'main_helpers.dart';
import 'dialogs/link_dialog.dart';
import 'dialogs/expense_dialog.dart';
import 'dialogs/bill_dialog.dart';
import 'profiles/providers/theme_provider.dart';
import 'profiles/ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(const ProviderScope(child: MyNotesApp()));
}

class MyNotesApp extends ConsumerWidget {
  const MyNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'My Notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        textTheme: GoogleFonts.lexendTextTheme(AppTheme.lightTheme.textTheme),
      ),
      darkTheme: AppTheme.darkTheme.copyWith(
        textTheme: GoogleFonts.lexendTextTheme(AppTheme.darkTheme.textTheme),
      ),
      themeMode: themeMode,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late PageController _pageController;
  late AnimationController _syncAnimationController;
  bool _isSyncing = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  late StreamSubscription _intentDataStreamSubscription;
  bool _isAppUnlocked = false;
  bool _hasPurgedTrash = false;


  void _triggerAppLaunchUnlock() {
    verifyPasscode(context, ref, onSuccess: () {
      setState(() {
        _isAppUnlocked = true;
      });
    });
  }

  void _loadAppLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('biometric_app_lock_enabled') ?? false;
    if (!enabled) {
      setState(() {
        _isAppUnlocked = true;
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          _triggerAppLaunchUnlock();
        }
      });
    });
  }

  Future<void> _checkBackupReminder() async {
    final path = ref.read(vaultPathProvider).value;
    if (path == null || path.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastSyncMs = prefs.getInt('last_sync_timestamp_ms');
    final now = DateTime.now();
    
    bool shouldWarn = false;
    int daysSince = 7;
    
    if (lastSyncMs == null) {
      shouldWarn = true;
    } else {
      final lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
      daysSince = now.difference(lastSync).inDays;
      if (daysSince >= 7) {
        shouldWarn = true;
      }
    }
    
    if (shouldWarn && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lastSyncMs == null
                      ? 'No backup performed yet. Sync now to keep your data safe.'
                      : 'No backup in $daysSince days. Sync now to keep your data safe.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFB45309),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Sync',
            textColor: Colors.white,
            onPressed: () => verifyPasscode(context, ref, onSuccess: _handleSyncAnimation),
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _syncAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    
    // For sharing or opening links from outside the app while the app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) {
        // In newer versions, text/urls are also returned in the media stream
        _handleSharedText(value.first.path);
      }
    }, onError: (err) => print("getMediaStream error: $err"));

    // For sharing or opening links from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        _handleSharedText(value.first.path);
        ReceiveSharingIntent.instance.reset(); // Clear the initial intent
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBackupReminder();
    });

    _loadAppLockState();
  }

  void _handleSharedText(String text) {
    String category = 'General';
    final lowerText = text.toLowerCase();
    if (lowerText.contains('youtube.com') || lowerText.contains('youtu.be')) {
      category = 'YouTube';
    } else if (lowerText.contains('instagram.com')) {
      category = 'Instagram';
    } else if (lowerText.contains('facebook.com') || lowerText.contains('twitter.com') || lowerText.contains('x.com')) {
      category = 'Social';
    } else if (lowerText.contains('maps.google.com') || lowerText.contains('goo.gl/maps')) {
      category = 'Maps';
    }

    // Try to extract URL and title from the shared text
    final urlRegex = RegExp(r'(https?://[^\s]+)');
    final match = urlRegex.firstMatch(text);
    String title = 'Shared Link';
    String url = text;
    if (match != null) {
      url = match.group(0) ?? text;
      String remaining = text.replaceFirst(url, '').trim();
      // Clean up common noise and symbols from the remaining text
      remaining = remaining.replaceAll(RegExp(r'^[\s\-:|]+|[\s\-:|]+$'), '').trim();
      if (remaining.isNotEmpty) {
        title = remaining;
      }
    }

    setState(() => _currentIndex = 2);
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => LinkDialog(
        initialTitle: title,
        initialUrl: url,
        initialCategory: category,
        isSharing: true,
      ),
    );
  }

  // _checkVaultStatus is replaced by the Setup Screen in build()

  @override
  void dispose() {
    _pageController.dispose();
    _syncAnimationController.dispose();
    _searchController.dispose();
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(localSyncingProvider, (previous, next) {
      if (next) {
        if (!_isSyncing && mounted) {
          setState(() => _isSyncing = true);
          _syncAnimationController.repeat();
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Syncing...'),
              duration: Duration(milliseconds: 800),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (_isSyncing && mounted) {
          setState(() => _isSyncing = false);
          _syncAnimationController.stop();
          _syncAnimationController.reset();
        }
      }
    });

    ref.listen<SyncStatus>(syncProvider, (previous, next) {
      if (next == SyncStatus.syncing) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Syncing with Google Drive...'), duration: Duration(seconds: 10)),
        );
      } else if (next == SyncStatus.success) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setInt('last_sync_timestamp_ms', DateTime.now().millisecondsSinceEpoch);
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync successful!'), backgroundColor: Colors.green),
        );
      } else if (next == SyncStatus.error) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync failed. Please check connection or configuration.'), backgroundColor: Colors.red),
        );
      } else if (next == SyncStatus.idle && previous == SyncStatus.syncing) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync canceled or failed to sign in.'), backgroundColor: Colors.orange),
        );
      }
    });

    final vaultPath = ref.watch(vaultPathProvider);

    if (vaultPath.value != null && !_hasPurgedTrash) {
      _hasPurgedTrash = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(vaultServiceProvider).purgeOldDeletedItems().then((_) {
          ref.invalidate(deletedNotesProvider);
          ref.invalidate(deletedExpensesProvider);
          ref.invalidate(deletedLinksProvider);
        });
      });
    }

    if (vaultPath.isLoading) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    if (vaultPath.value == null || vaultPath.value!.isEmpty) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_special, color: Color(0xFF1D63D2), size: 80),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to My Notes',
                    style: GoogleFonts.lexend(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A vault folder is required before you can save any data. Please pick a folder on your device to store your notes, links, tables and more.',
                    style: GoogleFonts.lexend(fontSize: 15, color: Colors.grey[400]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You cannot use the app until a folder is selected.',
                    style: GoogleFonts.lexend(fontSize: 13, color: Colors.orange[300], fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  FilledButton.icon(
                    onPressed: _pickVaultFolder,
                    icon: const Icon(Icons.create_new_folder),
                    label: const Text('Pick Vault Folder'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1D63D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_isAppUnlocked) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, color: Color(0xFF1D63D2), size: 80),
              const SizedBox(height: 24),
              Text(
                'My Notes is Locked',
                style: GoogleFonts.lexend(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Unlock to access your vaults',
                style: GoogleFonts.lexend(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: _triggerAppLaunchUnlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Unlock Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D63D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final activeReminders = ref.watch(activeRemindersProvider);
    final selectedNotes = ref.watch(selectedNotesProvider);
    final selectedExpenses = ref.watch(selectedExpensesProvider);
    final selectedLinks = ref.watch(selectedLinksProvider);
    final selectedReminders = ref.watch(selectedRemindersProvider);
    final isEditingTable = ref.watch(editingTableProvider) != null;
    final isSelectionMode = selectedNotes.isNotEmpty || selectedExpenses.isNotEmpty || selectedLinks.isNotEmpty || selectedReminders.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            ref.read(searchQueryProvider.notifier).state = '';
          });
          return;
        }
        if (isSelectionMode) {
          ref.read(selectedNotesProvider.notifier).clear();
          ref.read(selectedExpensesProvider.notifier).clear();
          ref.read(selectedLinksProvider.notifier).clear();
          ref.read(selectedRemindersProvider.notifier).clear();
          return;
        }
        if (isEditingTable) {
          ref.read(editingTableProvider.notifier).state = null;
          return;
        }
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
            if (_pageController.hasClients) _pageController.jumpToPage(0);
          });
          return;
        }
        final bool? shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App?'),
            content: const Text('Do you want to exit My Notes?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
            ],
          ),
        );
        if (shouldPop == true) SystemNavigator.pop();
      },
      child: Scaffold(
        drawer: isEditingTable ? null : _buildDrawer(vaultPath),
        appBar: isEditingTable ? null : _buildAppBar(isSelectionMode, selectedNotes.length, selectedExpenses.length, vaultPath),
        body: _buildBody(),
        bottomNavigationBar: (isSelectionMode || isEditingTable || (_currentIndex > 3 && _currentIndex != 7))
            ? null 
            : NavigationBar(
                selectedIndex: _currentIndex == 7 ? 4 : _currentIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _currentIndex = index == 4 ? 7 : index;
                    _isSearching = false;
                    _searchController.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                    // Auto-lock any revealed card when leaving Cards tab
                    ref.read(revealedCardIdProvider.notifier).setRevealed(null);
                  });
                },
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.notes_outlined), selectedIcon: Icon(Icons.notes), label: 'Notes'),
                  NavigationDestination(icon: Icon(Icons.wallet_outlined), selectedIcon: Icon(Icons.wallet), label: 'Expenses'),
                  NavigationDestination(icon: Icon(Icons.link_outlined), selectedIcon: Icon(Icons.link), label: 'Links'),
                  NavigationDestination(icon: Icon(Icons.table_chart_outlined), selectedIcon: Icon(Icons.table_chart), label: 'Tables'),
                  NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Bills'),
                ],
              ),
        floatingActionButton: isSelectionMode || isEditingTable || _currentIndex == 4
            ? null 
            : FloatingActionButton(
                onPressed: _handleFabPress,
                elevation: 4,
                backgroundColor: const Color(0xFF1D63D2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.add, size: 30),
              ),
      ),
    );
  }

  Widget _buildDrawer(AsyncValue<String?> vaultPath) {
    final sortOrder = ref.watch(sortOrderProvider);
    final fontSize = ref.watch(fontSizeProvider);

    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 32,
              bottom: 32,
            ),
            decoration: const BoxDecoration(color: Color(0xFF2A5EAF)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text(
                  'My Notes',
                  style: GoogleFonts.lexend(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                 Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      // Dark Mode Card
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                            return InkWell(
                              onTap: () {
                                ref.read(themeModeProvider.notifier).setThemeMode(
                                  isDark ? ThemeMode.light : ThemeMode.dark
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.blue.withOpacity(0.08) 
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.blue.withOpacity(0.15) 
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(
                                          isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                                          color: const Color(0xFFF59E0B),
                                          size: 20,
                                        ),
                                        Transform.scale(
                                          scale: 0.75,
                                          child: Switch(
                                            value: isDark,
                                            activeThumbColor: const Color(0xFF2A5EAF),
                                            onChanged: (val) {
                                              ref.read(themeModeProvider.notifier).setThemeMode(
                                                val ? ThemeMode.dark : ThemeMode.light
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Dark Mode',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // App Lock Card
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final appLockEnabled = ref.watch(biometricLockEnabledProvider);
                            final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                            return InkWell(
                              onTap: () {
                                ref.read(biometricLockEnabledProvider.notifier).state = !appLockEnabled;
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.blue.withOpacity(0.08) 
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.blue.withOpacity(0.15) 
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Icon(
                                          Icons.fingerprint,
                                          color: Color(0xFF6366F1),
                                          size: 20,
                                        ),
                                        Transform.scale(
                                          scale: 0.75,
                                          child: Switch(
                                            value: appLockEnabled,
                                            activeThumbColor: const Color(0xFF2A5EAF),
                                            onChanged: (val) {
                                              ref.read(biometricLockEnabledProvider.notifier).state = val;
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'App Lock',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                 Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      // Sort By Card
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final sortOrder = ref.watch(sortOrderProvider);
                            final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                            
                            String sortLabel = 'Date (Newest)';
                            if (sortOrder == NoteSortOrder.dateOldest) {
                              sortLabel = 'Date (Oldest)';
                            } else if (sortOrder == NoteSortOrder.atoz) sortLabel = 'Title (A-Z)';
                            else if (sortOrder == NoteSortOrder.ztoa) sortLabel = 'Title (Z-A)';

                            return InkWell(
                              onTap: () {
                                _showSortBottomSheet(context, ref);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.blue.withOpacity(0.08) 
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.blue.withOpacity(0.15) 
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Icon(
                                          Icons.sort,
                                          color: Color(0xFF0EA5E9),
                                          size: 20,
                                        ),
                                        Icon(
                                          Icons.arrow_drop_down,
                                          color: isDark ? Colors.white54 : Colors.black54,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Sort By',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      sortLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white38 : Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Font Size Card
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final fontSize = ref.watch(fontSizeProvider);
                            final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                            
                            String fontLabel = 'Medium';
                            if (fontSize == 12) {
                              fontLabel = 'Small';
                            } else if (fontSize == 16) fontLabel = 'Large';
                            else if (fontSize == 18) fontLabel = 'Extra Large';

                            return InkWell(
                              onTap: () {
                                _showFontBottomSheet(context, ref);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.blue.withOpacity(0.08) 
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.blue.withOpacity(0.15) 
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Icon(
                                          Icons.format_size,
                                          color: Color(0xFF14B8A6),
                                          size: 20,
                                        ),
                                        Icon(
                                          Icons.arrow_drop_down,
                                          color: isDark ? Colors.white54 : Colors.black54,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Font Size',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      fontLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white38 : Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                 Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      // Backup to Cloud Card
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final syncStatus = ref.watch(syncProvider);
                            final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                            final isSyncing = syncStatus == SyncStatus.syncing;
                            
                            return InkWell(
                              onTap: isSyncing ? null : () {
                                Navigator.pop(context);
                                verifyPasscode(context, ref, onSuccess: () {
                                  _showBackupSelectionDialog();
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Opacity(
                                opacity: isSyncing ? 0.6 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDark 
                                        ? Colors.blue.withOpacity(0.08) 
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark 
                                          ? Colors.blue.withOpacity(0.15) 
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Icon(
                                            isSyncing ? Icons.cloud_sync : Icons.cloud_upload_outlined,
                                            color: const Color(0xFF2563EB),
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Backup',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isSyncing ? 'Syncing...' : 'Save to Drive',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white38 : Colors.black54,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Restore from Cloud Card
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final syncStatus = ref.watch(syncProvider);
                            final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                            final isSyncing = syncStatus == SyncStatus.syncing;
                            
                            return InkWell(
                              onTap: isSyncing ? null : () {
                                Navigator.pop(context);
                                verifyPasscode(context, ref, onSuccess: () {
                                  _showRestoreConfirm();
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Opacity(
                                opacity: isSyncing ? 0.6 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDark 
                                        ? Colors.blue.withOpacity(0.08) 
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark 
                                          ? Colors.blue.withOpacity(0.15) 
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Icon(
                                            Icons.cloud_download_outlined,
                                            color: Color(0xFF22C55E),
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Restore',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isSyncing ? 'Syncing...' : 'Get from Drive',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white38 : Colors.black54,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                 Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      // Reminders Card
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                            return InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                setState(() => _currentIndex = 5);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.blue.withOpacity(0.08) 
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.blue.withOpacity(0.15) 
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(
                                          Icons.notifications_active_outlined,
                                          color: Color(0xFFF59E0B),
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Reminders',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Scheduled alerts',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white38 : Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Secure Cards Card
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
                            return InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                setState(() => _currentIndex = 6);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.blue.withOpacity(0.08) 
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.blue.withOpacity(0.15) 
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(
                                          Icons.credit_card,
                                          color: Color(0xFF7C3AED),
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Secure Cards',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Protected data',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white38 : Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                  leading: const Icon(Icons.folder_outlined, color: Color(0xFFF59E0B), size: 22),
                  title: const Text('Pick Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickVaultFolder();
                  },
                ),
                ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                  leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 22),
                  title: const Text('Recycle Bin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _currentIndex = 4);
                  },
                ),
                ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                  leading: const Icon(Icons.security, color: Color(0xFF8B5CF6), size: 22),
                  title: const Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    _showSecuritySettings(context, ref);
                  },
                ),
                ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                  leading: const Icon(Icons.file_download_outlined, color: Color(0xFF10B981), size: 22),
                  title: const Text('Import Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    verifyPasscode(context, ref, onSuccess: () {
                      _importData();
                    });
                  },
                ),
                ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
                  leading: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
                  title: const Text('Sign Out Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(context);
                    _showSignOutConfirm();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncTile() {
    final syncStatus = ref.watch(syncProvider);
    
    return Column(
      children: [
        ListTile(
          leading: Icon(
            syncStatus == SyncStatus.syncing ? Icons.cloud_sync : Icons.cloud_upload_outlined,
            color: syncStatus == SyncStatus.error ? Colors.red : const Color(0xFF1D63D2),
          ),
          title: const Text('Backup to Cloud'),
          subtitle: Text(
            syncStatus == SyncStatus.syncing 
                ? 'Syncing...' 
                : (syncStatus == SyncStatus.error ? 'Sync Failed' : (syncStatus == SyncStatus.success ? 'Sync Success!' : 'Save data to Google Drive')),
            style: TextStyle(color: syncStatus == SyncStatus.error ? Colors.red : (syncStatus == SyncStatus.success ? Colors.green : Colors.grey)),
          ),
          onTap: syncStatus == SyncStatus.syncing ? null : () {
            verifyPasscode(context, ref, onSuccess: _showBackupSelectionDialog);
          },
        ),
        ListTile(
          leading: const Icon(Icons.cloud_download_outlined, color: Color(0xFF1D63D2)),
          title: const Text('Restore from Cloud'),
          subtitle: const Text('Download data from Google Drive'),
          onTap: syncStatus == SyncStatus.syncing ? null : () {
            verifyPasscode(context, ref, onSuccess: _showRestoreConfirm);
          },
        ),
      ],
    );
  }

  void _showBackupSelectionDialog() {
    final List<String> backupFiles = [
      'notes_data.json',
      'expenses_data.json',
      'links_data.json',
      'tables_data.json',
      'bills_data.json',
    ];
    
    final Map<String, Map<String, dynamic>> fileInfo = {
      'notes_data.json': {'name': 'Notes', 'icon': Icons.description, 'color': Colors.amber},
      'expenses_data.json': {'name': 'Expenses', 'icon': Icons.account_balance_wallet, 'color': Colors.green},
      'links_data.json': {'name': 'Links', 'icon': Icons.link, 'color': Colors.blue},
      'tables_data.json': {'name': 'Tables & Formulas', 'icon': Icons.table_chart, 'color': Colors.teal},
      'bills_data.json': {'name': 'Bills & Loans', 'icon': Icons.receipt_long, 'color': Colors.orange},
    };
    
    Set<String> selectedFiles = Set.from(backupFiles);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select items to Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: backupFiles.map((file) {
              final info = fileInfo[file] ?? {'name': file, 'icon': Icons.insert_drive_file, 'color': Colors.grey};
              return CheckboxListTile(
                title: Row(
                  children: [
                    Icon(info['icon'] as IconData, color: info['color'] as Color, size: 20),
                    const SizedBox(width: 10),
                    Text(info['name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
                value: selectedFiles.contains(file),
                onChanged: (bool? value) {
                  setDialogState(() {
                    if (value == true) {
                      selectedFiles.add(file);
                    } else {
                      selectedFiles.remove(file);
                    }
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selectedFiles.isEmpty ? null : () {
                Navigator.pop(context);
                ref.read(syncProvider.notifier).syncWithDrive(selectedFiles: selectedFiles.toList());
              },
              child: const Text('Backup'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRestoreConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from Cloud?'),
        content: const Text('This will OVERWRITE your current local data with the backup from Google Drive. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(syncProvider.notifier).downloadFromDrive();
            }, 
            child: const Text('Restore', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  void _showSignOutConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('Do you want to sign out from your Google account? You will be asked to choose an account again next time you backup or restore.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(syncProvider.notifier).signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed out from Google Drive')));
              }
            }, 
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSortRadio(NoteSortOrder order, String label) {
    return RadioListTile<NoteSortOrder>(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: order,
      groupValue: ref.watch(sortOrderProvider),
      onChanged: (val) {
        if (val != null) ref.read(sortOrderProvider.notifier).state = val;
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
    );
  }



  Widget _buildFontRadio(double size, String label) {
    return RadioListTile<double>(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: size,
      groupValue: ref.watch(fontSizeProvider),
      onChanged: (val) {
        if (val != null) ref.read(fontSizeProvider.notifier).state = val;
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
    );
  }

  void _showSortBottomSheet(BuildContext outerContext, WidgetRef outerRef) {
    showModalBottomSheet(
      context: outerContext,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final currentSort = outerRef.watch(sortOrderProvider);
        final isDark = outerRef.watch(themeModeProvider) == ThemeMode.dark;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Sort Order',
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1D63D2),
                ),
              ),
              const SizedBox(height: 12),
              _buildSortRadioItem(outerRef, NoteSortOrder.dateNewest, 'Date (Newest)', currentSort),
              _buildSortRadioItem(outerRef, NoteSortOrder.dateOldest, 'Date (Oldest)', currentSort),
              _buildSortRadioItem(outerRef, NoteSortOrder.atoz, 'Title (A-Z)', currentSort),
              _buildSortRadioItem(outerRef, NoteSortOrder.ztoa, 'Title (Z-A)', currentSort),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  outerRef.read(lockProvider.notifier).setLock('1851421');
                  Navigator.pop(sheetContext);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  alignment: Alignment.center,
                  child: Text(
                    'reset p',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                ),
              ),
              const Divider(),
              Consumer(
                builder: (consumerContext, innerRef, _) {
                  final isLockEnabled = innerRef.watch(securityLockEnabledProvider);
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Enable Security Lock',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Bypass PIN/fingerprint prompts when disabled',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    value: isLockEnabled,
                    activeThumbColor: const Color(0xFF1D63D2),
                    onChanged: (val) {
                      if (!val) {
                        verifyPasscode(consumerContext, outerRef, onSuccess: () {
                          outerRef.read(securityLockEnabledProvider.notifier).state = false;
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(outerContext).showSnackBar(
                            const SnackBar(content: Text('Security lock disabled globally')),
                          );
                        });
                      } else {
                        outerRef.read(securityLockEnabledProvider.notifier).state = true;
                        ScaffoldMessenger.of(outerContext).showSnackBar(
                          const SnackBar(content: Text('Security lock enabled globally')),
                        );
                      }
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortRadioItem(WidgetRef ref, NoteSortOrder value, String label, NoteSortOrder groupValue) {
    return ListTile(
      title: Text(label),
      leading: Radio<NoteSortOrder>(
        value: value,
        groupValue: groupValue,
        activeColor: const Color(0xFF1D63D2),
        onChanged: (val) {
          if (val != null) {
            ref.read(sortOrderProvider.notifier).state = val;
            Navigator.pop(context);
          }
        },
      ),
      onTap: () {
        ref.read(sortOrderProvider.notifier).state = value;
        Navigator.pop(context);
      },
    );
  }

  void _showFontBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final currentFont = ref.watch(fontSizeProvider);
        final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Font Size',
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1D63D2),
                ),
              ),
              const SizedBox(height: 12),
              _buildFontRadioItem(ref, 12, 'Small', currentFont),
              _buildFontRadioItem(ref, 14, 'Medium', currentFont),
              _buildFontRadioItem(ref, 16, 'Large', currentFont),
              _buildFontRadioItem(ref, 18, 'Extra Large', currentFont),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFontRadioItem(WidgetRef ref, double value, String label, double groupValue) {
    return ListTile(
      title: Text(label),
      leading: Radio<double>(
        value: value,
        groupValue: groupValue,
        activeColor: const Color(0xFF1D63D2),
        onChanged: (val) {
          if (val != null) {
            ref.read(fontSizeProvider.notifier).state = val;
            Navigator.pop(context);
          }
        },
      ),
      onTap: () {
        ref.read(fontSizeProvider.notifier).state = value;
        Navigator.pop(context);
      },
    );
  }

  PreferredSizeWidget _buildAppBar(bool selectionMode, int noteCount, int expCount, AsyncValue<String?> vaultPath) {
    if (selectionMode) {
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () {
          ref.read(selectedNotesProvider.notifier).clear();
          ref.read(selectedExpensesProvider.notifier).clear();
          ref.read(selectedLinksProvider.notifier).clear();
          ref.read(selectedRemindersProvider.notifier).clear();
        }),
        title: Text(() {
          if (_currentIndex == 0) return '$noteCount selected';
          if (_currentIndex == 1) return '$expCount selected';
          if (_currentIndex == 5) return '${ref.watch(selectedRemindersProvider).length} selected';
          return '${ref.watch(selectedLinksProvider).length} selected';
        }()),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: _currentIndex == 0 
                ? _selectAllNotes 
                : (_currentIndex == 1 
                    ? _selectAllExpenses 
                    : (_currentIndex == 5 
                        ? _selectAllReminders 
                        : _selectAllLinks)),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _currentIndex == 0 
                ? _deleteSelectedNotes 
                : (_currentIndex == 1 
                    ? _deleteSelectedExpenses 
                    : (_currentIndex == 5 
                        ? _deleteSelectedReminders 
                        : _deleteSelectedLinks)),
          ),
          if (_currentIndex != 5)
            IconButton(
              icon: const Icon(Icons.drive_file_move),
              onPressed: _currentIndex == 0 
                  ? _moveSelectedNotes 
                  : (_currentIndex == 1 
                      ? _moveSelectedExpenses 
                      : _moveSelectedLinks),
            ),
        ],
      );
    }

    return AppBar(
      titleSpacing: 0,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF1D63D2)),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search Notes, Expenses, Links, Reminders...',
                border: InputBorder.none
              ),
              onChanged: (value) {
                setState(() {});
                ref.read(searchQueryProvider.notifier).state = value;
              },
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    text: _currentIndex == 1 ? 'My Expenses' : (_currentIndex == 2 ? 'My Links' : (_currentIndex == 3 ? 'My Tables' : (_currentIndex == 4 ? 'Recycle Bin' : (_currentIndex == 5 ? 'Reminders' : (_currentIndex == 6 ? 'Secure Cards' : (_currentIndex == 7 ? 'Bills & Subscriptions' : 'My Notes')))))),
                    style: GoogleFonts.lexend(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1D63D2)),
                    children: [
                      if (_currentIndex == 0) ...[
                        TextSpan(
                          text: '      |      Vasu ',
                          style: GoogleFonts.lexend(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1D63D2).withOpacity(0.95)),
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: const Text('❤️', style: TextStyle(fontSize: 11))
                              .animate(onPlay: (controller) => controller.repeat(reverse: true))
                              .scale(begin: const Offset(1, 1), end: const Offset(1.25, 1.25), duration: 600.ms, curve: Curves.easeInOut),
                        ),
                        TextSpan(
                          text: ' Likki',
                          style: GoogleFonts.lexend(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1D63D2).withOpacity(0.95)),
                        ),
                      ],
                    ],
                  ),
                ),
                const _LiveClock(),
              ],
            ),
      actions: [
        if (_isSearching)
          IconButton(icon: const Icon(Icons.close), onPressed: () {
            setState(() => _isSearching = false);
            _searchController.clear();
            ref.read(searchQueryProvider.notifier).state = '';
          })
        else ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_currentIndex != 5 && _currentIndex != 6)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: RotationTransition(
                    turns: _syncAnimationController,
                    child: Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
                  ),
                  onPressed: () {
                    if (!_isSyncing) {
                      verifyPasscode(context, ref, onSuccess: _handleSyncAnimation);
                    }
                  },
                  tooltip: _isSyncing ? 'Syncing...' : 'Sync Vault',
                ),
              if (_currentIndex != 4 && _currentIndex != 5 && _currentIndex != 6)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
                  onPressed: () {
                    setState(() => _isSearching = true);
                  },
                  tooltip: 'Search',
                ),
            ],
          ),
          
          if (_currentIndex == 4 || _currentIndex == 5 || _currentIndex == 6)
            IconButton(
              icon: Icon(Icons.close, color: Theme.of(context).colorScheme.primary),
              onPressed: () {
                setState(() {
                  _currentIndex = 0;
                  _isSearching = false;
                  _searchController.clear();
                  ref.read(searchQueryProvider.notifier).state = '';
                  // Auto-lock any revealed card when closing Cards view
                  ref.read(revealedCardIdProvider.notifier).setRevealed(null);
                });
              },
            ),
        ],
      ],
      bottom: _buildAppBarReminderBottom(ref),
    );
  }

  void _showSecuritySettings(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => SecuritySettingsDialog(),
    );
  }

  void _handleMenuSelection(String value) {
    if (value == 'recycle') setState(() => _currentIndex = 4);
    if (value == 'manage_link_cats') manageLinkCategoriesDialog(context, ref);
    if (value == 'vault') _pickVaultFolder();
    if (value == 'import') _importData();
    if (value.startsWith('font_')) {
      final size = double.parse(value.substring(5));
      ref.read(fontSizeProvider.notifier).state = size;
    }
    if (value.startsWith('sort_')) {
      final order = NoteSortOrder.values.firstWhere((e) => e.toString() == value.substring(5));
      ref.read(sortOrderProvider.notifier).state = order;
    }
  }

  PreferredSizeWidget? _buildAppBarReminderBottom(WidgetRef ref) {
    final activeReminders = ref.watch(activeRemindersProvider);
    if (activeReminders.isEmpty) return null;

    return PreferredSize(
      preferredSize: const Size.fromHeight(40),
      child: Container(
        color: Colors.red.shade900,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reminder: ${activeReminders.first.title}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (activeReminders.length > 1)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+${activeReminders.length - 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            InkWell(
              onTap: () {
                setState(() {
                  _currentIndex = 5;
                });
              },
              child: const Text(
                'VIEW',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: () {
                final notifier = ref.read(remindersProvider.notifier);
                final first = activeReminders.first;
                notifier.updateReminder(first.copyWith(isDismissed: true));
              },
              child: const Text(
                'DISMISS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching && _searchController.text.trim().isNotEmpty) {
      return _buildGlobalSearchResults(_searchController.text.trim().toLowerCase());
    }
    if (_currentIndex == 4) return const RecycleBinView();
    if (_currentIndex == 5) return const RemindersView();
    if (_currentIndex == 6) return const CardsView();
    if (_currentIndex == 7) return const BillsView();
    return IndexedStack(index: _currentIndex, children: const [NotesView(), ExpensesView(), LinksView(), TablesView()]);
  }

  Widget _buildGlobalSearchResults(String query) {
    final notes = ref.read(notesProvider).where((n) =>
        n.title.toLowerCase().contains(query) || n.content.toLowerCase().contains(query)).toList();
    final expenses = ref.read(expensesProvider).where((e) =>
        e.title.toLowerCase().contains(query) || (e.note?.toLowerCase().contains(query) ?? false)).toList();
    final links = ref.read(linkItemsProvider).where((l) =>
        l.title.toLowerCase().contains(query) || l.url.toLowerCase().contains(query)).toList();
    final reminders = ref.read(remindersProvider).where((r) =>
        r.title.toLowerCase().contains(query) || r.description.toLowerCase().contains(query)).toList();

    final totalResults = notes.length + expenses.length + links.length + reminders.length;

    if (totalResults == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text('No results for "$query"', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('$totalResults result${totalResults == 1 ? '' : 's'} for "$query"',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (notes.isNotEmpty) ...[
          _globalSearchSection('Notes', Icons.notes, const Color(0xFF6366F1)),
          ...notes.map((n) => _globalSearchTile(
            icon: Icons.notes_outlined, color: const Color(0xFF6366F1),
            title: n.title.isEmpty ? 'Untitled' : n.title,
            subtitle: n.content.replaceAll('\n', ' '),
            badge: 'NOTE',
            onTap: () {
              setState(() { _isSearching = false; });
              Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditor(note: n, isNew: false)));
            },
          )),
          const SizedBox(height: 8),
        ],
        if (expenses.isNotEmpty) ...[
          _globalSearchSection('Expenses', Icons.wallet, const Color(0xFF10B981)),
          ...expenses.map((e) => _globalSearchTile(
            icon: Icons.receipt_outlined, color: const Color(0xFF10B981),
            title: e.title,
            subtitle: '${e.type == 'In' ? '+' : e.type == 'Out' ? '-' : ''}₹${e.amount.toStringAsFixed(0)} · ${e.category}',
            badge: 'EXPENSE',
            onTap: () => setState(() { _isSearching = false; _currentIndex = 1; }),
          )),
          const SizedBox(height: 8),
        ],
        if (links.isNotEmpty) ...[
          _globalSearchSection('Links', Icons.link, const Color(0xFF0EA5E9)),
          ...links.map((l) => _globalSearchTile(
            icon: Icons.link_outlined, color: const Color(0xFF0EA5E9),
            title: l.title,
            subtitle: l.url,
            badge: 'LINK',
            onTap: () => setState(() { _isSearching = false; _currentIndex = 2; }),
          )),
          const SizedBox(height: 8),
        ],
        if (reminders.isNotEmpty) ...[
          _globalSearchSection('Reminders', Icons.alarm, const Color(0xFFF59E0B)),
          ...reminders.map((r) => _globalSearchTile(
            icon: Icons.alarm_outlined, color: const Color(0xFFF59E0B),
            title: r.title,
            subtitle: r.description.isNotEmpty ? r.description : DateFormat('dd MMM yyyy, hh:mm a').format(r.dateTime),
            badge: 'REMINDER',
            onTap: () => setState(() { _isSearching = false; _currentIndex = 5; }),
          )),
        ],
      ],
    );
  }

  Widget _globalSearchSection(String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _globalSearchTile({required IconData icon, required Color color, required String title,
      required String subtitle, required String badge, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(radius: 16, backgroundColor: color.withOpacity(0.12), child: Icon(icon, size: 16, color: color)),
        title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
          child: Text(badge, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
        ),
        onTap: onTap,
      ),
    );
  }

  void _handleFabPress() {
    switch (_currentIndex) {
      case 0:
        final selectedCat = ref.read(selectedCategoryProvider);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => NoteEditor(
            note: Note(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: '', 
              content: '', 
              category: selectedCat
            ), 
            isNew: true
          ),
        ));
        break;
      case 1:
        final selectedCat = ref.read(selectedExpenseCategoryProvider);
        showDialog(
          context: context,
          useRootNavigator: true,
          builder: (context) => ExpenseDialog(initialCategory: selectedCat),
        );
        break;
      case 2:
        final selectedCat = ref.read(selectedLinkCategoryProvider);
        showDialog(
          context: context,
          useRootNavigator: true,
          builder: (context) => LinkDialog(initialCategory: selectedCat),
        );
        break;
      case 3:
        final selectedCat = ref.read(selectedTableCategoryProvider);
        ref.read(editingTableProvider.notifier).state = VaultTable(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '',
          columns: [VaultTableCell(text: 'Column 1'), VaultTableCell(text: 'Column 2')],
          rows: [
            [VaultTableCell(text: ''), VaultTableCell(text: '')]
          ],
          category: selectedCat,
        );
        break;
      case 5:
        showDialog(
          context: context,
          useRootNavigator: true,
          builder: (context) => const ReminderDialog(),
        );
        break;
      case 6:
        showCardEditorDialog(context, ref);
        break;
      case 7:
        showDialog(
          context: context,
          useRootNavigator: true,
          builder: (context) => BillDialog(),
        );
        break;
    }
  }

  void _selectAllNotes() {
    final currentCat = ref.read(selectedCategoryProvider);
    final allNotesInCat = ref.read(notesProvider).where((n) => n.category == currentCat).map((n) => n.id).toSet();
    ref.read(selectedNotesProvider.notifier).selectAll(allNotesInCat);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${allNotesInCat.length} notes selected')));
  }

  void _selectAllExpenses() {
    final currentCat = ref.read(selectedExpenseCategoryProvider);
    final expenses = ref.read(expensesProvider);
    final filtered = currentCat == 'All' ? expenses : expenses.where((e) => e.category == currentCat);
    final selectedIds = filtered.map((e) => e.id).toSet();
    ref.read(selectedExpensesProvider.notifier).selectAll(selectedIds);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} expenses selected')));
  }

  void _selectAllLinks() {
    final currentCat = ref.read(selectedLinkCategoryProvider);
    final links = ref.read(linkItemsProvider);
    final filtered = currentCat == 'All' ? links : links.where((l) => l.category == currentCat);
    final selectedIds = filtered.map((l) => l.id).toSet();
    ref.read(selectedLinksProvider.notifier).selectAll(selectedIds);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} links selected')));
  }

  void _selectAllReminders() {
    final reminders = ref.read(remindersProvider);
    final selectedIds = reminders.map((r) => r.id).toSet();
    ref.read(selectedRemindersProvider.notifier).selectAll(selectedIds);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} reminders selected')));
  }

  void _deleteSelectedNotes() {
    final selectedIds = ref.read(selectedNotesProvider).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Notes?'),
        content: Text('Move ${selectedIds.length} notes to Recycle Bin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () {
            ref.read(notesProvider.notifier).deleteNotes(selectedIds);
            ref.read(selectedNotesProvider.notifier).clear();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} notes moved to Recycle Bin')));
          }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _deleteSelectedExpenses() {
    final selectedIds = ref.read(selectedExpensesProvider).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expenses?'),
        content: Text('Move ${selectedIds.length} expenses to Recycle Bin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () {
            ref.read(expensesProvider.notifier).deleteExpenses(selectedIds);
            ref.read(selectedExpensesProvider.notifier).clear();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} expenses moved to Recycle Bin')));
          }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _deleteSelectedLinks() {
    final selectedIds = ref.read(selectedLinksProvider).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Links?'),
        content: Text('Move ${selectedIds.length} links to Recycle Bin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () {
            ref.read(linkItemsProvider.notifier).deleteLinks(selectedIds);
            ref.read(selectedLinksProvider.notifier).clear();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} links moved to Recycle Bin')));
          }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _deleteSelectedReminders() {
    final selectedIds = ref.read(selectedRemindersProvider).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminders?'),
        content: Text('Are you sure you want to permanently delete these ${selectedIds.length} reminders?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () {
            ref.read(remindersProvider.notifier).deleteReminders(selectedIds);
            ref.read(selectedRemindersProvider.notifier).clear();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} reminders permanently deleted')));
          }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _moveSelectedNotes() {
    final selectedIds = ref.read(selectedNotesProvider).toList();
    final categories = ref.read(categoriesProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${selectedIds.length} Notes'),
        content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: categories.length, itemBuilder: (context, index) {
          final cat = categories[index];
          return ListTile(title: Text(cat), leading: const Icon(Icons.folder_outlined), onTap: () {
            ref.read(notesProvider.notifier).moveNotes(selectedIds, cat);
            ref.read(selectedNotesProvider.notifier).clear();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} notes moved to $cat')));
          });
        })),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
  }

  void _moveSelectedExpenses() {
    final selectedIds = ref.read(selectedExpensesProvider).toList();
    final categories = ref.read(expenseCategoriesProvider).where((c) => c != 'All').toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${selectedIds.length} Expenses'),
        content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: categories.length, itemBuilder: (context, index) {
          final cat = categories[index];
          return ListTile(title: Text(cat), leading: const Icon(Icons.account_balance_wallet_outlined), onTap: () {
            ref.read(expensesProvider.notifier).moveExpenses(selectedIds, cat);
            ref.read(selectedExpensesProvider.notifier).clear();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} expenses moved to $cat')));
          });
        })),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
  }

  void _moveSelectedLinks() {
    final selectedIds = ref.read(selectedLinksProvider).toList();
    final categories = ref.read(linkCategoriesProvider).where((c) => c != 'All').toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${selectedIds.length} Links'),
        content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: categories.length, itemBuilder: (context, index) {
          final cat = categories[index];
          return ListTile(title: Text(cat), leading: const Icon(Icons.link_outlined), onTap: () {
            ref.read(linkItemsProvider.notifier).moveLinks(selectedIds, cat);
            ref.read(selectedLinksProvider.notifier).clear();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selectedIds.length} links moved to $cat')));
          });
        })),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _handleSyncAnimation() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    _syncAnimationController.repeat();
    await _exportData();
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _isSyncing = false);
      _syncAnimationController.stop();
      _syncAnimationController.reset();
    }
  }

  Future<void> _exportData() async {
    final vaultPath = await ref.read(vaultServiceProvider).getVaultPath();
    if (vaultPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a vault folder first')));
      return;
    }
    try {
      await ref.read(vaultServiceProvider).exportToFolders(
        vaultPath, 
        ref.read(notesProvider), 
        ref.read(categoriesProvider), 
        ref.read(expensesProvider),
        ref.read(linkItemsProvider),
        ref.read(tablesProvider),
        ref.read(cardsProvider),
        ref.read(lockProvider),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_timestamp_ms', DateTime.now().millisecondsSinceEpoch);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync complete!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
  }

  Future<void> _pickVaultFolder() async {
    final storageGranted = await Permission.storage.request().isGranted;
    final manageGranted = await Permission.manageExternalStorage.request().isGranted;
    if (!storageGranted && !manageGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission is required to pick a folder.')),
        );
      }
      return;
    }
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null) {
      await ref.read(vaultServiceProvider).setVaultPath(selectedDirectory);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_timestamp_ms', DateTime.now().millisecondsSinceEpoch);
      ref.invalidate(vaultPathProvider);
      ref.invalidate(cardsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vault connected to: $selectedDirectory')));
    } else {
      // User cancelled — remind them a folder is required
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No folder selected. Please pick a folder to continue.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _importData() async {
    if (await Permission.storage.request().isGranted || await Permission.manageExternalStorage.request().isGranted) {
      String? selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory != null) {
        showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
        try {
          final data = await ref.read(vaultServiceProvider).importFromFolders(selectedDirectory);
          final importedNotes = data['notes'] as List<Note>;
          final importedCategories = data['categories'] as List<String>;
          final importedExpenses = (data['expenses'] as List<dynamic>? ?? []).map((e) => Expense.fromJson(e)).toList();
          final importedExpenseCategories = data['expenseCategories'] as List<String>? ?? [];
          final importedLinks = (data['links'] as List<dynamic>? ?? []).map((l) => LinkItem.fromJson(l)).toList();
          final importedLinkCategories = data['linkCategories'] as List<String>? ?? [];
          final importedTables = (data['tables'] as List<dynamic>? ?? []).map((t) => VaultTable.fromJson(t)).toList();
          final importedTableCategories = data['tableCategories'] as List<String>? ?? [];
          
          if (importedNotes.isEmpty && importedExpenses.isEmpty && importedLinks.isEmpty && importedTables.isEmpty) { 
            Navigator.pop(context); 
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data found to import'))); 
            return; 
          }

          // Register categories
          for (final cat in importedCategories) {
            ref.read(categoriesProvider.notifier).addCategory(cat);
          }
          for (final cat in importedExpenseCategories) {
            ref.read(expenseCategoriesProvider.notifier).addCategory(cat);
          }
          for (final cat in importedLinkCategories) {
            ref.read(linkCategoriesProvider.notifier).addCategory(cat);
          }
          for (final cat in importedTableCategories) {
            ref.read(tableCategoriesProvider.notifier).addCategory(cat);
          }

          // Register items
          for (final note in importedNotes) {
            ref.read(notesProvider.notifier).addNote(note);
          }
          if (importedExpenses.isNotEmpty) ref.read(expensesProvider.notifier).addExpenses(importedExpenses);
          if (importedLinks.isNotEmpty) {
            for (final link in importedLinks) {
              ref.read(linkItemsProvider.notifier).addLink(link);
            }
          }
          if (importedTables.isNotEmpty) {
            for (final table in importedTables) {
              ref.read(tablesProvider.notifier).addTable(table);
            }
          }

          // Import deleted items if present
          final deletedData = data['deletedData'] as Map<String, dynamic>?;
          if (deletedData != null) {
            final delNotes = (deletedData['notes'] as List<dynamic>? ?? []).map((n) => Note.fromJson(n)).toList();
            final delExps = (deletedData['expenses'] as List<dynamic>? ?? []).map((e) => Expense.fromJson(e)).toList();
            final delLinks = (deletedData['links'] as List<dynamic>? ?? []).map((l) => LinkItem.fromJson(l)).toList();
            
            if (delNotes.isNotEmpty) ref.read(deletedNotesProvider.notifier).addNotes(delNotes);
            if (delExps.isNotEmpty) ref.read(deletedExpensesProvider.notifier).addExpenses(delExps);
            if (delLinks.isNotEmpty) ref.read(deletedLinksProvider.notifier).addLinks(delLinks);
          }

          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import successful!')));
        } catch (e) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
        }
      }
    }
  }

}

class SecuritySettingsDialog extends ConsumerStatefulWidget {
  const SecuritySettingsDialog({super.key});

  @override
  ConsumerState<SecuritySettingsDialog> createState() => _SecuritySettingsDialogState();
}

class _SecuritySettingsDialogState extends ConsumerState<SecuritySettingsDialog> {
  late TextEditingController _newPassController;
  late TextEditingController _verifyOldController;
  late FocusNode _newPassFocusNode;
  bool _isSettingNew = false;

  @override
  void initState() {
    super.initState();
    _newPassController = TextEditingController();
    _verifyOldController = TextEditingController();
    _newPassFocusNode = FocusNode();
    
    // Check initial state
    final currentLock = ref.read(lockProvider);
    _isSettingNew = currentLock.isEmpty;
  }

  @override
  void dispose() {
    _newPassController.dispose();
    _verifyOldController.dispose();
    _newPassFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentLock = ref.watch(lockProvider);
    final isSet = currentLock.isNotEmpty;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.security, color: Color(0xFF1D63D2)),
          const SizedBox(width: 8),
          const Text('Reset Password'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isSettingNew) ...[
            const Text('Enter current passcode to change:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _verifyOldController,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Current Passcode', border: OutlineInputBorder(), counterText: ''),
              keyboardType: TextInputType.number,
              maxLength: 7,
              onChanged: (val) {
                if (val == currentLock) {
                  setState(() {
                    _isSettingNew = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_newPassFocusNode.canRequestFocus) {
                        _newPassFocusNode.requestFocus();
                      }
                    });
                  });
                }
              },
            ),
          ] else ...[
            Text(isSet ? 'Enter new 7-digit passcode:' : 'Set a new 7-digit passcode:', 
                 style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _newPassController,
              focusNode: _newPassFocusNode,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'New Passcode', border: OutlineInputBorder(), counterText: ''),
              keyboardType: TextInputType.number,
              maxLength: 7,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (_isSettingNew)
          TextButton(
            onPressed: () {
              if (_newPassController.text.length == 7) {
                ref.read(lockProvider.notifier).setLock(_newPassController.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passcode saved successfully')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Must be 7 digits')));
              }
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late final Stream<DateTime> _clockStream;

  @override
  void initState() {
    super.initState();
    _clockStream = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: _clockStream,
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final day = now.day;
        String suffix = 'th';
        if (day < 11 || day > 13) {
          switch (day % 10) {
            case 1: suffix = 'st'; break;
            case 2: suffix = 'nd'; break;
            case 3: suffix = 'rd'; break;
          }
        }
        return Text.rich(
          TextSpan(
            style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
            children: [
              TextSpan(text: "$day$suffix ${DateFormat('MMMM yyyy | EEE | hh:mm').format(now)}"),
              TextSpan(
                text: DateFormat(':ss').format(now),
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 15),
              ),
              TextSpan(text: DateFormat(' a').format(now)),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.visible,
        );
      },
    );
  }
}
