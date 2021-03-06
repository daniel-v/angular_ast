// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:angular_ast/src/ast.dart';
import 'package:angular_ast/src/exception_handler/exception_handler.dart';
import 'package:angular_ast/src/parser/reader.dart';
import 'package:angular_ast/src/token/tokens.dart';
import 'package:source_span/source_span.dart';

/// A recursive descent AST parser from a series of tokens.
class RecursiveAstParser {
  final NgTokenReversibleReader _reader;
  final SourceFile _source;
  final List<String> _voidElements;
  final exceptionHandler;

  RecursiveAstParser(
    SourceFile sourceFile,
    Iterable<NgToken> tokens,
    this._voidElements,
    this.exceptionHandler,
  )
      : _reader = new NgTokenReversibleReader<NgTokenType>(sourceFile, tokens),
        _source = sourceFile;

  /// Iterates through and returns the top-level AST nodes from the tokens.
  List<StandaloneTemplateAst> parse() {
    // Start with an empty list.
    var nodes = <StandaloneTemplateAst>[];
    NgToken token;
    // Iterate through until and wait until EOF.
    //
    // Collects comments, elements, and text.
    //
    // Any other AST structure should be handled by the parseElement case.
    while ((token = _reader.next()) != null) {
      nodes.add(parseStandalone(token));
    }

    // Return the collected nodes.
    return nodes;
  }

  /// Parses and returns a [CloseElementAst].
  CloseElementAst parseCloseElement(NgToken beginToken) {
    var nameToken = _reader.next();
    if (_voidElements.contains(nameToken.lexeme)) {
      exceptionHandler.handle(new AngularParserException(
        NgParserWarningCode.VOID_ELEMENT_IN_CLOSE_TAG,
        nameToken.offset,
        nameToken.length,
      ));
    }

    while (_reader.peekType() == NgTokenType.whitespace) {
      _reader.next();
    }
    var closeElementEnd = _reader.next();
    return new CloseElementAst.parsed(
      _source,
      beginToken,
      nameToken,
      closeElementEnd,
    );
  }

  /// Parses and returns a comment beginning at the token provided.
  CommentAst parseComment(NgToken beginToken) {
    NgToken valueToken;
    if (_reader.peekType() == NgTokenType.commentEnd) {
      valueToken = new NgToken.commentValue(_reader.peek().offset, '');
    } else {
      valueToken = _reader.next();
    }
    var endToken = _reader.next();
    return new CommentAst.parsed(
      _source,
      beginToken,
      valueToken,
      endToken,
    );
  }

