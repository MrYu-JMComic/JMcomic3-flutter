import 'entities.dart';

/// Stable, source-neutral description of a reader page.
///
/// `position` is the original list position and is never changed by
/// [ReaderPageRepository]. Empty or duplicate names are retained and marked
/// so callers can decide how to handle them without silently reordering pages.
class PageDescriptor {
  const PageDescriptor({
    required this.position,
    required this.name,
    this.width = 0,
    this.height = 0,
    this.key = '',
    this.isDuplicateName = false,
    this.localPath,
    this.localAvailable = false,
  });

  final int position;
  final String name;
  final int width;
  final int height;
  final String key;
  final bool isDuplicateName;
  /// Canonical local cache path, when independently validated by the caller.
  final String? localPath;
  final bool localAvailable;

  bool get hasName => name.trim().isNotEmpty;
  bool get hasDimensions => width > 0 && height > 0;
  /// A repeated filename is still a valid page: the source index is part of
  /// the identity and prevents one page from silently hiding another.  Keep
  /// [isDuplicateName] as diagnostic metadata for callers that want to warn
  /// or choose a stronger cache key, but never discard the page here.
  bool get isUsable => hasName;

  PageDescriptor copyWith({bool? isDuplicateName, String? localPath, bool? localAvailable}) => PageDescriptor(
        position: position,
        name: name,
        width: width,
        height: height,
        key: key,
        isDuplicateName: isDuplicateName ?? this.isDuplicateName,
        localPath: localPath ?? this.localPath,
        localAvailable: localAvailable ?? this.localAvailable,
      );
}

/// Compatibility adapter for online `List<String>` and offline [DlImage].
class ReaderPageRepository {
  const ReaderPageRepository._();

  static List<PageDescriptor> fromOnline(List<String> images) =>
      _markDuplicates(images.asMap().entries.map((entry) => PageDescriptor(
            position: entry.key,
            name: entry.value,
          )));

  static List<PageDescriptor> fromOffline(List<DlImage> images) =>
      _markDuplicates(images.asMap().entries.map((entry) {
        final image = entry.value;
        return PageDescriptor(
          position: entry.key,
          name: image.name,
          width: image.width,
          height: image.height,
          key: image.key,
        );
      }));

  static List<PageDescriptor> _markDuplicates(
      Iterable<PageDescriptor> descriptors) {
    final seen = <String>{};
    return List.unmodifiable(descriptors.map((page) {
      final normalized = page.name.trim();
      final duplicate = normalized.isNotEmpty && !seen.add(normalized);
      return page.copyWith(isDuplicateName: duplicate);
    }));
  }
}
