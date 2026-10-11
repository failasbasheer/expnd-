import 'dart:io';

/// Resolves stored receipt photo paths to files on disk.
///
/// Receipts used to be stored as absolute paths into the app's Documents
/// folder. iOS can move that container on update, reinstall or restore, which
/// left every old path dead. New receipts store only the file name, and old
/// absolute paths are re-rooted by file name, so both survive a container move.
class Receipts {
  Receipts._();

  static String? _docs;

  /// Call once at startup with the app's Documents directory.
  static void init(Directory documents) => _docs = documents.path;

  /// The value to persist for a receipt saved at [path].
  static String storedName(String path) => path.split('/').last;

  /// The receipt file for a stored value, or null if it no longer exists.
  static File? fileFor(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    final docs = _docs;
    if (docs != null) {
      final rooted = File('$docs/${storedName(stored)}');
      if (rooted.existsSync()) return rooted;
    }
    final literal = File(stored);
    return literal.isAbsolute && literal.existsSync() ? literal : null;
  }
}
