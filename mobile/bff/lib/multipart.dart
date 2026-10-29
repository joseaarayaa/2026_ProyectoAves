import 'dart:convert';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';

import 'errors.dart';

class ArchivoSubido {
  ArchivoSubido({
    required this.bytes,
    required this.nombre,
    required this.contentType,
  });

  final Uint8List bytes;
  final String nombre;
  final String contentType;
}

class SubidaMultipart {
  SubidaMultipart({required this.campos, this.archivo});

  final Map<String, String> campos;
  final ArchivoSubido? archivo;
}

/// Lee un `multipart/form-data` entero en memoria. El campo de archivo se
/// llama `file` en el contrato de la app.
///
/// Corta con 413 si el cuerpo supera [maxBytes] (más un margen para los campos
/// de texto), sin llegar a leer el resto.
Future<SubidaMultipart> leerMultipart(
  Request request, {
  required int maxBytes,
}) async {
  final cabecera = request.headers['content-type'];
  if (cabecera == null) {
    throw BffError(400, 'validacion', 'Se esperaba multipart/form-data.');
  }

  final MediaType tipo;
  try {
    tipo = MediaType.parse(cabecera);
  } on FormatException {
    throw BffError(400, 'validacion', 'Content-Type no válido.');
  }
  final limite = tipo.parameters['boundary'];
  if (tipo.mimeType != 'multipart/form-data' || limite == null) {
    throw BffError(400, 'validacion', 'Se esperaba multipart/form-data.');
  }

  final campos = <String, String>{};
  ArchivoSubido? archivo;
  var total = 0;
  final tope = maxBytes + 64 * 1024;

  try {
    final partes = MimeMultipartTransformer(limite).bind(request.read());
    await for (final parte in partes) {
      final disposicion = parte.headers['content-disposition'] ?? '';
      final nombre =
          RegExp(r'(?:^|[;\s])name="([^"]*)"').firstMatch(disposicion)?.group(1);
      final nombreArchivo =
          RegExp(r'filename="([^"]*)"').firstMatch(disposicion)?.group(1);

      final acumulado = BytesBuilder(copy: false);
      await for (final trozo in parte) {
        total += trozo.length;
        if (total > tope) {
          throw BffError(
            413,
            'archivo_muy_grande',
            'La foto supera el tamaño máximo permitido.',
          );
        }
        acumulado.add(trozo);
      }
      if (nombre == null) continue;
      final bytes = acumulado.takeBytes();

      if (nombreArchivo != null && nombre == 'file') {
        archivo = ArchivoSubido(
          bytes: bytes,
          nombre: nombreArchivo.isEmpty ? 'foto' : nombreArchivo,
          contentType: parte.headers['content-type'] ??
              lookupMimeType(nombreArchivo, headerBytes: bytes) ??
              'application/octet-stream',
        );
      } else if (nombreArchivo == null) {
        campos[nombre] = utf8.decode(bytes, allowMalformed: true);
      }
    }
  } on MimeMultipartException {
    throw BffError(400, 'validacion', 'El multipart está mal formado.');
  }

  if (archivo != null) {
    if (archivo.bytes.length > maxBytes) {
      throw BffError(
        413,
        'archivo_muy_grande',
        'La foto supera el tamaño máximo permitido.',
      );
    }
    if (!archivo.contentType.toLowerCase().startsWith('image/')) {
      throw BffError(400, 'validacion', 'El archivo debe ser una imagen.');
    }
  }
  return SubidaMultipart(campos: campos, archivo: archivo);
}
