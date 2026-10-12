import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: _bindgenEnvironment(input),
    ).run(input: input, output: output);
  });
}

// Android bindings and compiled C code must use the manifest's minimum API.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) return const {};
  final llvmRoot = File.fromUri(compiler).parent.parent;
  String? libclangPath;
  final externalPath = input.userDefines['libclang_path'];
  if (externalPath is String && externalPath.isNotEmpty) {
    final directory = Directory(externalPath);
    if (!directory.existsSync() || !directory.listSync().any(_isLibclang)) {
      throw StateError('libclang_path does not contain a libclang library');
    }
    libclangPath = directory.path;
  }
  for (final name in const ['lib', 'lib64', 'bin']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (libclangPath == null &&
        directory.existsSync() &&
        directory.listSync().any(_isLibclang)) {
      libclangPath = directory.path;
    }
  }
  if (libclangPath == null) {
    throw StateError(
      'No libclang under ${llvmRoot.path} (lib, lib64 or bin); the NDK Flutter '
      'passed cannot run bindgen for rquickjs. Windows builders must configure '
      'hooks.user_defines.rust_api.libclang_path with an external LLVM library',
    );
  }
  final (
    rustTriple,
    ndkTriple,
    headerTriple,
  ) = switch (input.config.code.targetArchitecture) {
    Architecture.arm64 => (
      'aarch64-linux-android',
      'aarch64-linux-android',
      'aarch64-linux-android',
    ),
    Architecture.arm => (
      'armv7-linux-androideabi',
      'armv7a-linux-androideabi',
      'arm-linux-androideabi',
    ),
    Architecture.x64 => (
      'x86_64-linux-android',
      'x86_64-linux-android',
      'x86_64-linux-android',
    ),
    _ => throw UnsupportedError('Unsupported Android Rust architecture'),
  };
  final api = input.config.code.android.targetNdkApi;
  final suffix = Platform.isWindows ? '.cmd' : '';
  final cc = '${llvmRoot.path}/bin/$ndkTriple$api-clang$suffix';
  final cxx = '${llvmRoot.path}/bin/$ndkTriple$api-clang++$suffix';
  if (!File(cc).existsSync() || !File(cxx).existsSync()) {
    throw StateError('NDK compilers for Android API $api are missing');
  }
  final resources = Directory('${llvmRoot.path}/lib/clang')
      .listSync()
      .whereType<Directory>()
      .where(
        (directory) => File('${directory.path}/include/stdbool.h').existsSync(),
      );
  if (resources.isEmpty) {
    throw StateError('NDK Clang resource headers are missing');
  }
  final resourcePath = resources.first.path.replaceAll(r'\', '/');
  final sysroot = '${llvmRoot.path}/sysroot'.replaceAll(r'\', '/');
  final envTriple = rustTriple.replaceAll('-', '_');
  return {
    'LIBCLANG_PATH': libclangPath,
    'CC_$envTriple': cc,
    'CXX_$envTriple': cxx,
    'CARGO_TARGET_${envTriple.toUpperCase()}_LINKER': cc,
    'BINDGEN_EXTRA_CLANG_ARGS_$envTriple':
        '--sysroot="$sysroot" -I"$sysroot/usr/include/$headerTriple" -resource-dir="$resourcePath" -D__ANDROID_API__=$api',
  };
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}
