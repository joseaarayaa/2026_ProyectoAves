import 'package:shelf/shelf.dart';

import '../backend/backend_client.dart';
import '../backend/token_resolver.dart';
import '../http_utils.dart';
import '../mappers.dart';

/// Autenticación: casi passthrough al backend. Solo adapta lo que la app lee
/// distinto de lo que manda Phoenix.
class AuthRoutes {
  AuthRoutes({required this.backend, required this.tokens});

  final BackendClient backend;
  final TokenResolver tokens;

  /// `POST /api/user/signin`
  Future<Response> registrar(Request request) async {
    final cuerpo = await leerJsonObjeto(request);
    // El contrato escribe `confirm_pasword` (errata); el backend espera
    // `confirm_password`. Se aceptan las dos.
    final errata = cuerpo.remove('confirm_pasword');
    if (errata != null && !cuerpo.containsKey('confirm_password')) {
      cuerpo['confirm_password'] = errata;
    }
    final respuesta = await backend.postJson('/api/user/signin', cuerpo);
    return jsonResponse(201, sesionApp(comoMapa(respuesta)));
  }

  /// `POST /api/user/login`
  Future<Response> iniciarSesion(Request request) async {
    final cuerpo = await leerJsonObjeto(request);
    final respuesta = await backend.postJson('/api/user/login', cuerpo);
    return jsonResponse(200, sesionApp(comoMapa(respuesta)));
  }

  /// `GET /api/user/me`
  Future<Response> yo(Request request) async {
    final token = tokens.requerir(request);
    final respuesta = await backend.getJson('/api/user/me', token: token);
    final usuario = extraerMapa(respuesta, 'user');
    return jsonResponse(200, {'user': usuarioApp(usuario)});
  }

  /// `DELETE /api/user/logout`
  Future<Response> cerrarSesion(Request request) async {
    final token = bearer(request);
    if (token != null) {
      await backend.delete('/api/user/logout', token: token);
    }
    return Response(204);
  }
}
