import 'dart:io';

/// Configuración del BFF. Todo viene de variables de entorno; no hay claves
/// escritas en el código.
class BffConfig {
  const BffConfig({
    required this.backendUrl,
    this.puerto = 8080,
    this.servicioEmail,
    this.servicioPassword,
    this.aliasCategorias = const {},
    this.maxSubidaBytes = 5 * 1024 * 1024,
    this.tiempoLimite = const Duration(seconds: 15),
  });

  factory BffConfig.desdeEntorno([Map<String, String>? entorno]) {
    final env = entorno ?? Platform.environment;

    String? texto(String clave) {
      final valor = env[clave]?.trim();
      return (valor == null || valor.isEmpty) ? null : valor;
    }

    final alias = <String, String>{};
    for (final par in (texto('CATEGORY_ALIASES') ?? '').split(',')) {
      final partes = par.split('=');
      if (partes.length != 2) continue;
      final clave = partes[0].trim();
      final valor = partes[1].trim();
      if (clave.isNotEmpty && valor.isNotEmpty) alias[clave] = valor;
    }

    return BffConfig(
      backendUrl: texto('BACKEND_URL') ?? 'http://localhost:4000',
      puerto: int.tryParse(texto('PORT') ?? '') ?? 8080,
      servicioEmail: texto('SERVICE_EMAIL'),
      servicioPassword: texto('SERVICE_PASSWORD'),
      aliasCategorias: alias,
      maxSubidaBytes:
          int.tryParse(texto('MAX_UPLOAD_BYTES') ?? '') ?? 5 * 1024 * 1024,
      tiempoLimite: Duration(
        seconds: int.tryParse(texto('BACKEND_TIMEOUT_SECONDS') ?? '') ?? 15,
      ),
    );
  }

  final String backendUrl;
  final int puerto;
  final String? servicioEmail;
  final String? servicioPassword;

  /// Clave de categoría de la app -> nombre de categoría en el backend.
  final Map<String, String> aliasCategorias;
  final int maxSubidaBytes;
  final Duration tiempoLimite;

  bool get servicioConfigurado =>
      servicioEmail != null && servicioPassword != null;
}
