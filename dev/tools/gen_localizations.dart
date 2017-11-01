// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This program generates a Dart "localizations" Map definition that combines
// the contents of the arb files. The map can be used to lookup a localized
// string: `localizations[localeString][resourceId]`.
//
// The *.arb files are in packages/flutter_localizations/lib/src/l10n.
//
// The arb (JSON) format files must contain a single map indexed by locale.
// Each map value is itself a map with resource identifier keys and localized
// resource string values.
//
// The arb filenames are expected to have the form "material_(\w+)\.arb", where
// the group following "_" identifies the language code and the country code,
// e.g. "material_en.arb" or "material_en_GB.arb". In most cases both codes are
// just two characters.
//
// This app is typically run by hand when a module's .arb files have been
// updated.
//
// ## Usage
//
// Run this program from the root of the git repository.
//
// The following outputs the generated Dart code to the console as a dry run:
//
// ```
// dart dev/tools/gen_localizations.dart
// ```
//
// If the data looks good, use the `-w` option to overwrite the
// packages/flutter_localizations/lib/src/l10n/localizations.dart file:
//
// ```
// dart dev/tools/gen_localizations.dart --overwrite
// ```

import 'dart:convert' show JSON;
import 'dart:io';

import 'package:path/path.dart' as pathlib;

import 'localizations_utils.dart';
import 'localizations_validator.dart';

const String outputHeader = '''
// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This file has been automatically generated.  Please do not edit it manually.
// To regenerate the file, use:
// @(regenerate)
''';

/// Maps locales to resource key/value pairs.
final Map<String, Map<String, String>> localeToResources = <String, Map<String, String>>{};

/// Maps locales to resource attributes.
///
/// See also https://github.com/googlei18n/app-resource-bundle/wiki/ApplicationResourceBundleSpecification#resource-attributes
final Map<String, Map<String, dynamic>> localeToResourceAttributes = <String, Map<String, dynamic>>{};

// Return s as a Dart-parseable raw string in single or double quotes. Expand double quotes:
// foo => r'foo'
// foo "bar" => r'foo "bar"'
// foo 'bar' => r'foo ' "'" r'bar' "'"
String generateString(String s) {
  if (!s.contains("'"))
    return "r'$s'";

  final StringBuffer output = new StringBuffer();
  bool started = false; // Have we started writing a raw string.
  for (int i = 0; i < s.length; i++) {
    if (s[i] == "'") {
      if (started)
        output.write("'");
      output.write(' "\'" ');
      started = false;
    } else if (!started) {
      output.write("r'${s[i]}");
      started = true;
    } else {
      output.write(s[i]);
    }
  }
  if (started)
    output.write("'");
  return output.toString();
}

String generateLocalizationsMap() {
  final StringBuffer output = new StringBuffer();

  output.writeln('''
/// Maps from [Locale.languageCode] to a map that contains the localized strings
/// for that locale.
///
/// This variable is used by [MaterialLocalizations].
const Map<String, Map<String, String>> localizations = const <String, Map<String, String>> {''');

  for (String locale in localeToResources.keys.toList()..sort()) {
    output.writeln("  '$locale': const <String, String>{");

    final Map<String, String> resources = localeToResources[locale];
    for (String name in resources.keys) {
      final String value = generateString(resources[name]);
      output.writeln("    '$name': $value,");
    }
    output.writeln('  },');
  }

  output.writeln('};');
  return output.toString();
}

void processBundle(File file, String locale) {
  localeToResources[locale] ??= <String, String>{};
  localeToResourceAttributes[locale] ??= <String, dynamic>{};
  final Map<String, String> resources = localeToResources[locale];
  final Map<String, dynamic> attributes = localeToResourceAttributes[locale];
  final Map<String, dynamic> bundle = JSON.decode(file.readAsStringSync());
  for (String key in bundle.keys) {
    // The ARB file resource "attributes" for foo are called @foo.
    if (key.startsWith('@'))
      attributes[key.substring(1)] = bundle[key];
    else
      resources[key] = bundle[key];
  }
}

void main(List<String> rawArgs) {
  checkCwdIsRepoRoot('gen_localizations');
  final GeneratorOptions options = parseArgs(rawArgs);

  // filenames are assumed to end in "prefix_lc.arb" or "prefix_lc_cc.arb", where prefix
  // is the 2nd command line argument, lc is a language code and cc is the country
  // code. In most cases both codes are just two characters.

  final Directory directory = new Directory(pathlib.join('packages', 'flutter_localizations', 'lib', 'src', 'l10n'));
  final RegExp filenameRE = new RegExp(r'material_(\w+)\.arb$');

  for (FileSystemEntity entity in directory.listSync()) {
    final String path = entity.path;
    if (FileSystemEntity.isFileSync(path) && filenameRE.hasMatch(path)) {
      final String locale = filenameRE.firstMatch(path)[1];
      processBundle(new File(path), locale);
    }
  }
  validateLocalizations(localeToResources, localeToResourceAttributes);

  final String regenerate = 'dart dev/tools/gen_localizations.dart --overwrite';
  final StringBuffer buffer = new StringBuffer();
  buffer.writeln(outputHeader.replaceFirst('@(regenerate)', regenerate));
  buffer.writeln(generateLocalizationsMap());

  if (options.writeToFile) {
    final File localizationsFile = new File(pathlib.join(directory.path, 'localizations.dart'));
    localizationsFile.writeAsStringSync('$buffer');
  } else {
    print(buffer);
  }
}
