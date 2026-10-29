import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'errors.dart';

Response jsonResponse(int status, Object? cuerpo) => Response(
      status,
      body: jsonEncode(cuerpo),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Token del header `Authorization: Bearer <token>`, o `null`.
String? bearer(Request request) {
  final cabecera = request.headers['authorization']?.trim();
  if (cabecera == null) return null;
  final coincidencia =
      RegExp(r'^Bearer\s+(\S+)$', caseSensitive: false).firstMatch(cabecera);
  return coincidencia?.group(1);
}

/// Cuerpo JSON de la petición como objeto. Vacío -> `{}`.
Future<Map<String, dynamic>> leerJsonObjeto(Request request) async {
  final texto = await request.readAsString();
  if (texto.trim().isEmpty) return <String, dynamic>{};
  try {
    final decodificado = jsonDecode(texto);
    if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
  } on FormatException {
    // se informa abajo
  }
  throw BffError(400, 'validacion', 'El cuerpo debe ser un objeto JSON.');
}

/// `cuerpo[clave]` como mapa; si el backend responde otra cosa, 502.
Map<String, dynamic> extraerMapa(Object? cuerpo, String clave) {
  if (cuerpo is Map && cuerpo[clave] is Map) {
    return Map<String, dynamic>.from(cuerpo[clave] as Map);
  }
  throw BffError(
    502,
    'respuesta_invalida',
    'El backend devolvió una respuesta inesperada.',
  );
}

/// El cuerpo completo como mapa; si no lo es, 502.
Map<String, dynamic> comoMapa(Object? cuerpo) {
  if (cuerpo is Map) return Map<String, dynamic>.from(cuerpo);
  throw BffError(
    502,
    'respuesta_invalida',
    'El backend devolvió una respuesta inesperada.',
  );
}
