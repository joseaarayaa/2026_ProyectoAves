import 'dart:convert';

import 'package:aves_bff/app.dart';
import 'package:aves_bff/config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

http.Response _json(int status, Object cuerpo) => http.Response(
      jsonEncode(cuerpo),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Backend Phoenix de mentira: responde según "METODO /ruta" y recuerda las
/// llamadas que recibió.
class BackendFalso {
  final llamadas = <http.Request>[];
  final rutas = <String, http.Response Function(http.Request)>{};

  late final MockClient cliente = MockClient((peticion) async {
    llamadas.add(peticion);
    final manejador = rutas['${peticion.method} ${peticion.url.path}'];
    if (manejador == null) {
      return _json(404, {'error': 'sin ruta ${peticion.url.path}'});
    }
    return manejador(peticion);
  });

  http.Request ultima(String metodo, String ruta) =>
      llamadas.lastWhere((l) => l.method == metodo && l.url.path == ruta);
}

BackendFalso _backendConCatalogo() {
  final b = BackendFalso();
  b.rutas['GET /api/categories'] = (_) => _json(200, {
        'categories': [
          {'id': 'c1', 'name': 'Rapaces'},
          {'id': 'c2', 'name': 'Aves'},
        ],
      });
  b.rutas['GET /api/birds'] = (_) => _json(200, {
        'birds': [
          {'id': 'b1', 'name': 'Cóndor andino', 'category_id': 'c1'},
          {'id': 'b2', 'name': 'Picaflor', 'category_id': 'c2'},
        ],
      });
  return b;
}

Handler _crear(BackendFalso b, {BffConfig? config}) => construirManejador(
      config ?? const BffConfig(backendUrl: 'http://backend'),
      clienteHttp: b.cliente,
    );

Request _pedir(
  String metodo,
  String ruta, {
  String? token,
  Object? json,
  String? cuerpo,
  Map<String, String>? cabeceras,
}) =>
    Request(
      metodo,
      Uri.parse('http://bff$ruta'),
      headers: {
        if (token != null) 'authorization': 'Bearer $token',
        if (json != null) 'content-type': 'application/json',
        ...?cabeceras,
      },
      body: json != null ? jsonEncode(json) : cuerpo,
    );

Future<Map<String, dynamic>> _leer(Response r) async =>
    jsonDecode(await r.readAsString()) as Map<String, dynamic>;

void main() {
  group('GET /images', () {
    test('traduce categoría, página y respuesta', () async {
      final b = _backendConCatalogo();
      b.rutas['GET /api/photos'] = (_) => _json(200, {
            'photos': [
              {
                'id': 's1',
                'photo_url': 'https://x/y.jpg',
                'place': 'Cajón del Maipo',
                'spotted_on': '2026-10-01',
                'comment': 'Volaba alto',
                'owner_id': 'u1',
                'inserted_at': '2026-10-01T10:00:00Z',
              },
            ],
            'pagination': {'page': 1, 'per_page': 20, 'count': 41, 'more?': true},
          });

      final r = await _crear(b)(
        _pedir('GET', '/images?categoria=Rapaces&pagina=0&por_pagina=20',
            token: 'tok'),
      );
      expect(r.statusCode, 200);

      final cuerpo = await _leer(r);
      final fotos = cuerpo['urls'] as List;
      expect(fotos, hasLength(1));
      expect((fotos.first as Map)['categoria'], 'rapaces');
      expect((fotos.first as Map)['url'], 'https://x/y.jpg');
      expect(cuerpo['paginado'], {'pagina': 0, 'total': 3});

      final llamada = b.ultima('GET', '/api/photos');
      expect(llamada.url.queryParameters['category_id'], 'c1');
      expect(llamada.url.queryParameters['page'], '1');
      expect(llamada.headers['Authorization'], 'Bearer tok');
    });

    test('categoría de la app sin equivalente en el backend: feed vacío',
        () async {
      final b = _backendConCatalogo();
      final r = await _crear(b)(_pedir('GET', '/images?categoria=marinas', token: 't'));
      expect(r.statusCode, 200);
      final cuerpo = await _leer(r);
      expect(cuerpo['urls'], isEmpty);
      expect((cuerpo['paginado'] as Map)['total'], 0);
    });

    test('alias de categoría apunta a una existente', () async {
      final b = _backendConCatalogo();
      b.rutas['GET /api/photos'] = (_) => _json(200, {
            'photos': <Object>[],
            'pagination': {'page': 1, 'per_page': 20, 'count': 0, 'more?': false},
          });
      final handler = _crear(
        b,
        config: const BffConfig(
          backendUrl: 'http://backend',
          aliasCategorias: {'terrestres': 'Aves'},
        ),
      );
      final r = await handler(_pedir('GET', '/images?categoria=terrestres', token: 't'));
      expect(r.statusCode, 200);
      expect(b.ultima('GET', '/api/photos').url.queryParameters['category_id'], 'c2');
    });

    test('categoría desconocida: 404', () async {
      final r = await _crear(_backendConCatalogo())(
        _pedir('GET', '/images?categoria=dinosaurios', token: 't'),
      );
      expect(r.statusCode, 404);
      expect((await _leer(r))['error'], 'categoria_no_encontrada');
    });

    test('sin categoría: 400', () async {
      final r = await _crear(_backendConCatalogo())(_pedir('GET', '/images', token: 't'));
      expect(r.statusCode, 400);
    });

    test('sin sesión y sin cuenta de servicio: 401', () async {
      final r = await _crear(_backendConCatalogo())(
        _pedir('GET', '/images?categoria=rapaces'),
      );
      expect(r.statusCode, 401);
      expect((await _leer(r))['error'], 'no_autenticado');
    });

    test('sin sesión usa la cuenta de servicio', () async {
      final b = _backendConCatalogo();
      b.rutas['POST /api/user/login'] = (_) => _json(200, {'token': 'svc'});
      b.rutas['GET /api/photos'] = (_) => _json(200, {
            'photos': <Object>[],
            'pagination': {'page': 1, 'per_page': 20, 'count': 0, 'more?': false},
          });
      final handler = _crear(
        b,
        config: const BffConfig(
          backendUrl: 'http://backend',
          servicioEmail: 'svc@aves.test',
          servicioPassword: 'secreto',
        ),
      );
      final r = await handler(_pedir('GET', '/images?categoria=rapaces'));
      expect(r.statusCode, 200);
      expect(b.ultima('GET', '/api/photos').headers['Authorization'], 'Bearer svc');
    });
  });

  group('POST /images', () {
    const limite = 'xxLIMITExx';
    final cuerpoMultipart = [
      '--$limite\r\n',
      'Content-Disposition: form-data; name="categoria"\r\n\r\nrapaces\r\n',
      '--$limite\r\n',
      'Content-Disposition: form-data; name="lugar"\r\n\r\nCajon del Maipo\r\n',
      '--$limite\r\n',
      'Content-Disposition: form-data; name="fecha"\r\n\r\n2026-10-01\r\n',
      '--$limite\r\n',
      'Content-Disposition: form-data; name="file"; filename="a.jpg"\r\n',
      'Content-Type: image/jpeg\r\n\r\n',
      'FOTOFALSA',
      '\r\n--$limite--\r\n',
    ].join();

    test('crea el avistamiento con el ave genérica de la categoría', () async {
      final b = _backendConCatalogo();
      b.rutas['POST /api/sightings'] = (_) => _json(201, {
            'sighting': {
              'id': 's9',
              'photo_url': 'http://backend/uploads/a.jpg',
              'place': 'Cajon del Maipo',
              'spotted_on': '2026-10-01',
              'bird_id': 'b1',
            },
          });

      final r = await _crear(b)(_pedir(
        'POST',
        '/images',
        token: 'tok',
        cuerpo: cuerpoMultipart,
        cabeceras: {'content-type': 'multipart/form-data; boundary=$limite'},
      ));
      expect(r.statusCode, 201);
      final cuerpo = await _leer(r);
      expect(cuerpo['id'], 's9');
      expect(cuerpo['categoria'], 'rapaces');

      final enviado = b.ultima('POST', '/api/sightings');
      expect(enviado.headers['content-type'], startsWith('multipart/form-data'));
      expect(enviado.body, contains('name="photo"'));
      expect(enviado.body, contains('FOTOFALSA'));
      expect(enviado.body, contains('name="bird_id"'));
      expect(enviado.body, contains('b1'));
      expect(enviado.body, contains('name="place"'));
      expect(enviado.body, contains('name="spotted_on"'));
    });

    test('sin sesión: 401', () async {
      final r = await _crear(_backendConCatalogo())(_pedir(
        'POST',
        '/images',
        cuerpo: cuerpoMultipart,
        cabeceras: {'content-type': 'multipart/form-data; boundary=$limite'},
      ));
      expect(r.statusCode, 401);
    });

    test('sin archivo: 400', () async {
      final sinArchivo = '--$limite\r\n'
          'Content-Disposition: form-data; name="categoria"\r\n\r\nrapaces\r\n'
          '--$limite--\r\n';
      final r = await _crear(_backendConCatalogo())(_pedir(
        'POST',
        '/images',
        token: 't',
        cuerpo: sinArchivo,
        cabeceras: {'content-type': 'multipart/form-data; boundary=$limite'},
      ));
      expect(r.statusCode, 400);
    });
  });

  group('reportes', () {
    final reporteBackend = {
      'id': 'r1',
      'sighting_id': 's1',
      'reason': 'no_es_ave: es un perro',
      'status': 'pendiente',
      'inserted_at': '2026-10-29T00:00:00Z',
      'sighting': {
        'id': 's1',
        'photo_url': 'https://x/y.jpg',
        'place': 'Parque',
        'bird_id': 'b1',
      },
    };

    test('PUT /images?id= crea el reporte', () async {
      final b = _backendConCatalogo();
      b.rutas['POST /api/reports'] = (_) => _json(201, {'report': reporteBackend});

      final r = await _crear(b)(_pedir(
        'PUT',
        '/images?id=s1',
        token: 'tok',
        json: {'motivo': 'no_es_ave', 'detalle': 'es un perro'},
      ));
      expect(r.statusCode, 200);
      final cuerpo = await _leer(r);
      expect(cuerpo['motivo'], 'no_es_ave');
      expect(cuerpo['detalle'], 'es un perro');
      expect(cuerpo['estado'], 'abierto');

      final enviado = jsonDecode(b.ultima('POST', '/api/reports').body) as Map;
      expect(enviado['sighting_id'], 's1');
      expect(enviado['reason'], 'no_es_ave: es un perro');
    });

    test('motivo inválido: 400', () async {
      final r = await _crear(_backendConCatalogo())(
        _pedir('PUT', '/images?id=s1', token: 't', json: {'motivo': 'porque si'}),
      );
      expect(r.statusCode, 400);
    });

    test('GET /images/reports traduce estado y agrega la categoría', () async {
      final b = _backendConCatalogo();
      b.rutas['GET /api/reports'] = (_) => _json(200, {
            'reports': [reporteBackend],
            'pagination': {'page': 1, 'per_page': 50, 'count': 1, 'more?': false},
          });

      final r = await _crear(b)(
        _pedir('GET', '/images/reports?estado=abierto', token: 'adm'),
      );
      expect(r.statusCode, 200);
      final lista = (await _leer(r))['reportes'] as List;
      final reporte = lista.single as Map;
      expect(reporte['estado'], 'abierto');
      expect((reporte['avistamiento'] as Map)['url'], 'https://x/y.jpg');
      expect((reporte['avistamiento'] as Map)['categoria'], 'rapaces');
      expect(b.ultima('GET', '/api/reports').url.queryParameters['status'],
          'pendiente');
    });

    test('estado inválido en el filtro: 400', () async {
      final r = await _crear(_backendConCatalogo())(
        _pedir('GET', '/images/reports?estado=raro', token: 't'),
      );
      expect(r.statusCode, 400);
    });

    test('revisado -> retire, descartado -> approve', () async {
      final b = _backendConCatalogo();
      b.rutas['POST /api/reports/r1/retire'] =
          (_) => _json(200, {'report': {...reporteBackend, 'status': 'retirado'}});
      b.rutas['POST /api/reports/r1/approve'] =
          (_) => _json(200, {'report': {...reporteBackend, 'status': 'aprobado'}});
      final handler = _crear(b);

      final revisado = await handler(_pedir('PUT', '/images/reports/r1',
          token: 'adm', json: {'estado': 'revisado'}));
      expect(revisado.statusCode, 200);
      expect((await _leer(revisado))['estado'], 'revisado');

      final descartado = await handler(_pedir('PUT', '/images/reports/r1',
          token: 'adm', json: {'estado': 'descartado'}));
      expect((await _leer(descartado))['estado'], 'descartado');
    });

    test('reabrir un reporte no está soportado: 409', () async {
      final r = await _crear(_backendConCatalogo())(_pedir(
        'PUT',
        '/images/reports/r1',
        token: 'adm',
        json: {'estado': 'abierto'},
      ));
      expect(r.statusCode, 409);
    });

    test('un usuario sin permiso recibe el 403 del backend', () async {
      final b = _backendConCatalogo();
      b.rutas['GET /api/reports'] = (_) => _json(403, {'errors': ['No autorizado']});
      final r = await _crear(b)(_pedir('GET', '/images/reports', token: 'normal'));
      expect(r.statusCode, 403);
    });
  });

  group('autenticación', () {
    test('login agrega `user` con el nickname', () async {
      final b = BackendFalso();
      b.rutas['POST /api/user/login'] = (_) => _json(200, {
            'user': {'id': 'u', 'email': 'a@b.cl', 'nickname': 'ana', 'rol': 'admin'},
            'token': 'jwt',
          });
      final r = await _crear(b)(_pedir('POST', '/api/user/login',
          json: {'email': 'a@b.cl', 'password': 'x'}));
      expect(r.statusCode, 200);
      final cuerpo = await _leer(r);
      expect(cuerpo['token'], 'jwt');
      expect((cuerpo['user'] as Map)['user'], 'ana');
      expect((cuerpo['user'] as Map)['rol'], 'admin');
    });

    test('también responde bajo /user/login (sin /api)', () async {
      final b = BackendFalso();
      b.rutas['POST /api/user/login'] =
          (_) => _json(200, {'user': {'nickname': 'ana'}, 'token': 'jwt'});
      final r = await _crear(b)(_pedir('POST', '/user/login',
          json: {'email': 'a@b.cl', 'password': 'x'}));
      expect(r.statusCode, 200);
    });

    test('credenciales inválidas: 401 con el mensaje del backend', () async {
      final b = BackendFalso();
      b.rutas['POST /api/user/login'] =
          (_) => _json(401, {'error': 'Credenciales inválidas'});
      final r = await _crear(b)(_pedir('POST', '/api/user/login',
          json: {'email': 'a@b.cl', 'password': 'mala'}));
      expect(r.statusCode, 401);
      expect((await _leer(r))['message'], 'Credenciales inválidas');
    });

    test('registro corrige la errata confirm_pasword', () async {
      final b = BackendFalso();
      b.rutas['POST /api/user/signin'] = (_) => _json(201, {
            'user': {'nickname': 'ana'},
            'token': 'jwt',
          });
      final r = await _crear(b)(_pedir('POST', '/api/user/signin', json: {
        'user': 'ana',
        'email': 'a@b.cl',
        'password': '12345678',
        'confirm_pasword': '12345678',
      }));
      expect(r.statusCode, 201);
      final enviado = jsonDecode(b.ultima('POST', '/api/user/signin').body) as Map;
      expect(enviado['confirm_password'], '12345678');
      expect(enviado.containsKey('confirm_pasword'), isFalse);
    });

    test('/me exige token', () async {
      final r = await _crear(BackendFalso())(_pedir('GET', '/api/user/me'));
      expect(r.statusCode, 401);
    });

    test('logout responde 204', () async {
      final b = BackendFalso();
      b.rutas['DELETE /api/user/logout'] = (_) => http.Response('', 204);
      final r = await _crear(b)(_pedir('DELETE', '/api/user/logout', token: 't'));
      expect(r.statusCode, 204);
    });
  });

  group('robustez', () {
    test('backend caído: 502 con JSON', () async {
      final cliente = MockClient((_) async => throw http.ClientException('caído'));
      final handler = construirManejador(
        const BffConfig(backendUrl: 'http://backend'),
        clienteHttp: cliente,
      );
      final r = await handler(_pedir('POST', '/api/user/login',
          json: {'email': 'a@b.cl', 'password': 'x'}));
      expect(r.statusCode, 502);
      expect((await _leer(r))['error'], 'backend_no_disponible');
    });

    test('ruta inexistente: 404 JSON', () async {
      final r = await _crear(BackendFalso())(_pedir('GET', '/nada'));
      expect(r.statusCode, 404);
      expect((await _leer(r))['error'], 'no_encontrado');
    });

    test('GET / sirve de chequeo de vida', () async {
      final r = await _crear(BackendFalso())(_pedir('GET', '/'));
      expect(r.statusCode, 200);
    });
  });
}
