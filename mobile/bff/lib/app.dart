import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'backend/backend_client.dart';
import 'backend/catalog_cache.dart';
import 'backend/service_account.dart';
import 'backend/token_resolver.dart';
import 'config.dart';
import 'http_utils.dart';
import 'middleware.dart';
import 'routes/auth_routes.dart';
import 'routes/images_routes.dart';
import 'routes/reports_routes.dart';

/// Arma el BFF completo. [clienteHttp] permite inyectar un `MockClient` en las
/// pruebas para no depender de un backend real.
Handler construirManejador(BffConfig config, {http.Client? clienteHttp}) {
  final backend = BackendClient(
    baseUrl: config.backendUrl,
    cliente: clienteHttp,
    tiempoLimite: config.tiempoLimite,
  );
  final servicio = ServiceAccount(
    backend,
    email: config.servicioEmail,
    password: config.servicioPassword,
  );
  final tokens = TokenResolver(servicio);
  final catalogo = CatalogCache(backend, alias: config.aliasCategorias);

  final auth = AuthRoutes(backend: backend, tokens: tokens);
  final imagenes = ImagesRoutes(
    backend: backend,
    catalogo: catalogo,
    tokens: tokens,
    maxSubidaBytes: config.maxSubidaBytes,
  );
  final reportes = ReportsRoutes(
    backend: backend,
    catalogo: catalogo,
    tokens: tokens,
  );

  Response estado(Request _) => jsonResponse(200, {'status': 'ok'});

  final router = Router(
    notFoundHandler: (Request _) => jsonResponse(404, {
      'error': 'no_encontrado',
      'message': 'Ruta no encontrada.',
    }),
  )
    ..get('/', estado)
    ..get('/health', estado);

  // La app llama `/api/user/...`; el contrato (birds_apis.yaml) declara
  // `/user/...`. Se sirven las dos para no depender de cuál se corrija.
  for (final prefijo in ['/api', '']) {
    router
      ..post('$prefijo/user/signin', auth.registrar)
      ..post('$prefijo/user/login', auth.iniciarSesion)
      ..get('$prefijo/user/me', auth.yo)
      ..delete('$prefijo/user/logout', auth.cerrarSesion);
  }

  router
    ..get('/images', imagenes.listar)
    ..post('/images', imagenes.subir)
    ..put('/images', imagenes.reportar)
    ..get('/images/reports', reportes.listar)
    ..put('/images/reports/<id>', reportes.cambiarEstado);

  return const Pipeline().addMiddleware(manejarErrores()).addHandler(router.call);
}
