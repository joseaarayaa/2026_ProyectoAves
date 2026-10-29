import '../mappers.dart';
import 'backend_client.dart';

/// Caché en memoria de categorías y aves del backend.
///
/// La app habla de categorías por nombre (`rapaces`); el backend, por UUID, y
/// asocia la categoría al *ave*, no a la foto. Esta caché resuelve:
/// - nombre de categoría -> `category_id`
/// - categoría -> un ave "genérica" para colgarle los avistamientos nuevos
/// - `bird_id` -> clave de categoría (para pintar reportes)
class CatalogCache {
  CatalogCache(
    this._backend, {
    Map<String, String> alias = const {},
    this.vigencia = const Duration(minutes: 10),
    DateTime Function()? ahora,
  })  : _ahora = ahora ?? DateTime.now,
        _alias = {
          for (final e in alias.entries) normalizar(e.key): normalizar(e.value),
        };

  final BackendClient _backend;
  final Duration vigencia;
  final DateTime Function() _ahora;

  /// clave de la app -> nombre normalizado de la categoría en el backend.
  final Map<String, String> _alias;

  DateTime? _cargadoEn;
  Future<void>? _enCurso;

  Map<String, String> _categoriaIdPorNombre = {};
  Map<String, String> _nombrePorCategoriaId = {};
  Map<String, String> _categoriaIdDeAve = {};
  Map<String, String> _primerAvePorCategoria = {};

  bool get _vigente =>
      _cargadoEn != null && _ahora().difference(_cargadoEn!) < vigencia;

  void invalidar() => _cargadoEn = null;

  Future<void> _asegurar(String token) {
    if (_vigente) return Future.value();
    return _enCurso ??= _recargar(token).whenComplete(() => _enCurso = null);
  }

  Future<void> _recargar(String token) async {
    final categorias = await _backend.getJson('/api/categories', token: token);
    final aves = await _backend.getJson('/api/birds', token: token);

    final idPorNombre = <String, String>{};
    final nombrePorId = <String, String>{};
    for (final c in _lista(categorias, 'categories')) {
      final id = c['id'];
      final nombre = c['name'];
      if (id is String && nombre != null) {
        final clave = normalizar('$nombre');
        idPorNombre[clave] = id;
        nombrePorId[id] = clave;
      }
    }

    final listaAves = _lista(aves, 'birds')
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    final categoriaDeAve = <String, String>{};
    final primerAve = <String, String>{};
    for (final a in listaAves) {
      final id = a['id'];
      final categoriaId = a['category_id'];
      if (id is String && categoriaId is String) {
        categoriaDeAve[id] = categoriaId;
        primerAve.putIfAbsent(categoriaId, () => id);
      }
    }

    _categoriaIdPorNombre = idPorNombre;
    _nombrePorCategoriaId = nombrePorId;
    _categoriaIdDeAve = categoriaDeAve;
    _primerAvePorCategoria = primerAve;
    _cargadoEn = _ahora();
  }

  /// `category_id` de una clave de la app (`rapaces`), o `null` si el backend
  /// no tiene esa categoría ni un alias que apunte a una existente.
  Future<String?> categoriaId(String clave, String token) async {
    await _asegurar(token);
    final nombre = _alias[clave] ?? clave;
    return _categoriaIdPorNombre[nombre];
  }

  /// Un ave de esa categoría para asociar los avistamientos nuevos, o `null`
  /// si la categoría no tiene aves.
  Future<String?> aveGenerica(String categoriaId, String token) async {
    await _asegurar(token);
    return _primerAvePorCategoria[categoriaId];
  }

  /// Clave de categoría (la de la app, si hay alias) de un ave; `''` si no se
  /// conoce.
  Future<String> claveDeAve(String aveId, String token) async {
    await _asegurar(token);
    final categoriaId = _categoriaIdDeAve[aveId];
    final nombre = categoriaId == null ? null : _nombrePorCategoriaId[categoriaId];
    if (nombre == null) return '';
    for (final e in _alias.entries) {
      if (e.value == nombre) return e.key;
    }
    return nombre;
  }

  List<Map<String, dynamic>> _lista(Object? cuerpo, String clave) {
    if (cuerpo is Map && cuerpo[clave] is List) {
      return (cuerpo[clave] as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }
}
