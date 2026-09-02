import 'entities.dart';

/// Stable, source-neutral description of a reader page.
///
/// `position` is the contiguous position in the normalized reader list. Empty
/// or duplicate names are retained and marked so callers can decide how to
/// handle them without silently dropping a page. Offline records keep their
/// persisted index separately in [sourceIndex].
class PageDescriptor {
  const PageDescriptor({
    required this.position,
    required this.name,
    this.sourceIndex,
    this.width = 0,
    this.height = 0,
    this.key = '',
    this.isDuplicateName = false,
    this.localPath,
    this.localAvailable = false,
  });

  final int position;
  final String name;

  /// Persisted source index, when supplied by an offline backend.  This is
  /// diagnostic identity only; [position] is always the contiguous index used
  /// by the reader widgets.
  final int? sourceIndex;
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

  PageDescriptor copyWith({
    bool? isDuplicateName,
    String? localPath,
    bool? localAvailable,
  }) => PageDescriptor(
    position: position,
    name: name,
    sourceIndex: sourceIndex,
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
      _markDuplicates(
        images.asMap().entries.map(
          (entry) => PageDescriptor(
            position: entry.key,
            name: entry.value,
            sourceIndex: entry.key,
          ),
        ),
      );

  static List<PageDescriptor> fromOffline(List<DlImage> images) {
    final ordered = orderOfflineImages(images);
    return _markDuplicates(
      ordered.asMap().entries.map((entry) {
        final image = entry.value;
        return PageDescriptor(
          position: entry.key,
          name: image.name,
          sourceIndex: image.imageIndex,
          width: image.width,
          height: image.height,
          key: image.key,
          // A path is trusted only when it came from the backend availability
          // probe.  Never derive one from the persisted name or dl_status.
          localPath: image.localPath,
          // A backend may serialize an empty path alongside an optimistic
          // availability flag. Treat that as metadata-only; consumers must
          // never attempt to open an empty filesystem path.
          localAvailable:
              image.localAvailable &&
              image.localPath != null &&
              image.localPath!.trim().isNotEmpty,
        );
      }),
    );
  }

  /// Normalize imported/download metadata into the order used by the reader.
  /// The persisted source index is not assumed to be dense or unique, so the
  /// returned list position (rather than imageIndex) is the only render index.
  static List<DlImage> orderOfflineImages(List<DlImage> images) {
    final indexed = images.asMap().entries.toList(growable: false);
    final ordered = indexed.toList()
      ..sort((a, b) {
        final aIndex = a.value.imageIndex;
        final bIndex = b.value.imageIndex;
        final aValid = aIndex >= 0;
        final bValid = bIndex >= 0;
        if (aValid != bValid) return aValid ? -1 : 1;
        if (aValid && aIndex != bIndex) return aIndex.compareTo(bIndex);
        return a.key.compareTo(b.key);
      });
    return List.unmodifiable(ordered.map((entry) => entry.value));
  }

  /// Apply a backend availability probe without ever deriving a path from
  /// metadata.  Matching uses chapter, persisted source index and name, with
  /// FIFO queues for malformed records that repeat the same tuple.  A probe
  /// that explicitly reports a page as missing clears any stale path from the
  /// base record; an empty/partial probe leaves unmatched records untouched so
  /// an older backend cannot erase otherwise useful compatibility metadata.
  static List<DlImage> mergeLocalAvailability(
    List<DlImage> base,
    List<DlImage> availability,
  ) {
    if (availability.isEmpty) {
      return List.unmodifiable(base);
    }
    final candidates = <String, List<DlImage>>{};
    for (final item in availability) {
      final key = _availabilityKey(item);
      (candidates[key] ??= <DlImage>[]).add(item);
    }
    return List.unmodifiable(
      base.map((item) {
        final queue = candidates[_availabilityKey(item)];
        if (queue == null || queue.isEmpty) {
          return item;
        }
        final candidate = queue.removeAt(0);
        final path = candidate.localPath?.trim();
        final available =
            candidate.localAvailable && path != null && path.isNotEmpty;
        return item.copyWithAvailability(
          localPath: available ? path : null,
          localAvailable: available,
          localState:
              candidate.localState ?? (available ? 'available' : 'missing'),
          replaceLocalPath: true,
          replaceLocalState: true,
        );
      }),
    );
  }

  static String _availabilityKey(DlImage image) =>
      '${image.albumId}\u0000${image.chapterId}\u0000${image.imageIndex}\u0000${image.name.trim()}';

  static List<PageDescriptor> _markDuplicates(
    Iterable<PageDescriptor> descriptors,
  ) {
    final seen = <String>{};
    return List.unmodifiable(
      descriptors.map((page) {
        final normalized = page.name.trim();
        final duplicate = normalized.isNotEmpty && !seen.add(normalized);
        return page.copyWith(isDuplicateName: duplicate);
      }),
    );
  }
}
