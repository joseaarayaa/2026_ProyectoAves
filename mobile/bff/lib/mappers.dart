/// Traducciones puras entre el contrato de la app (español) y el backend
/// (inglés). No hacen red, así que se prueban sin levantar nada.

/// Categorías generales que maneja la app (ver `categoriaGeneralAves`).
const categoriasApp = {'terrestres', 'acuaticas', 'rapaces', 'marinas', 'otras'};

/// Motivos permitidos por el contrato (`MotivoReporte`).
const motivosValidos = {
  'no_es_ave',
  'contenido_ofensivo',
  'imagen_enganosa',
  'derechos_autor',
  'otro',
};

/// Minúsculas y sin tildes: «Acuáticas» -> `acuaticas`.
String normalizar(String texto) {
  const origen = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const destino = 'aaaaaeeeeiiiiooooouuuun';
  final salida = StringBuffer();
  for (final rune in texto.trim().toLowerCase().runes) {
    final caracter = String.fromCharCode(rune);
    final indice = origen.indexOf(caracter);
    salida.write(indice >= 0 ? destino[indice] : caracter);
  }
  return salida.toString();
}

// ---------------------------------------------------------------- reportes

/// El backend guarda un único texto libre (`reason`); el contrato separa
/// `motivo` y `detalle`. Se codifica como `motivo` o `motivo: detalle`.
String razonDesdeMotivo(String motivo, String? detalle) {
  final texto = detalle?.trim() ?? '';
  return texto.isEmpty ? motivo : '$motivo: $texto';
}

/// Operación inversa de [razonDesdeMotivo]. Si el texto no empieza por un
/// motivo conocido (reporte creado fuera del BFF) se devuelve como `otro`.
({String motivo, String detalle}) motivoDesdeRazon(String? razon) {
  final texto = razon?.trim() ?? '';
  for (final motivo in motivosValidos) {
    if (texto == motivo) return (motivo: motivo, detalle: '');
    if (texto.startsWith('$motivo: ')) {
      return (motivo: motivo, detalle: texto.substring(motivo.length + 2));
    }
  }
  return (motivo: 'otro', detalle: texto);
}

/// Estado del backend -> estado que usa la pantalla de moderación.
///
/// - `pendiente` -> `abierto`
/// - `retirado`  -> `revisado`   (el reporte procedió: la foto se oculta)
/// - `aprobado`  -> `descartado` (el reporte no procedió: la foto se queda)
const _estadoAppPorStatus = {
  'pendiente': 'abierto',
  'retirado': 'revisado',
  'aprobado': 'descartado',
};

String estadoApp(String? status) => _estadoAppPorStatus[status] ?? 'abierto';

/// Estado de la app -> `status` del backend, o `null` si no existe.
String? statusDesdeEstadoApp(String estado) {
  for (final entrada in _estadoAppPorStatus.entries) {
    if (entrada.value == estado) return entrada.key;
  }
  return null;
}

// ------------------------------------------------------------------- fotos

/// `Sighting` del backend -> `Imagen` del contrato.
///
/// `autor` solo se incluye si el backend manda `owner_nickname`: hoy manda
/// únicamente `owner_id`, un UUID interno que no se expone a la app.
Map<String, dynamic> fotoDesdeSighting(
  Map<String, dynamic> sighting, {
  String categoria = '',
}) {
  final autor = sighting['owner_nickname'];
  return {
    'id': '${sighting['id'] ?? ''}',
    'url': '${sighting['photo_url'] ?? ''}',
    if (categoria.isNotEmpty) 'categoria': categoria,
    if (autor is String && autor.isNotEmpty) 'autor': autor,
    if (sighting['place'] != null) 'lugar': sighting['place'],
    if (sighting['spotted_on'] != null && '${sighting['spotted_on']}'.isNotEmpty)
      'fecha': sighting['spotted_on'],
    if (sighting['comment'] != null) 'comentario': sighting['comment'],
    if (sighting['inserted_at'] != null) 'subida_en': sighting['inserted_at'],
  };
}

/// Total de páginas para el campo `paginado.total` del contrato.
int totalPaginas(int cantidad, int porPagina) =>
    porPagina <= 0 ? 0 : (cantidad + porPagina - 1) ~/ porPagina;

/// `Report` del backend -> `ReporteModeracion` que lee la app.
Map<String, dynamic> reporteDesdeBackend(
  Map<String, dynamic> reporte, {
  String categoria = '',
}) {
  final razon = motivoDesdeRazon(reporte['reason']?.toString());
  final sighting = reporte['sighting'];
  final reportero = reporte['reporter_nickname'];
  final foto = sighting is Map
      ? fotoDesdeSighting(
          Map<String, dynamic>.from(sighting),
          categoria: categoria,
        )
      : null;
  return {
    'id': '${reporte['id'] ?? ''}',
    'avistamiento_id': '${reporte['sighting_id'] ?? ''}',
    'motivo': razon.motivo,
    'estado': estadoApp(reporte['status']?.toString()),
    'detalle': razon.detalle,
    if (reporte['inserted_at'] != null) 'creado_en': reporte['inserted_at'],
    if (reportero is String && reportero.isNotEmpty) 'reportado_por': reportero,
    if (foto != null) 'foto_url': foto['url'],
    if (foto != null) 'avistamiento': foto,
  };
}

// ----------------------------------------------------------------- usuario

/// La app lee `user.user` (string) y el backend manda `nickname`. Se agrega el
/// alias sin quitar nada de lo que ya viene.
Map<String, dynamic> usuarioApp(Map<String, dynamic> usuario) => {
      ...usuario,
      'user': usuario['nickname'] ?? usuario['email'] ?? '',
    };

/// Respuesta de login/registro del backend con el usuario ya adaptado.
Map<String, dynamic> sesionApp(Map<String, dynamic> sesion) {
  final usuario = sesion['user'];
  return {
    ...sesion,
    if (usuario is Map) 'user': usuarioApp(Map<String, dynamic>.from(usuario)),
  };
}