  /// Parses and returns a template AST beginning at the token provided.
  /// No desugaring of any kind occurs here.
  TemplateAst parseDecorator(NgToken beginToken) {
    // The first token is the decorator/name.
    NgToken prefixToken;
    NgToken decoratorToken;
    NgToken suffixToken;

    var peekType = _reader.peekType();
    if (peekType == NgTokenType.bananaPrefix ||
        peekType == NgTokenType.eventPrefix ||
        peekType == NgTokenType.propertyPrefix) {
      prefixToken = _reader.next();
      decoratorToken = _reader.next();
      suffixToken = _reader.next();
    } else if (peekType == NgTokenType.referencePrefix ||
        peekType == NgTokenType.templatePrefix) {
      prefixToken = _reader.next();
      decoratorToken = _reader.next();
    } else {
      decoratorToken = _reader.next();
    }

    NgAttributeValueToken valueToken;
    NgToken equalSignToken;

    if (_reader.peekTypeIgnoringType(NgTokenType.whitespace) ==
        NgTokenType.beforeElementDecoratorValue) {
      _consumeWhitespaces();
      equalSignToken = _reader.next();
      _consumeWhitespaces();
      valueToken = _reader.next() as NgAttributeValueToken;
    }

    if (prefixToken != null) {
      var prefixType = prefixToken.type;

      if (prefixType == NgTokenType.bananaPrefix) {
        return new BananaAst.parsed(
          _source,
          beginToken,
          prefixToken,
          decoratorToken,
          suffixToken,
          valueToken,
          equalSignToken,
        );
      } else if (prefixType == NgTokenType.eventPrefix) {
        if (decoratorToken.lexeme.split('.').length > 2) {
          exceptionHandler.handle(new AngularParserException(
            NgParserWarningCode.EVENT_NAME_TOO_MANY_FIXES,
            decoratorToken.offset,
            decoratorToken.length,
          ));
        }

        return new EventAst.parsed(
          _source,
          beginToken,
          prefixToken,
          decoratorToken,
          suffixToken,
          valueToken,
          equalSignToken,
        );
      } else if (prefixType == NgTokenType.propertyPrefix) {
        if (decoratorToken.lexeme.split('.').length > 3) {
          exceptionHandler.handle(new AngularParserException(
            NgParserWarningCode.PROPERTY_NAME_TOO_MANY_FIXES,
            decoratorToken.offset,
            decoratorToken.length,
          ));
        }

        return new PropertyAst.parsed(
          _source,
          beginToken,
          prefixToken,
          decoratorToken,
          suffixToken,
          valueToken,
          equalSignToken,
        );
      } else if (prefixType == NgTokenType.referencePrefix) {
        return new ReferenceAst.parsed(
          _source,
          beginToken,
          prefixToken,
          decoratorToken,
          valueToken,
          equalSignToken,
        );
      } else if (prefixType == NgTokenType.templatePrefix) {
        return new StarAst.parsed(
          _source,
          beginToken,
          prefixToken,
          decoratorToken,
          valueToken,
          equalSignToken,
        );
      }
    }

    // At this point, it is a TextAttribute, but handle cases
    // with 'on-' and 'bind-' prefix.
    if (decoratorToken.lexeme.startsWith('on-')) {
      var onToken = new NgToken.onPrefix(decoratorToken.offset);
      decoratorToken = new NgToken.elementDecorator(
        decoratorToken.offset + 'on-'.length,
        decoratorToken.lexeme.substring('on-'.length),
      );
      if (decoratorToken.lexeme == '') {
        exceptionHandler.handle(new AngularParserException(
          NgParserWarningCode.ELEMENT_DECORATOR_AFTER_PREFIX,
          onToken.offset,
          onToken.length,
        ));
      }
      return new EventAst.parsed(
        _source,
        beginToken,
        onToken,
        decoratorToken,
        null,
        valueToken,
        equalSignToken,
      );
    }
    if (decoratorToken.lexeme.startsWith('bind-')) {
      var bindToken = new NgToken.bindPrefix(decoratorToken.offset);
      decoratorToken = new NgToken.elementDecorator(
        decoratorToken.offset + 'bind-'.length,
        decoratorToken.lexeme.substring('bind-'.length),
      );
      if (decoratorToken.lexeme == '') {
        exceptionHandler.handle(new AngularParserException(
          NgParserWarningCode.ELEMENT_DECORATOR_AFTER_PREFIX,
          bindToken.offset,
          bindToken.length,
        ));
      }
      return new PropertyAst.parsed(
        _source,
        beginToken,
        bindToken,
        decoratorToken,
        null,
        valueToken,
        equalSignToken,
      );
    }
    return new AttributeAst.parsed(
      _source,
      beginToken,
      decoratorToken,
      valueToken,
      equalSignToken,
    );
  }

