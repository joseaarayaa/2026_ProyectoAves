import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Respuesta de error (o fallo de red) al hablar con el backend Phoenix.
class BackendException implements Exception {
  BackendException(this.statusCode, this.cuerpo);

  final int statusCode;
  final Object? cuerpo;

  /// Texto legible a partir de `{"error": "..."}` o `{"errors": [...]}`.
  String get mensaje {
    final c = cuerpo;
    if (c is Map) {
      final errores = c['errors'];
      if (errores is List && errores.isNotEmpty) {
        return errores
            .map((e) => e is Map ? (e['detail'] ?? e['message'] ?? e) : e)
            .join('\n');
      }
      final error = c['error'] ?? c['message'];
      if (error != null) return '$error';
    }
    return 'Error del servidor ($statusCode).';
  }

  @override
  String toString() => 'BackendException($statusCode): $mensaje';
}

/// Cliente HTTP del backend. Devuelve el JSON ya decodificado y lanza
/// [BackendException] ante cualquier status que no sea 2xx.
class BackendClient {
  BackendClient({
    required String baseUrl,
    http.Client? cliente,
    Duration tiempoLimite = const Duration(seconds: 15),
  })  : _base = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _cliente = cliente ?? http.Client(),
        _tiempoLimite = tiempoLimite;

  final String _base;
  final http.Client _cliente;
  final Duration _tiempoLimite;

  Uri _uri(String ruta, [Map<String, String>? consulta]) {
    final uri = Uri.parse('$_base$ruta');
    if (consulta == null || consulta.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...consulta});
  }

  Map<String, String> _cabeceras(String? token, {bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Object?> getJson(
    String ruta, {
    Map<String, String>? consulta,
    String? token,
  }) =>
      _enviar(() => _cliente.get(_uri(ruta, consulta), headers: _cabeceras(token)));

  Future<Object?> postJson(
    String ruta,
    Object? cuerpo, {
    String? token,
  }) =>
      _enviar(
        () => _cliente.post(
          _uri(ruta),
          headers: _cabeceras(token, json: true),
          body: jsonEncode(cuerpo ?? <String, dynamic>{}),
        ),
      );

  Future<Object?> delete(String ruta, {String? token}) =>
      _enviar(() => _cliente.delete(_uri(ruta), headers: _cabeceras(token)));

  /// Sube una foto como `multipart/form-data` en el campo `photo`, que es el
  /// que lee `SightingController`.
  Future<Object?> postMultipart(
    String ruta, {
    required List<int> bytes,
    required String nombreArchivo,
    required String contentType,
    Map<String, String> campos = const {},
    String? token,
  }) =>
      _enviar(() async {
        final solicitud = http.MultipartRequest('POST', _uri(ruta))
          ..headers.addAll(_cabeceras(token))
          ..fields.addAll(campos)
          ..files.add(
            http.MultipartFile.fromBytes(
              'photo',
              bytes,
              filename: nombreArchivo,
              contentType: MediaType.parse(contentType),
            ),
          );
        final streamed = await _cliente.send(solicitud);
        return http.Response.fromStream(streamed);
      });

  Future<Object?> _enviar(Future<http.Response> Function() peticion) async {
    final http.Response respuesta;
    try {
      respuesta = await peticion().timeout(_tiempoLimite);
    } on TimeoutException {
      throw BackendException(504, {
        'error': 'El backend tardó demasiado en responder.',
      });
    } on SocketException {
      throw BackendException(502, {
        'error': 'No se pudo conectar con el backend.',
      });
    } on http.ClientException {
      throw BackendException(502, {
        'error': 'No se pudo conectar con el backend.',
      });
    }

    final texto = utf8.decode(respuesta.bodyBytes, allowMalformed: true);
    Object? decodificado;
    if (texto.trim().isNotEmpty) {
      try {
        decodificado = jsonDecode(texto);
      } on FormatException {
        decodificado = null;
      }
    }
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return decodificado;
    }
    throw BackendException(respuesta.statusCode, decodificado);
  }
}
