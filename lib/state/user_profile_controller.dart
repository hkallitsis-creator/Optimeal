import 'package:flutter/foundation.dart';

import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/services/user_profile_service.dart';

class UserProfileController extends ChangeNotifier {
  UserProfileController(this._service);

  final UserProfileService _service;

  UserProfile _profile = UserProfile.empty();
  bool _isLoaded = false;

  UserProfile get profile => _profile;
  bool get isLoaded => _isLoaded;
  bool get isOnboarded => _profile.onboarded;

  Future<void> load() async {
    _profile = await _service.load();
    _isLoaded = true;
    notifyListeners();
  }

  /// Returns true if the change was actually persisted to disk. The
  /// in-memory profile (and any listening UI) updates either way — this is
  /// only for callers that need to tell the user whether the save is real.
  Future<bool> updateProfile(UserProfile next) async {
    _profile = next.copyWith(updatedAt: DateTime.now());
    notifyListeners();
    return _service.save(_profile);
  }
}