  /// Returns a DOM element AST starting at the provided token.
  ///
  /// It's possible the element will end up not being an [ElementAst].
  StandaloneTemplateAst parseElement(
      NgToken beginToken, Queue<String> tagStack) {
    var isTemplateElement = false;

    // Parse the element identifier.
    var nameToken = _reader.next();
    if (nameToken.lexeme == 'ng-content') {
      return parseEmbeddedContent(beginToken, nameToken);
    } else if (nameToken.lexeme == 'template') {
      isTemplateElement = true;
    }
    var isVoidElement = _voidElements.contains(nameToken.lexeme);

    // Start collecting decorators.
    var attributes = <AttributeAst>[];
    var childNodes = <StandaloneTemplateAst>[];
    var events = <EventAst>[];
    var properties = <PropertyAst>[];
    var references = <ReferenceAst>[];
    var bananas = <BananaAst>[];
    var stars = <StarAst>[];
    NgToken nextToken;

    // Start looping and get all of the decorators within the element.
    do {
      nextToken = _reader.next();
      if (nextToken.type == NgTokenType.beforeElementDecorator) {
        var decoratorAst = parseDecorator(nextToken);
        if (decoratorAst is AttributeAst) {
          attributes.add(decoratorAst);
        } else if (decoratorAst is StarAst) {
          if (isTemplateElement) {
            exceptionHandler.handle(new AngularParserException(
              NgParserWarningCode.INVALID_DECORATOR_IN_TEMPLATE,
              decoratorAst.beginToken.offset,
              decoratorAst.endToken.end - decoratorAst.beginToken.offset,
            ));
          } else {
            if (stars.isNotEmpty) {
              exceptionHandler.handle(new AngularParserException(
                NgParserWarningCode.DUPLICATE_STAR_DIRECTIVE,
                decoratorAst.beginToken.offset,
                decoratorAst.endToken.end - decoratorAst.beginToken.offset,
              ));
            } else {
              stars.add(decoratorAst);
            }
          }
        } else if (decoratorAst is EventAst) {
          events.add(decoratorAst);
        } else if (decoratorAst is PropertyAst) {
          properties.add(decoratorAst);
        } else if (decoratorAst is BananaAst) {
          if (isTemplateElement) {
            exceptionHandler.handle(new AngularParserException(
              NgParserWarningCode.INVALID_DECORATOR_IN_TEMPLATE,
              decoratorAst.beginToken.offset,
              decoratorAst.endToken.end - decoratorAst.beginToken.offset,
            ));
          } else {
            bananas.add(decoratorAst);
          }
        } else if (decoratorAst is ReferenceAst) {
          references.add(decoratorAst);
        } else {
          throw new StateError('Invalid decorator AST: $decoratorAst');
        }
      }
    } while (nextToken.type != NgTokenType.openElementEnd &&
        nextToken.type != NgTokenType.openElementEndVoid);

    if (!isVoidElement && nextToken.type == NgTokenType.openElementEndVoid) {
      exceptionHandler.handle(new AngularParserException(
        NgParserWarningCode.NONVOID_ELEMENT_USING_VOID_END,
        nextToken.offset,
        nextToken.length,
      ));
      nextToken = new NgToken.generateErrorSynthetic(
        nextToken.offset,
        NgTokenType.openElementEnd,
      );
    }
    var endToken = nextToken;
    CloseElementAst closeElementAst;

    // If not a void element, look for closing tag OR child nodes.
    if (!isVoidElement && nextToken.type != NgTokenType.openElementEndVoid) {
      tagStack.addFirst(nameToken.lexeme);
      var closingTagFound = false;

      while (!closingTagFound) {
        nextToken = _reader.next();
        if (nextToken == null) {
          exceptionHandler.handle(new AngularParserException(
            NgParserWarningCode.CANNOT_FIND_MATCHING_CLOSE,
            beginToken.offset,
            endToken.end - beginToken.offset,
          ));
          closeElementAst = new CloseElementAst(nameToken.lexeme);
          closingTagFound = true;
        } else if (nextToken.type == NgTokenType.closeElementStart) {
          var closeNameToken = _reader.peek();
          var closeIdentifier = closeNameToken.lexeme;
          if (closeIdentifier != nameToken.lexeme) {
            // Found a closing tag, but not matching current [ElementAst].
            // Generate initial error code; could be dangling or unmatching.
            if (tagStack.contains(closeIdentifier)) {
              // If the closing tag is in the seen [ElementAst] stack,
              // leave it alone. Instead create a synthetic close.
              _reader.putBack(nextToken);
              closeElementAst = new CloseElementAst(nameToken.lexeme);
              closingTagFound = true;
              exceptionHandler.handle(new AngularParserException(
                NgParserWarningCode.CANNOT_FIND_MATCHING_CLOSE,
                beginToken.offset,
                endToken.end - beginToken.offset,
              ));
            } else {
              // If the closing tag is not in the stack, create a synthetic
              // [ElementAst] to pair the dangling close and add as child.
              var closeComplement = parseCloseElement(nextToken);
              exceptionHandler.handle(new AngularParserException(
                NgParserWarningCode.DANGLING_CLOSE_ELEMENT,
                closeComplement.beginToken.offset,
                closeComplement.endToken.end -
                    closeComplement.beginToken.offset,
              ));
              if (closeIdentifier == 'ng-content') {
                var synthContent = new EmbeddedContentAst();
                synthContent.closeComplement = closeComplement;
                childNodes.add(synthContent);
              } else if (closeIdentifier == 'template') {
                var synthTemplate = new EmbeddedTemplateAst();
                synthTemplate.closeComplement = closeComplement;
                childNodes.add(synthTemplate);
              } else {
                var synthOpenElement =
                    new ElementAst(closeNameToken.lexeme, closeComplement);
                childNodes.add(synthOpenElement);
              }
            }
          } else {
            closeElementAst = parseCloseElement(nextToken);
            closingTagFound = true;
          }
        } else {
          var childAst = parseStandalone(nextToken, tagStack);
          childNodes.add(childAst);
        }
      }
      tagStack.removeFirst();
    }

    if (isTemplateElement) {
      return new EmbeddedTemplateAst.parsed(
        _source,
        beginToken,
        endToken,
        closeComplement: closeElementAst,
        attributes: attributes,
        childNodes: childNodes,
        events: events,
        properties: properties,
        references: references,
      );
    } else {
      return new ElementAst.parsed(
        _source,
        beginToken,
        nameToken,
        endToken,
        attributes: attributes,
        childNodes: childNodes,
        events: events,
        properties: properties,
        references: references,
        bananas: bananas,
        stars: stars,
        closeComplement: closeElementAst,
      );
    }
  }

