// ignore_for_file: depend_on_referenced_packages

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final builder = CBuilder.library(
      name: 'sysres',
      assetName: 'libsysres',
      sources: [
        'lib/src/libsysres/cpu.c',
        'lib/src/libsysres/memory.c',
      ],
    );

    await builder.run(input: input, output: output);
  });
}
