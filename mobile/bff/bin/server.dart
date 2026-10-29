import 'dart:io';

import 'package:aves_bff/app.dart';
import 'package:aves_bff/config.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final config = BffConfig.desdeEntorno();
  final manejador = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(construirManejador(config));

  final servidor =
      await io.serve(manejador, InternetAddress.anyIPv4, config.puerto);
  stdout.writeln(
    'BFF escuchando en :${servidor.port} -> backend ${config.backendUrl}'
    '${config.servicioConfigurado ? ' (cuenta de servicio activa)' : ''}',
  );

  Future<void> cerrar(ProcessSignal _) async {
    await servidor.close(force: false);
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(cerrar);
  try {
    // SIGTERM es el que manda Docker; no existe en Windows.
    ProcessSignal.sigterm.watch().listen(cerrar);
  } on SignalException {
    // Plataforma sin SIGTERM: basta con SIGINT.
  }
}
