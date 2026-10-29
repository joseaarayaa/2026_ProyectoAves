/// Error propio del BFF con el status y el código que verá la app.
///
/// El middleware lo convierte en `{"error": codigo, "message": mensaje}`, que
/// es el formato que `ApiClient` de la app ya sabe leer.
class BffError implements Exception {
  BffError(this.status, this.codigo, this.mensaje);

  final int status;
  final String codigo;
  final String mensaje;

  @override
  String toString() => 'BffError($status, $codigo): $mensaje';
}
