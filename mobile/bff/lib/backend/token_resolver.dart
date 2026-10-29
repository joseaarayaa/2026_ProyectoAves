import 'package:shelf/shelf.dart';

import '../errors.dart';
import '../http_utils.dart';
import 'backend_client.dart';
import 'service_account.dart';

/// Decide con qué token se llama al backend en cada petición.
class TokenResolver {
  TokenResolver(this._servicio);

  final ServiceAccount _servicio;

  /// Exige sesión del usuario: sin token responde 401.
  String requerir(Request request) {
    final token = bearer(request);
    if (token == null) {
      throw BffError(401, 'no_autenticado', 'Falta el token de sesión.');
    }
    return token;
  }

  /// Rutas públicas: usa el token del usuario si lo hay; si no, la cuenta de
  /// servicio. Si el token de servicio venció, se renueva y se reintenta una
  /// vez.
  Future<T> conTokenOServicio<T>(
    Request request,
    Future<T> Function(String token) accion,
  ) async {
    final propio = bearer(request);
    if (propio != null) return accion(propio);

    if (!_servicio.configurada) {
      throw BffError(
        401,
        'no_autenticado',
        'Inicia sesión para ver las fotos de la comunidad.',
      );
    }
    try {
      return await accion(await _servicio.token());
    } on BackendException catch (e) {
      if (e.statusCode != 401) rethrow;
      _servicio.invalidar();
      return accion(await _servicio.token());
    }
  }
}
