import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;

/// A registrar-neutral representation of a ZIP archive and any nested ZIPs.
///
/// PDF replacement is addressed by [ArchivePdfEntry.archivePath], while every
/// other entry is retained as-is when [rebuild] creates a replacement archive.
/// Entry order is preserved from the decoded archive at every nesting level.
class ArchiveManifest {
  final List<_ArchiveManifestEntry> _entries;

  const ArchiveManifest._(this._entries);

  factory ArchiveManifest.decode(Uint8List zipBytes) {
    return ArchiveManifest._(_decodeEntries(zipBytes));
  }

  List<ArchivePdfEntry> get pdfEntries {
    final entries = <ArchivePdfEntry>[];
    _collectPdfEntries(_entries, '', entries);
    return List.unmodifiable(entries);
  }

  /// Rebuilds the source archive, replacing only PDF paths supplied in
  /// [replacementPdfBytes]. All other entries, including nested companion
  /// files, remain in their original hierarchy and entry order.
  Uint8List rebuild(Map<String, Uint8List> replacementPdfBytes) {
    return _encodeEntries(_entries, '', replacementPdfBytes);
  }

  static List<_ArchiveManifestEntry> _decodeEntries(Uint8List zipBytes) {
    final decoded = archive.ZipDecoder().decodeBytes(zipBytes);
    return decoded.files
        .map((entry) => _ArchiveManifestEntry.fromArchiveFile(entry))
        .toList();
  }

  static void _collectPdfEntries(
    List<_ArchiveManifestEntry> entries,
    String prefix,
    List<ArchivePdfEntry> result,
  ) {
    for (final entry in entries) {
      final path = '$prefix${entry.name}';
      if (entry.children != null) {
        _collectPdfEntries(entry.children!, '$path!/', result);
      } else if (entry.isPdf) {
        result.add(ArchivePdfEntry(
          archivePath: path,
          sourceFileName: entry.name.split('/').last,
          pdfBytes: entry.bytes,
        ));
      }
    }
  }

  static Uint8List _encodeEntries(
    List<_ArchiveManifestEntry> entries,
    String prefix,
    Map<String, Uint8List> replacements,
  ) {
    final output = archive.Archive();
    for (final entry in entries) {
      final path = '$prefix${entry.name}';
      if (entry.isDirectory) {
        output.addFile(archive.ArchiveFile.noCompress(entry.name, 0, <int>[]));
        continue;
      }

      final bytes = entry.children != null
          ? _encodeEntries(entry.children!, '$path!/', replacements)
          : replacements[path] ?? entry.bytes;
      output.addFile(archive.ArchiveFile(entry.name, bytes.length, bytes));
    }

    final bytes = archive.ZipEncoder().encode(output);
    if (bytes == null) {
      throw Exception('Failed to rebuild ZIP archive.');
    }
    return Uint8List.fromList(bytes);
  }
}

class ArchivePdfEntry {
  final String archivePath;
  final String sourceFileName;
  final Uint8List pdfBytes;

  const ArchivePdfEntry({
    required this.archivePath,
    required this.sourceFileName,
    required this.pdfBytes,
  });
}

class _ArchiveManifestEntry {
  final String name;
  final bool isDirectory;
  final Uint8List bytes;
  final List<_ArchiveManifestEntry>? children;

  const _ArchiveManifestEntry({
    required this.name,
    required this.isDirectory,
    required this.bytes,
    this.children,
  });

  bool get isPdf => name.toLowerCase().endsWith('.pdf');

  factory _ArchiveManifestEntry.fromArchiveFile(archive.ArchiveFile entry) {
    final bytes = entry.isFile
        ? Uint8List.fromList(entry.content as List<int>)
        : Uint8List(0);
    final isNestedZip =
        entry.isFile && entry.name.toLowerCase().endsWith('.zip');

    if (isNestedZip) {
      try {
        return _ArchiveManifestEntry(
          name: entry.name,
          isDirectory: false,
          bytes: bytes,
          children: ArchiveManifest._decodeEntries(bytes),
        );
      } catch (_) {
        // A ZIP entry can be encrypted or malformed. Preserve its original
        // bytes rather than making archive-format assumptions here.
      }
    }

    return _ArchiveManifestEntry(
      name: entry.name,
      isDirectory: !entry.isFile,
      bytes: bytes,
    );
  }
}
