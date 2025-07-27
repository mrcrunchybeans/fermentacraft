import 'package:logger/logger.dart';

final logger = Logger(
  level: const bool.fromEnvironment('dart.vm.product') ? Level.warning : Level.debug,
  printer: PrettyPrinter(
    methodCount: 1,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: true,  ),
);
