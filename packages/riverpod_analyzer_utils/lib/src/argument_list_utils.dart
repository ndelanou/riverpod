import 'package:analyzer/dart/ast/ast.dart';
import 'package:meta/meta.dart';

/// Utilities for [ArgumentList] to help with specific argument retrieval.
@internal
extension ArgumentListUtils on ArgumentList {
  /// Lists the positional arguments of an argument list.
  Iterable<Expression> positionalArguments() {
    return arguments.whereType<Expression>();
  }

  /// Lists the named arguments of an argument list.
  Iterable<NamedArgument> namedArguments() {
    return arguments.whereType<NamedArgument>();
  }
}
