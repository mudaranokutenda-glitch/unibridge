import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_icons.dart';
import 'l10n.dart';

// ---------------- Bottom bar with a raised round "+" in the middle ----------------
// Requests | Marketplace | [+] | Student space | Profile
// The "+" itself is the floating button of the Home screen (docked in the notch).
// The tab numbers are the same as before: 0 Requests, 1 Marketplace, 2 Student space, 3 Profile.

class AppBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  const AppBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      height: 66,
      padding: EdgeInsets.zero,
      color: dark ? AppColors.darkCard : AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: dark ? Colors.black : AppColors.sky,
      child: Row(
        children: [
          _item(context, 0, null, Icons.swap_horiz, Icons.swap_horiz,
              tr('Requests')),
          _item(context, 1, 'marketplace', Icons.storefront_outlined,
              Icons.storefront, tr('Marketplace')),
          const SizedBox(width: 76), // room for the round "+"
          _item(context, 2, 'student_space', Icons.school_outlined,
              Icons.school, tr('Student space')),
          _item(context, 3, 'profile', Icons.person_outline, Icons.person,
              tr('Profile')),
        ],
      ),
    );
  }

  // iconName: the PNG in assets/icons (null = always a Material icon).
  Widget _item(BuildContext context, int index, String? iconName, IconData icon,
      IconData selectedIcon, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = selectedIndex == index;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // A soft blue circle sits behind the active tab.
              Container(
                width: 40,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? scheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: iconName == null
                      ? Icon(selected ? selectedIcon : icon,
                          color: color, size: 24)
                      : Opacity(
                          opacity: selected ? 1 : 0.6,
                          child: AppIcon(
                            name: iconName,
                            fallback: selected ? selectedIcon : icon,
                            color: color,
                            size: 24,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// The round "+" in the middle of the bar.
class NewRequestButton extends StatelessWidget {
  final VoidCallback onPressed;
  const NewRequestButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: FloatingActionButton(
        heroTag: 'new-request',
        tooltip: tr('New request'),
        onPressed: onPressed,
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }
}
