// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Inlined from custom_lint_core (originally from source_gen) to avoid
// pulling in custom_lint_core/custom_lint_visitor which are incompatible
// with analyzer 11+.

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

/// An abstraction around doing static type checking at compile/build time.
abstract class TypeChecker {
  const TypeChecker._();

  /// Creates a new [TypeChecker] that delegates to other [checkers].
  const factory TypeChecker.any(Iterable<TypeChecker> checkers) = _AnyChecker;

  /// Creates a new [TypeChecker] that delegates to other [checkers].
  ///
  /// This implementation will return `true` if **all** the checkers match.
  const factory TypeChecker.every(Iterable<TypeChecker> checkers) =
      _EveryChecker;

  /// Create a new [TypeChecker] backed by a static [type].
  const factory TypeChecker.fromStatic(DartType type) = _LibraryTypeChecker;

  /// Checks that the element comes from a specific package.
  const factory TypeChecker.fromPackage(String packageName) = _PackageChecker;

  /// Checks that the element has a specific name, and optionally checks that it
  /// is defined from a specific package.
  const factory TypeChecker.fromName(
    String name, {
    String? packageName,
  }) = _NamedChecker;

  /// Create a new [TypeChecker] backed by a library [url].
  const factory TypeChecker.fromUrl(dynamic url) = _UriTypeChecker;

