import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/models/user_profile.dart';

class UserProfileService {
  static const String _prefsKey = 'user_profile_v1';

  Future<UserProfile> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      final parsed = raw == null ? null : UserProfile.fromPrefsString(raw);
      return parsed ?? UserProfile.empty();
    } catch (e) {
      debugPrint('UserProfileService.load failed: $e');
      return UserProfile.empty();
    }
  }

  /// Returns true if the profile was actually persisted. Callers that need
  /// to tell the user their change was saved (rather than just updating
  /// in-memory state) should check this instead of assuming success.
  Future<bool> save(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, profile.toPrefsString());
      return true;
    } catch (e) {
      debugPrint('UserProfileService.save failed: $e');
      return false;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('UserProfileService.clear failed: $e');
    }
  }
}
