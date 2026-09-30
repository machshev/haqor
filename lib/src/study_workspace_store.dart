import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bindings/bindings.dart' hide StudyItem;
import 'prefs_read.dart';
import 'request_failure.dart';
import 'study_workspace.dart';
import 'tutor/progress_sync.dart';

/// The study workspaces, shared by every reader tab so that an edit in one is
/// never written over by another's older copy. It keeps them in preferences
/// and in Rust, and takes Rust's answers to [GetStudyState] (which also
/// follow a sync) as the one place they are received.
class StudyWorkspaceStore extends ChangeNotifier {
  /// [sendRequest] and [save] let tests replace the native signals.
  StudyWorkspaceStore({this.sendRequest, this.save});

  final void Function(GetStudyState request)? sendRequest;
  final void Function(SaveStudyState request)? save;

  final List<StudyWorkspace> _workspaces = [];
  String? _activeId;
  StreamSubscription<RustSignalPack<StudyState>>? _stateSub;
  StreamSubscription<RequestFailed>? _failureSub;
  bool _loaded = false;
  // Until Rust answers the request made at startup, its answer is older than
  // any edit made since, so such an edit is kept and the answer set aside.
  bool _awaitingFirstAnswer = false;
  bool _editedBeforeAnswer = false;
  bool _migrationSent = false;
  bool _disposed = false;

  List<StudyWorkspace> get workspaces => List.unmodifiable(_workspaces);
  String? get activeId => _activeId;

  StudyWorkspace? get active {
    for (final workspace in _workspaces) {
      if (workspace.id == _activeId) return workspace;
    }
    return null;
  }

  /// Read the local copy, then ask Rust for its own.
  Future<void> start() async {
    _stateSub = StudyState.rustSignalStream.listen(_onState);
    _failureSub = listenForFailure(requestStudyState, (_) {
      // Keep the local copy, and take the next answer as any other.
      _awaitingFirstAnswer = false;
    });
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _workspaces
      ..clear()
      ..addAll(decodeStudyWorkspaces(prefs.readString(studyWorkspacesKey)));
    _activeId = _validActiveId(prefs.readString(activeStudyWorkspaceKey));
    _loaded = true;
    _awaitingFirstAnswer = true;
    notifyListeners();
    final request = GetStudyState();
    final send = sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  String? _validActiveId(String? id) =>
      _workspaces.any((workspace) => workspace.id == id)
      ? id
      : _workspaces.isEmpty
      ? null
      : _workspaces.first.id;

  Future<void> _onState(RustSignalPack<StudyState> pack) async {
    if (_disposed || !_loaded) return;
    final message = pack.message;
    final edited = _awaitingFirstAnswer && _editedBeforeAnswer;
    _awaitingFirstAnswer = false;
    // The edit made before this answer is already saved and sent, and is
    // newer than what the answer holds.
    if (edited) return;
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    if (!message.found) {
      // Rust has none yet: hand it the copy this device kept before study
      // moved into the core, once however many tabs are open.
      final legacyJson = prefs.readString(studyWorkspacesKey);
      if (!_migrationSent &&
          legacyJson != null &&
          tryDecodeStudyWorkspaces(legacyJson) != null) {
        _migrationSent = true;
        _send(
          SaveStudyState(
            workspacesJson: legacyJson,
            activeWorkspaceId: prefs.readString(activeStudyWorkspaceKey) ?? '',
          ),
        );
      }
      return;
    }
    // An answer that cannot be read is no answer: the local copy stays as it
    // is, instead of being replaced by nothing and saved over the backup.
    final decoded = tryDecodeStudyWorkspaces(message.workspacesJson);
    if (decoded == null) return;
    _workspaces
      ..clear()
      ..addAll(decoded);
    _activeId = _validActiveId(message.activeWorkspaceId);
    notifyListeners();
    await saveStudyWorkspaces(prefs, _workspaces, _activeId);
  }

  void _send(SaveStudyState request) {
    final save = this.save;
    if (save != null) {
      save(request);
    } else {
      request.sendSignalToRust();
      scheduleProgressSync();
    }
  }

  /// Keep [updated] in place of the workspace with its id.
  Future<void> replace(StudyWorkspace updated) {
    final index = _workspaces.indexWhere(
      (workspace) => workspace.id == updated.id,
    );
    if (index < 0) return Future.value();
    _workspaces[index] = updated;
    return _changed();
  }

  /// Add [workspace] and make it the active one.
  Future<void> add(StudyWorkspace workspace) {
    _workspaces.add(workspace);
    _activeId = workspace.id;
    return _changed();
  }

  /// Remove the workspace [id], activating the first left if it was active.
  Future<void> remove(String id) {
    _workspaces.removeWhere((workspace) => workspace.id == id);
    _activeId = _validActiveId(_activeId);
    return _changed();
  }

  Future<void> select(String? id) {
    _activeId = id;
    return _changed();
  }

  Future<void> _changed() async {
    if (_disposed) return;
    if (_awaitingFirstAnswer) _editedBeforeAnswer = true;
    notifyListeners();
    // Encoded once, for both the local copy and Rust's.
    final workspaces = List.of(_workspaces);
    final activeId = _activeId;
    final encoded = encodeStudyWorkspaces(workspaces);
    final prefs = await SharedPreferences.getInstance();
    await saveStudyWorkspaces(prefs, workspaces, activeId, encoded: encoded);
    _send(
      SaveStudyState(
        workspacesJson: encoded,
        activeWorkspaceId: activeId ?? '',
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _stateSub?.cancel();
    _failureSub?.cancel();
    super.dispose();
  }
}
