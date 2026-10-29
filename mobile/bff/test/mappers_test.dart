import 'package:aves_bff/mappers.dart';
import 'package:test/test.dart';

void main() {
  group('normalizar', () {
    test('quita tildes y pasa a minúsculas', () {
      expect(normalizar('Acuáticas'), 'acuaticas');
      expect(normalizar('  RAPACES '), 'rapaces');
      expect(normalizar('Cóndor Andino'), 'condor andino');
    });
  });

  group('motivo y detalle', () {
    test('ida y vuelta con detalle', () {
      final razon = razonDesdeMotivo('no_es_ave', 'parece un perro');
      expect(razon, 'no_es_ave: parece un perro');
      final partes = motivoDesdeRazon(razon);
      expect(partes.motivo, 'no_es_ave');
      expect(partes.detalle, 'parece un perro');
    });

    test('sin detalle', () {
      expect(razonDesdeMotivo('otro', null), 'otro');
      expect(razonDesdeMotivo('otro', '  '), 'otro');
      expect(motivoDesdeRazon('otro').motivo, 'otro');
    });

    test('texto libre ajeno al BFF se trata como «otro»', () {
      final partes = motivoDesdeRazon('No es un ave, es un dron');
      expect(partes.motivo, 'otro');
      expect(partes.detalle, 'No es un ave, es un dron');
    });
  });

  group('estados', () {
    test('backend -> app', () {
      expect(estadoApp('pendiente'), 'abierto');
      expect(estadoApp('retirado'), 'revisado');
      expect(estadoApp('aprobado'), 'descartado');
      expect(estadoApp(null), 'abierto');
    });

    test('app -> backend', () {
      expect(statusDesdeEstadoApp('abierto'), 'pendiente');
      expect(statusDesdeEstadoApp('revisado'), 'retirado');
      expect(statusDesdeEstadoApp('descartado'), 'aprobado');
      expect(statusDesdeEstadoApp('inventado'), isNull);
    });
  });

  group('fotoDesdeSighting', () {
    test('traduce campos y no expone owner_id', () {
      final foto = fotoDesdeSighting({
        'id': 's1',
        'photo_url': 'https://x/y.jpg',
        'place': 'Cajón del Maipo',
        'spotted_on': '2026-10-01',
        'comment': 'Volaba alto',
        'owner_id': 'uuid-interno',
        'inserted_at': '2026-10-01T10:00:00Z',
      }, categoria: 'rapaces');

      expect(foto['id'], 's1');
      expect(foto['url'], 'https://x/y.jpg');
      expect(foto['categoria'], 'rapaces');
      expect(foto['lugar'], 'Cajón del Maipo');
      expect(foto['fecha'], '2026-10-01');
      expect(foto['comentario'], 'Volaba alto');
      expect(foto['subida_en'], '2026-10-01T10:00:00Z');
      expect(foto.containsKey('autor'), isFalse);
      expect(foto.values, isNot(contains('uuid-interno')));
    });

    test('usa owner_nickname como autor cuando el backend lo manda', () {
      final foto = fotoDesdeSighting({
        'id': 's1',
        'photo_url': 'u',
        'owner_nickname': 'ana',
      });
      expect(foto['autor'], 'ana');
    });
  });

  test('totalPaginas redondea hacia arriba', () {
    expect(totalPaginas(0, 20), 0);
    expect(totalPaginas(20, 20), 1);
    expect(totalPaginas(41, 20), 3);
  });

  test('usuarioApp agrega el alias `user` con el nickname', () {
    final usuario = usuarioApp({
      'id': '1',
      'email': 'a@b.cl',
      'nickname': 'ana',
      'rol': 'admin',
    });
    expect(usuario['user'], 'ana');
    expect(usuario['rol'], 'admin');
    expect(usuario['email'], 'a@b.cl');
  });
}
