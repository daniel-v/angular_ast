// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:angular_ast/angular_ast.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:quiver/core.dart';

final _listEquals = const ListEquality();

/// A de-sugared form of longer pseudo expression.
class NgMicroAst {
  /// What variable assignments were made.
  final List<ReferenceAst> assignments;

  /// What properties are bound.
  final List<PropertyAst> properties;

  @literal
  const NgMicroAst({
    @required this.assignments,
    @required this.properties,
  });

  @override
  bool operator ==(Object o) {
    if (o is NgMicroAst) {
      return _listEquals.equals(assignments, o.assignments) &&
          _listEquals.equals(properties, o.properties);
    }
    return false;
  }

  @override
  int get hashCode {
    return hash2(_listEquals.hash(assignments), _listEquals.hash(properties));
  }

  @override
  String toString() => '#$NgMicroAst <$assignments $properties>';
}
