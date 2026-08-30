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
  });

  final int position;
  final String name;
  final int width;
  final int height;
  final String key;
  final bool isDuplicateName;

  bool get hasName => name.trim().isNotEmpty;
  bool get hasDimensions => width > 0 && height > 0;
  bool get isUsable => hasName && !isDuplicateName;

  PageDescriptor copyWith({bool? isDuplicateName}) => PageDescriptor(
        position: position,
        name: name,
        width: width,
        height: height,
        key: key,
        isDuplicateName: isDuplicateName ?? this.isDuplicateName,
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