  /// Returns and parses an embedded content directive/transclusions.
  EmbeddedContentAst parseEmbeddedContent(
      NgToken beginToken, NgToken elementIdentifierToken) {
    NgToken selectToken, equalSign, endToken;
    NgAttributeValueToken valueToken;
    var selectAttributeFound = false;
    CloseElementAst closeElementAst;

    // Ensure that ng-content has only 'select' attribute, if any. Also
    // catch for multiple 'select'; if multiple, accept the first one seen.
    while (_reader.peekType() == NgTokenType.beforeElementDecorator) {
      var startOffset = _reader.next().offset;
      var nextToken = _reader.next();

      if (nextToken.type != NgTokenType.elementDecorator ||
          nextToken.lexeme != 'select') {
        var endOffset = _accumulateInvalidNgContentDecoratorValue(nextToken);
        var e = new AngularParserException(
          NgParserWarningCode.INVALID_DECORATOR_IN_NGCONTENT,
          startOffset,
          endOffset - startOffset,
        );
        exceptionHandler.handle(e);
      } else {
        if (selectAttributeFound) {
          var endOffset = _accumulateInvalidNgContentDecoratorValue(nextToken);
          var e = new AngularParserException(
            NgParserWarningCode.DUPLICATE_SELECT_DECORATOR,
            startOffset,
            endOffset - startOffset,
          );
          exceptionHandler.handle(e);
        } else {
          selectAttributeFound = true;
          selectToken = nextToken;
          _consumeWhitespaces();
          if (_reader.peekType() == NgTokenType.beforeElementDecoratorValue) {
            equalSign = _reader.next();
            _consumeWhitespaces();
            valueToken = _reader.next();
          }
        }
      }
    }

    _consumeWhitespaces();

    // Ensure closed by '>' and not '/>'.
    endToken = _reader.next();
    if (endToken.type == NgTokenType.openElementEndVoid) {
      var e = new AngularParserException(
        NgParserWarningCode.NONVOID_ELEMENT_USING_VOID_END,
        endToken.offset,
        endToken.length,
      );
      exceptionHandler.handle(e);
      endToken = new NgToken.generateErrorSynthetic(
        endToken.offset,
        NgTokenType.openElementEnd,
      );
    }

    // Ensure closing </ng-content> exists.
    if (_reader.peekType() != NgTokenType.closeElementStart) {
      var e = new AngularParserException(
        NgParserWarningCode.NGCONTENT_MUST_CLOSE_IMMEDIATELY,
        beginToken.offset,
        endToken.end - beginToken.offset,
      );
      exceptionHandler.handle(e);
      closeElementAst = new CloseElementAst('ng-content');
    } else {
      var closeElementStart = _reader.next();
      var closeElementName = _reader.peek().lexeme;

      if (closeElementName != 'ng-content') {
        var e = new AngularParserException(
          NgParserWarningCode.NGCONTENT_MUST_CLOSE_IMMEDIATELY,
          beginToken.offset,
          endToken.end - beginToken.offset,
        );
        exceptionHandler.handle(e);
        _reader.putBack(closeElementStart);
        closeElementAst = new CloseElementAst('ng-content');
      } else {
        closeElementAst = parseCloseElement(closeElementStart);
      }
    }
    return new EmbeddedContentAst.parsed(
      _source,
      beginToken,
      elementIdentifierToken,
      endToken,
      closeElementAst,
      selectToken,
      equalSign,
      valueToken,
    );
  }

