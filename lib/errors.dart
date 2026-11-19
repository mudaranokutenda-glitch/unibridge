import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n.dart';

// ---------------- Short, translated error messages ----------------
// Never show raw errors like "PostgrestException(message: ..., code: 42501)".
//
//   friendlyError(e)              -> "No internet connection. Check it and try again."
//   tr('Could not save: {error}', {'error': friendlyError(e, short: true)})
//                                 -> "Could not save: no internet connection."
//
// The full error is still printed in the debug console (flutter run).

String friendlyError(Object e, {bool short = false}) {
  debugPrint('Error: $e');
  final raw = e.toString().toLowerCase();

  if (_isNoInternet(raw)) {
    return short
        ? tr('no internet connection.')
        : tr('No internet connection. Check it and try again.');
  }

  if (e is PostgrestException) {
    // Our own database functions raise messages written for people
    // ("Request is no longer open", "You can only confirm your own side"...).
    if (e.code == 'P0001') return tr(e.message);
    if (e.code == '42501' || e.code == 'PGRST301') {
      return short
          ? tr('not allowed.')
          : tr("You are not allowed to do this.");
    }
    if (e.code == '23505') {
      return short ? tr('it already exists.') : tr('This already exists.');
    }
    if (e.code == 'PGRST116') {
      return short
          ? tr('it is no longer available.')
          : tr('This is no longer available.');
    }
  }

  if (e is AuthException) {
    return short
        ? tr('please log in again.')
        : tr('Your login has expired. Please log in again.');
  }

  if (e is FunctionException) {
    final d = e.details;
    final text = d is Map ? d['error']?.toString() : null;
    if (text != null && text.isNotEmpty) return tr(text);
  }

  if (e is StorageException) {
    if ((e.statusCode ?? '') == '413' || e.message.toLowerCase().contains('size')) {
      return short ? tr('the file is too big.') : tr('This file is too big.');
    }
  }

  return short ? tr('please try again.') : tr('Something went wrong. Try again.');
}

bool _isNoInternet(String raw) =>
    raw.contains('socketexception') ||
    raw.contains('failed host lookup') ||
    raw.contains('clientexception') ||
    raw.contains('connection refused') ||
    raw.contains('connection closed') ||
    raw.contains('network is unreachable') ||
    raw.contains('timed out') ||
    raw.contains('timeoutexception');
