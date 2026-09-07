import 'package:analyzer/dart/element/element.dart';
import 'package:riverpod_analyzer_utils/riverpod_analyzer_utils.dart';
import 'package:source_gen/source_gen.dart';

void validateClassBasedProvider(ClassBasedProviderDeclaration provider) {
  final classElement = provider.node.declaredFragment?.element;

  // Assert that the class is not abstract
  if (provider.node.abstractKeyword != null) {
    throw InvalidGenerationSourceError(
      '`@riverpod` can only be used on concrete classes.',
      element: classElement,
    );
  }

  // Assert that the provider has a default constructor
  final constructor = classElement?.constructors
      .cast<ConstructorElement?>()
      .firstWhere((e) => e?.isDefaultConstructor ?? false, orElse: () => null);
  if (constructor == null) {
    throw InvalidGenerationSourceError(
      'The class ${provider.name.lexeme} must have a default constructor.',
      element: classElement,
    );
  }

  // Assert that the default constructor can be called with no parameter
  if (constructor.formalParameters.any((e) => e.isRequired)) {
    throw InvalidGenerationSourceError(
      'The default constructor of ${provider.name.lexeme} must have not have required parameters.',
      element: constructor,
    );
  }
}