  /// Helper function that accumulates all parts of attribute-value variant
  /// and returns the end offset at where it finishes. Should be used to gather
  /// any non-'select' decorator. Consumes all necessary erroneous tokens.
  int _accumulateInvalidNgContentDecoratorValue(NgToken nextToken) {
    NgToken lastConsumedToken;
    if (nextToken.type == NgTokenType.bananaPrefix ||
        nextToken.type == NgTokenType.eventPrefix ||
        nextToken.type == NgTokenType.propertyPrefix) {
      lastConsumedToken = _reader.next(); // Decorator
      lastConsumedToken = _reader.next(); // Suffix
    } else if (nextToken.type == NgTokenType.templatePrefix ||
        nextToken.type == NgTokenType.referencePrefix) {
      lastConsumedToken = _reader.next(); // Decorator
    }
    if (_reader.peekTypeIgnoringType(NgTokenType.whitespace) ==
        NgTokenType.beforeElementDecoratorValue) {
      _consumeWhitespaces();
      if (_reader.peekType() == NgTokenType.beforeElementDecoratorValue) {
        lastConsumedToken = _reader.next(); // '=' sign
      }
      _consumeWhitespaces();
      lastConsumedToken = _reader.next(); // Attribute value
    }
    return lastConsumedToken?.end ?? nextToken.end;
  }

  /// Returns and parses an interpolation AST.
  InterpolationAst parseInterpolation(NgToken beginToken) {
    var valueToken = _reader.next();
    var endToken = _reader.next();
    return new InterpolationAst.parsed(
      _source,
      beginToken,
      valueToken,
      endToken,
    );
  }

  /// Returns and parses a top-level AST structure.
  StandaloneTemplateAst parseStandalone(
    NgToken token, [
    Queue<String> tagStack,
  ]) {
    tagStack = tagStack ?? new Queue();
    switch (token.type) {
      case NgTokenType.commentStart:
        return parseComment(token);
      case NgTokenType.openElementStart:
        return parseElement(token, tagStack);
      case NgTokenType.interpolationStart:
        return parseInterpolation(token);
      case NgTokenType.text:
        return parseText(token);
      // Dangling close tag. If error recovery is enabled, returns
      // a synthetic open with the dangling close. If not enabled,
      // simply throws error.
      case NgTokenType.closeElementStart:
        var danglingCloseIdentifier = _reader.peek().lexeme;
        var closeComplement = parseCloseElement(token);
        exceptionHandler.handle(new AngularParserException(
          NgParserWarningCode.DANGLING_CLOSE_ELEMENT,
          closeComplement.beginToken.offset,
          closeComplement.endToken.end - closeComplement.beginToken.offset,
        ));
        if (danglingCloseIdentifier == 'ng-content') {
          var synthOpenElement = new EmbeddedContentAst();
          synthOpenElement.closeComplement = closeComplement;
          return synthOpenElement;
        } else {
          var synthOpenElement =
              new ElementAst(danglingCloseIdentifier, closeComplement);
          return synthOpenElement;
        }
        break;
      default:
        // Simply throw error here; should never hit.
        if (exceptionHandler is RecoveringExceptionHandler) {
          // Throw an error here - this should never hit in recovery mode
          // unless something went really wrong. If so, FIX IT ASAP!
          throw new Exception('Non-standalone starting token found!');
        }
        exceptionHandler.handle(new AngularParserException(
          NgParserWarningCode.EXPECTED_STANDALONE,
          token.offset,
          token.length,
        ));
        return null;
    }
  }

  void _consumeWhitespaces() {
    while (_reader.peekType() != null &&
        _reader.peekType() == NgTokenType.whitespace) {
      _reader.next();
    }
  }

  /// Returns and parses a text AST.
  TextAst parseText(NgToken token) => new TextAst.parsed(_source, token);
}
