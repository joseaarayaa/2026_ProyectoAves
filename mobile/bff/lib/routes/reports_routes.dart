import 'package:shelf/shelf.dart';

import '../backend/backend_client.dart';
import '../backend/catalog_cache.dart';
import '../backend/token_resolver.dart';
import '../errors.dart';
import '../http_utils.dart';
import '../mappers.dart';

/// Cola de moderación: `/images/reports` -> `/api/reports`.
/// El backend decide quién puede verla (moderador/admin) y responde 403 si no.
class ReportsRoutes {
  ReportsRoutes({
    required this.backend,
    required this.catalogo,
    required this.tokens,
  });

  final BackendClient backend;
  final CatalogCache catalogo;
  final TokenResolver tokens;

  static const _porPagina = 50;
  static const _maxPaginas = 10;

  /// `GET /images/reports?estado=abierto|revisado|descartado`
  Future<Response> listar(Request request) async {
    final token = tokens.requerir(request);
    final estado = request.url.queryParameters['estado']?.trim() ?? '';

    String? status;
    if (estado.isNotEmpty) {
      status = statusDesdeEstadoApp(estado);
      if (status == null) {
        throw BffError(
          400,
          'validacion',
          'Estado no válido. Usa abierto, revisado o descartado.',
        );
      }
    }

    final reportes = <Map<String, dynamic>>[];
    for (var pagina = 1; pagina <= _maxPaginas; pagina++) {
      final respuesta = await backend.getJson(
        '/api/reports',
        consulta: {
          'page': '$pagina',
          'per_page': '$_porPagina',
          if (status != null) 'status': status,
        },
        token: token,
      );
      final cuerpo = comoMapa(respuesta);
      final lista = cuerpo['reports'];
      if (lista is List) {
        for (final r in lista.whereType<Map>()) {
          reportes.add(await _mapear(Map<String, dynamic>.from(r), token));
        }
      }
      final paginacion = cuerpo['pagination'];
      if (paginacion is! Map || paginacion['more?'] != true) break;
    }
    return jsonResponse(200, {'reportes': reportes});
  }

  /// `PUT /images/reports/{id}` con `{estado}`.
  ///
  /// `revisado` retira la foto (`/retire`); `descartado` la deja visible
  /// (`/approve`). El backend no permite reabrir un reporte.
  Future<Response> cambiarEstado(Request request, String id) async {
    final token = tokens.requerir(request);
    final cuerpo = await leerJsonObjeto(request);
    final estado = '${cuerpo['estado'] ?? ''}';

    final accion = switch (estado) {
      'revisado' => 'retire',
      'descartado' => 'approve',
      'abierto' => throw BffError(
          409,
          'no_soportado',
          'El backend no permite reabrir un reporte.',
        ),
      _ => throw BffError(
          400,
          'validacion',
          'Estado no válido. Usa «revisado» o «descartado».',
        ),
    };

    final respuesta = await backend.postJson(
      '/api/reports/${Uri.encodeComponent(id)}/$accion',
      <String, dynamic>{},
      token: token,
    );
    // La respuesta no trae la foto; la app vuelve a leer la lista entera
    // después de cambiar el estado, así que no hace falta pedirla aparte.
    return jsonResponse(200, reporteDesdeBackend(extraerMapa(respuesta, 'report')));
  }

  Future<Map<String, dynamic>> _mapear(
    Map<String, dynamic> reporte,
    String token,
  ) async {
    var categoria = '';
    final foto = reporte['sighting'];
    if (foto is Map && foto['bird_id'] is String) {
      try {
        categoria = await catalogo.claveDeAve(foto['bird_id'] as String, token);
      } on BackendException {
        categoria = '';
      }
    }
    return reporteDesdeBackend(reporte, categoria: categoria);
  }
}
