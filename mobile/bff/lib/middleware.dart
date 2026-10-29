import 'dart:io';

import 'package:shelf/shelf.dart';

import 'backend/backend_client.dart';
import 'errors.dart';
import 'http_utils.dart';

/// Convierte cualquier fallo en el JSON `{"error", "message"}` que espera la
/// app, sin filtrar trazas ni detalles internos.
Middleware manejarErrores() {
  return (Handler interno) {
    return (Request request) async {
      try {
        return await interno(request);
      } on BffError catch (e) {
        return jsonResponse(e.status, {'error': e.codigo, 'message': e.mensaje});
      } on BackendException catch (e) {
        final status =
            e.statusCode >= 500 && e.statusCode != 504 ? 502 : e.statusCode;
        return jsonResponse(status, {
          'error': _codigo(status),
          'message': e.mensaje,
        });
      } on FormatException catch (e) {
        return jsonResponse(400, {'error': 'validacion', 'message': e.message});
      } catch (e, pila) {
        stderr.writeln('Error no controlado en ${request.method} '
            '${request.requestedUri.path}: $e\n$pila');
        return jsonResponse(500, {
          'error': 'error_interno',
          'message': 'Error interno del BFF.',
        });
      }
    };
  };
}

String _codigo(int status) => switch (status) {
      400 || 422 => 'validacion',
      401 => 'no_autenticado',
      403 => 'prohibido',
      404 => 'no_encontrado',
      409 => 'conflicto',
      413 => 'archivo_muy_grande',
      502 => 'backend_no_disponible',
      504 => 'tiempo_excedido',
      _ => 'error',
    };
