import 'package:flutter/material.dart';

import 'config.dart';
import 'profiles.dart';
import 'profile_setup.dart';
import 'wilayas.dart';
import 'l10n.dart';

// ---------------- WhatsApp-style rows for the request lists ----------------
// Used by Open requests (home.dart) and My requests (requests.dart).

const double kRowAvatarRadius = 26;
const double _rowStartPadding = 16;
const double _avatarGap = 12;

int _asCount(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

// "★ 4.8" or "No ratings yet"
String ratingText(Map<String, dynamic>? p) {
  final count = _asCount(p?['rating_count']);
  final avg = asDouble(p?['avg_rating']);
  if (count == 0 || avg == null) return tr('No ratings yet');
  return '★ ${avg.toStringAsFixed(1)}';
}

String completedText(Map<String, dynamic>? p) =>
    tr('{count} completed', {'count': _asCount(p?['completed_count'])});

// ---------------- Request expiry (48 hours by default) ----------------
// The database cancels an OPEN request after request_expiry_hours (table
// app_settings, default 48). The app only SHOWS the time left.

double kRequestExpiryHours = 48;
bool _expiryLoaded = false;

Future<void> loadRequestExpiryHours() async {
  if (_expiryLoaded) return;
  try {
    final row = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'request_expiry_hours')
        .maybeSingle();
    final v = asDouble(row?['value']);
    if (v != null && v > 0) kRequestExpiryHours = v;
    _expiryLoaded = true;
  } catch (e) {
    // The table may not exist yet: keep 48 hours.
    debugPrint('Could not read request_expiry_hours: $e');
  }
}

// Time left for an OPEN request, or null for any other status.
Duration? requestTimeLeft(Map<String, dynamic> r) {
  if ('${r['status']}' != 'OPEN') return null;
  final created = DateTime.tryParse('${r['created_at']}');
  if (created == null) return null;
  final end = created.add(Duration(minutes: (kRequestExpiryHours * 60).round()));
  return end.difference(DateTime.now());
}

// Cancelled by the expiry job, or still OPEN but past its time (the job runs
// every 15 minutes, so for a short while an old request is still OPEN).
bool requestIsExpired(Map<String, dynamic> r) {
  if ('${r['status']}' == 'CANCELLED') return '${r['cancel_reason']}' == 'EXPIRED';
  final left = requestTimeLeft(r);
  return left != null && left <= Duration.zero;
}

// "1d 4h", "4h 10m", "35m"
String durationShort(Duration d) {
  final minutes = d.inMinutes < 1 ? 1 : d.inMinutes;
  final days = minutes ~/ 1440;
  final hours = (minutes % 1440) ~/ 60;
  final mins = minutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${mins}m';
  return '${mins}m';
}

// The text shown instead of "Open" on an open request: "Expires in 1d 4h".
String requestStatusText(Map<String, dynamic> r) {
  if (requestIsExpired(r)) return tr('Expired');
  final left = requestTimeLeft(r);
  if (left != null) {
    return tr('Expires in {time}', {'time': durationShort(left)});
  }
  return statusLabel(r['status']);
}

// "50 USD" instead of "50.0 USD"
String formatAmount(dynamic amount, dynamic currency) {
  final n = num.tryParse('$amount');
  final text = n == null
      ? '$amount'
      : (n == n.roundToDouble() ? n.toInt().toString() : n.toString());
  return '$text ${currency ?? ''}'.trim();
}

Widget _nameWithTick(
  BuildContext context,
  String name,
  bool verified, {
  double fontSize = 16,
}) {
  return Row(
    children: [
      Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      ),
      if (verified) ...[
        const SizedBox(width: 4),
        Icon(Icons.verified, size: fontSize, color: Colors.blue),
      ],
    ],
  );
}

class RequestRow extends StatelessWidget {
  // The other person. null = nobody yet (then [placeholderIcon] is shown).
  final Map<String, dynamic>? person;
  final IconData placeholderIcon;
  // Line 1 when there is no person (e.g. "Waiting for a match").
  final String? placeholderTitle;
  final String subtitle;
  final String amount;
  final String status;
  // Small button on the far end (Match / Cancel), optional.
  final Widget? action;
  final VoidCallback? onTap;
  // Cancelled: red accent on the start side and a red status.
  final bool danger;

  const RequestRow({
    super.key,
    required this.person,
    required this.subtitle,
    required this.amount,
    required this.status,
    this.placeholderIcon = Icons.person_outline,
    this.placeholderTitle,
    this.action,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);
    final p = person;

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: danger
            ? BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: scheme.error, width: 3),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            _rowStartPadding,
            10,
            12,
            10,
          ),
          child: Row(
            children: [
              p != null
                  ? avatar(p, radius: kRowAvatarRadius)
                  : CircleAvatar(
                      radius: kRowAvatarRadius,
                      backgroundColor: scheme.surfaceContainerHighest,
                      foregroundColor: scheme.onSurfaceVariant,
                      child: Icon(placeholderIcon),
                    ),
              const SizedBox(width: _avatarGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    p != null
                        ? _nameWithTick(
                            context,
                            publicDisplayName(p),
                            p['is_verified'] == true,
                          )
                        : Text(
                            placeholderTitle ?? tr('UniBridge user'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: danger ? scheme.error : scheme.onSurfaceVariant,
                      fontWeight: danger ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
              if (action != null) ...[const SizedBox(width: 8), action!],
            ],
          ),
        ),
      ),
    );
  }
}

// Thin line between rows. Starts after the avatar, like WhatsApp.
class RequestRowDivider extends StatelessWidget {
  const RequestRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: _rowStartPadding + kRowAvatarRadius * 2 + _avatarGap,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

// Small "Match" button that fits in a row.
class SmallRowButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const SmallRowButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

// ---------------- My profile bar (top of the Requests tab) ----------------

// Frame colours of the profile bar. Change them here.
const Color kVerifiedFrameColor = Color(0xFFD4AF37); // gold
const Color kUnverifiedFrameColor = Color(0xFF2F80ED); // blue

class MyProfileBar extends StatelessWidget {
  // My profile from get_public_profiles. null = not loaded (yet).
  final Map<String, dynamic>? profile;
  // true while the first load is running (then no "Complete your profile").
  final bool loading;
  final VoidCallback onTap;
  const MyProfileBar({
    super.key,
    required this.profile,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    // Always shown: if my profile is missing, use my sign-up / Google name.
    final p = profile ?? myFallbackProfile();
    final scheme = Theme.of(context).colorScheme;
    final verified = p['is_verified'] == true;
    final frameColor = verified ? kVerifiedFrameColor : kUnverifiedFrameColor;
    final String details;
    if (profile == null && loading) {
      details = '';
    } else if (!isProfileComplete(profile)) {
      details = tr('Complete your profile');
    } else {
      details = [
        validWilaya(p['wilaya'])!,
        ratingText(p),
        completedText(p),
      ].join(' · ');
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
      // The Material draws the rounded frame and clips the tap ripple to it.
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: frameColor, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 4, 6),
            child: Row(
              children: [
                // Ring: 2 px border in the primary colour, then a 2 px
                // see-through gap (the background shows through).
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: avatar(p, radius: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _nameWithTick(
                        context,
                        publicDisplayName(p),
                        verified,
                        fontSize: 15,
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
