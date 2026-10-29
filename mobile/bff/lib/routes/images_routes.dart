import 'dart:math';

import 'package:shelf/shelf.dart';

import '../backend/backend_client.dart';
import '../backend/catalog_cache.dart';
import '../backend/token_resolver.dart';
import '../errors.dart';
import '../http_utils.dart';
import '../mappers.dart';
import '../multipart.dart';

/// Contrato `/images` de la app -> `/api/photos`, `/api/sightings` y
/// `/api/reports` del backend.
class ImagesRoutes {
  ImagesRoutes({
    required this.backend,
    required this.catalogo,
    required this.tokens,
    required this.maxSubidaBytes,
  });

  final BackendClient backend;
  final CatalogCache catalogo;
  final TokenResolver tokens;
  final int maxSubidaBytes;

  /// `GET /images?categoria&pagina&por_pagina`
  ///
  /// La app pagina desde 0 y espera `paginado.total` como total de páginas.
  Future<Response> listar(Request request) async {
    final consulta = request.url.queryParameters;
    final categoria = consulta['categoria']?.trim() ?? '';
    if (categoria.isEmpty) {
      throw BffError(400, 'validacion', 'Falta el parámetro «categoria».');
    }
    final pagina = max(0, int.tryParse(consulta['pagina'] ?? '') ?? 0);
    final porPagina =
        min(50, max(1, int.tryParse(consulta['por_pagina'] ?? '') ?? 20));
    final clave = normalizar(categoria);

    return tokens.conTokenOServicio(request, (token) async {
      final categoriaId = await catalogo.categoriaId(clave, token);
      if (categoriaId == null) {
        // Categoría de la app que el backend aún no tiene: feed vacío, no un
        // error que rompa la pantalla.
        if (categoriasApp.contains(clave)) {
          return jsonResponse(200, {
            'urls': <Object>[],
            'paginado': {'pagina': pagina, 'total': 0},
          });
        }
        throw BffError(
          404,
          'categoria_no_encontrada',
          'La categoría no existe en el catálogo.',
        );
      }

      final respuesta = await backend.getJson(
        '/api/photos',
        consulta: {
          'category_id': categoriaId,
          'page': '${pagina + 1}',
          'per_page': '$porPagina',
        },
        token: token,
      );
      final cuerpo = comoMapa(respuesta);
      final fotos = (cuerpo['photos'] is List ? cuerpo['photos'] as List : [])
          .whereType<Map>()
          .map((s) => fotoDesdeSighting(
                Map<String, dynamic>.from(s),
                categoria: clave,
              ))
          .toList();

      final paginacion = cuerpo['pagination'];
      final cantidad = paginacion is Map ? paginacion['count'] : null;
      final hayMas = paginacion is Map && paginacion['more?'] == true;
      final total = cantidad is int
          ? totalPaginas(cantidad, porPagina)
          : (hayMas ? pagina + 2 : pagina + 1);

      return jsonResponse(200, {
        'urls': fotos,
        'paginado': {'pagina': pagina, 'total': total},
      });
    });
  }

  /// `POST /images` (multipart: file, categoria, lugar, fecha, comentario)
  Future<Response> subir(Request request) async {
    final token = tokens.requerir(request);
    final subida = await leerMultipart(request, maxBytes: maxSubidaBytes);
    final archivo = subida.archivo;
    if (archivo == null || archivo.bytes.isEmpty) {
      throw BffError(
        400,
        'validacion',
        'Falta el archivo de imagen en el campo «file».',
      );
    }

    final campos = subida.campos;
    final clave = normalizar(campos['categoria'] ?? '');
    final aveId = await _resolverAve(campos['bird_id'], clave, token);

    final comentario = _texto(campos['comentario']);
    final respuesta = await backend.postMultipart(
      '/api/sightings',
      bytes: archivo.bytes,
      nombreArchivo: archivo.nombre,
      contentType: archivo.contentType,
      token: token,
      campos: {
        // El backend exige lugar y fecha; la app los marca como opcionales.
        'place': _texto(campos['lugar']) ?? 'Sin especificar',
        'spotted_on': _fecha(campos['fecha']) ?? _hoy(),
        if (comentario != null)
          'comment':
              comentario.length > 500 ? comentario.substring(0, 500) : comentario,
        if (aveId != null) 'bird_id': aveId,
      },
    );
    final avistamiento = extraerMapa(respuesta, 'sighting');
    return jsonResponse(201, fotoDesdeSighting(avistamiento, categoria: clave));
  }

  /// `PUT /images?id=<foto>` (reportar) con `{motivo, detalle}`.
  Future<Response> reportar(Request request) async {
    final token = tokens.requerir(request);
    final id = request.url.queryParameters['id']?.trim() ?? '';
    if (id.isEmpty) {
      throw BffError(400, 'validacion', 'Falta el parámetro «id».');
    }
    final cuerpo = await leerJsonObjeto(request);
    final motivo = '${cuerpo['motivo'] ?? ''}';
    if (!motivosValidos.contains(motivo)) {
      throw BffError(400, 'validacion', 'Motivo de reporte no válido.');
    }
    var detalle = cuerpo['detalle']?.toString().trim();
    if (detalle != null && detalle.length > 500) {
      detalle = detalle.substring(0, 500);
    }

    final respuesta = await backend.postJson(
      '/api/reports',
      {'sighting_id': id, 'reason': razonDesdeMotivo(motivo, detalle)},
      token: token,
    );
    return jsonResponse(200, reporteDesdeBackend(extraerMapa(respuesta, 'report')));
  }

  /// Ave a la que se cuelga el avistamiento: la que mande la app (`bird_id`) o
  /// la primera de la categoría. Si no hay ninguna, el avistamiento se guarda
  /// sin ave (el backend lo permite), pero no aparecerá filtrado por categoría.
  Future<String?> _resolverAve(
    String? explicito,
    String clave,
    String token,
  ) async {
    final ave = explicito?.trim();
    if (ave != null && ave.isNotEmpty) return ave;
    if (clave.isEmpty) return null;
    try {
      final categoriaId = await catalogo.categoriaId(clave, token);
      if (categoriaId == null) return null;
      return await catalogo.aveGenerica(categoriaId, token);
    } on BackendException {
      return null;
    }
  }

  String? _texto(String? valor) {
    final texto = valor?.trim();
    return (texto == null || texto.isEmpty) ? null : texto;
  }

  String? _fecha(String? valor) {
    final texto = valor?.trim();
    if (texto == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(texto)) {
      return null;
    }
    return DateTime.tryParse(texto) == null ? null : texto;
  }

  String _hoy() => DateTime.now().toUtc().toIso8601String().substring(0, 10);
}