  /// Returns the first constant annotating [element] assignable to this type.
  DartObject? firstAnnotationOf(
    Element element, {
    bool throwOnUnresolved = true,
  }) {
    final annotations = element.metadata.annotations;
    if (annotations.isEmpty) {
      return null;
    }
    final results = annotationsOf(
      element,
      throwOnUnresolved: throwOnUnresolved,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Returns if a constant annotating [element] is assignable to this type.
  bool hasAnnotationOf(Element element, {bool throwOnUnresolved = true}) =>
      firstAnnotationOf(element, throwOnUnresolved: throwOnUnresolved) != null;

  /// Returns the first constant annotating [element] that is exactly this type.
  DartObject? firstAnnotationOfExact(
    Element element, {
    bool throwOnUnresolved = true,
  }) {
    final annotations = element.metadata.annotations;
    if (annotations.isEmpty) {
      return null;
    }
    final results = annotationsOfExact(
      element,
      throwOnUnresolved: throwOnUnresolved,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Returns if a constant annotating [element] is exactly this type.
  bool hasAnnotationOfExact(
    Element element, {
    bool throwOnUnresolved = true,
  }) =>
      firstAnnotationOfExact(
        element,
        throwOnUnresolved: throwOnUnresolved,
      ) !=
      null;

  DartObject? _computeConstantValue(
    Object element,
    ElementAnnotation annotation,
    int annotationIndex, {
    bool throwOnUnresolved = true,
  }) {
    final result = annotation.computeConstantValue();
    if (result == null && throwOnUnresolved && element is Element) {
      throw UnresolvedAnnotationException._from(element, annotationIndex);
    }
    return result;
  }

  /// Returns annotating constants on [element] assignable to this type.
  Iterable<DartObject> annotationsOf(
    Element element, {
    bool throwOnUnresolved = true,
  }) =>
      _annotationsWhere(
        element,
        isAssignableFromType,
        throwOnUnresolved: throwOnUnresolved,
      );

  Iterable<DartObject> _annotationsWhere(
    Element element,
    bool Function(DartType) predicate, {
    bool throwOnUnresolved = true,
  }) sync* {
    final annotations = element.metadata.annotations;
    for (var i = 0; i < annotations.length; i++) {
      final value = _computeConstantValue(
        element,
        annotations[i],
        i,
        throwOnUnresolved: throwOnUnresolved,
      );
      if (value?.type != null && predicate(value!.type!)) {
        yield value;
      }
    }
  }

  /// Returns annotating constants on [element] of exactly this type.
  Iterable<DartObject> annotationsOfExact(
    Element element, {
    bool throwOnUnresolved = true,
  }) =>
      _annotationsWhere(
        element,
        isExactlyType,
        throwOnUnresolved: throwOnUnresolved,
      );

  /// Returns `true` if the type of [element] can be assigned to this type.
  bool isAssignableFrom(Element element) =>
      isExactly(element) ||
      (element is InterfaceElement && element.allSupertypes.any(isExactlyType));

  /// Returns `true` if [staticType] can be assigned to this type.
  bool isAssignableFromType(DartType staticType) {
    final element = staticType.element;
    return element != null && isAssignableFrom(element);
  }

  /// Returns `true` if representing the exact same class as [element].
  bool isExactly(Element element);

  /// Returns `true` if representing the exact same type as [staticType].
  bool isExactlyType(DartType staticType) {
    final element = staticType.element;
    return element != null && isExactly(element);
  }

  /// Returns `true` if representing a super class of [element].
  bool isSuperOf(Element element) {
    if (element is InterfaceElement) {
      var theSuper = element.supertype;
      do {
        if (isExactlyType(theSuper!)) {
          return true;
        }
        theSuper = theSuper.superclass;
      } while (theSuper != null);
    }
    return false;
  }

  /// Returns `true` if representing a super type of [staticType].
  bool isSuperTypeOf(DartType staticType) {
    final element = staticType.element;
    return element != null && isSuperOf(element);
  }
}

class _LibraryTypeChecker extends TypeChecker {
  const _LibraryTypeChecker(this._type) : super._();
  final DartType _type;

  @override
  bool isExactly(Element element) =>
      element is InterfaceElement && element == _type.element;

  @override
  String toString() => _urlOfElement(_type.element!);
}

@immutable
class _PackageChecker extends TypeChecker {
  const _PackageChecker(this._packageName) : super._();
  final String _packageName;

  @override
  bool isExactly(Element element) {
    final targetUri = element.library?.uri;
    if (targetUri == null) return false;
    if (_packageName == targetUri.toString()) return true;
    final targetPackageName = targetUri.pathSegments.firstOrNull;
    return targetPackageName != null && targetPackageName == _packageName;
  }

  @override
  bool operator ==(Object o) =>
      o is _PackageChecker && o._packageName == _packageName;

  @override
  int get hashCode => Object.hash(runtimeType, _packageName);

  @override
  String toString() => _packageName;
}

@immutable
class _NamedChecker extends TypeChecker {
  const _NamedChecker(this._name, {this.packageName}) : super._();
  final String _name;
  final String? packageName;

  @override
  bool isExactly(Element element) {
    if (element.name != _name) return false;
    if (packageName == null) return true;
    final checker = _PackageChecker(packageName!);
    return checker.isExactly(element);
  }

  @override
  bool operator ==(Object o) =>
      o is _NamedChecker && o._name == _name && o.packageName == packageName;

  @override
  int get hashCode => Object.hash(runtimeType, _name, packageName);

  @override
  String toString() => '$packageName#$_name';
}

@immutable
class _UriTypeChecker extends TypeChecker {
  const _UriTypeChecker(dynamic url)
      : _url = '$url',
        super._();

  static final _cache = Expando<Uri>();
  final String _url;

  Uri get uri => _cache[this] ??= _normalizeUrl(Uri.parse(_url));

  bool hasSameUrl(dynamic url) =>
      uri.toString() ==
      (url is String ? url : _normalizeUrl(url as Uri).toString());

  @override
  bool isExactly(Element element) => hasSameUrl(_urlOfElement(element));

  @override
  bool operator ==(Object o) => o is _UriTypeChecker && o._url == _url;

  @override
  int get hashCode => _url.hashCode;

  @override
  String toString() => '$uri';
}

class _AnyChecker extends TypeChecker {
  const _AnyChecker(this._checkers) : super._();
  final Iterable<TypeChecker> _checkers;

  @override
  bool isExactly(Element element) => _checkers.any((c) => c.isExactly(element));
}

class _EveryChecker extends TypeChecker {
  const _EveryChecker(this._checkers) : super._();
  final Iterable<TypeChecker> _checkers;

  @override
  bool isExactly(Element element) =>
      _checkers.every((c) => c.isExactly(element));
}

/// Exception thrown when [TypeChecker] fails to resolve a metadata annotation.
class UnresolvedAnnotationException implements Exception {
  factory UnresolvedAnnotationException._from(
    Element annotatedElement,
    int annotationIndex,
  ) {
    final sourceSpan = _findSpan(annotatedElement, annotationIndex);
    return UnresolvedAnnotationException._(annotatedElement, sourceSpan);
  }

  const UnresolvedAnnotationException._(
    this.annotatedElement,
    this.annotationSource,
  );

  final Element annotatedElement;
  final SourceSpan? annotationSource;

  static SourceSpan? _findSpan(Element annotatedElement, int annotationIndex) {
    final parsedLibrary = annotatedElement.session!.getParsedLibraryByElement(
      annotatedElement.library!,
    ) as ParsedLibraryResult;
    final declaration = parsedLibrary.getFragmentDeclaration(
      annotatedElement.firstFragment,
    );
    if (declaration == null) {
      return null;
    }
    final node = declaration.node;
    final List<Annotation> metadata;
    if (node is AnnotatedNode) {
      metadata = node.metadata;
    } else if (node is FormalParameter) {
      metadata = node.metadata;
    } else {
      throw StateError(
        'Unhandled Annotated AST node type: ${node.runtimeType}',
      );
    }
    final annotation = metadata[annotationIndex];
    final start = annotation.offset;
    final end = start + annotation.length;
    final parsedUnit = declaration.parsedUnit!;
    return SourceSpan(
      SourceLocation(start, sourceUrl: parsedUnit.uri),
      SourceLocation(end, sourceUrl: parsedUnit.uri),
      parsedUnit.content.substring(start, end),
    );
  }

  @override
  String toString() {
    final message = 'Could not resolve annotation for `$annotatedElement`.';
    if (annotationSource != null) {
      return annotationSource!.message(message);
    }
    return message;
  }
}

String _urlOfElement(Element element) => element.kind == ElementKind.DYNAMIC
    ? 'dart:core#dynamic'
    : element.kind == ElementKind.NEVER
        ? 'dart:core#Never'
        : _normalizeUrl(element.library!.uri)
            .replace(fragment: element.name)
            .toString();

Uri _normalizeUrl(Uri url) {
  switch (url.scheme) {
    case 'dart':
      return _normalizeDartUrl(url);
    case 'package':
      return _packageToAssetUrl(url);
    case 'file':
      return _fileToAssetUrl(url);
    default:
      return url;
  }
}

Uri _normalizeDartUrl(Uri url) => url.pathSegments.isNotEmpty
    ? url.replace(pathSegments: url.pathSegments.take(1))
    : url;

Uri _fileToAssetUrl(Uri url) {
  if (!p.isWithin(p.url.current, url.path)) return url;
  return Uri(
    scheme: 'asset',
    path: p.join('', p.relative(url.path)),
  );
}

Uri _packageToAssetUrl(Uri url) => url.scheme == 'package'
    ? url.replace(
        scheme: 'asset',
        pathSegments: <String>[
          url.pathSegments.first,
          'lib',
          ...url.pathSegments.skip(1),
        ],
      )
    : url;
