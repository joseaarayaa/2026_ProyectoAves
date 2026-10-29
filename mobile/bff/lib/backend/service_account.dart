import 'backend_client.dart';

/// Sesión del BFF con una cuenta sin privilegios.
///
/// El contrato declara `GET /images` como público, pero `/api/photos` del
/// backend exige un usuario autenticado. Con esta cuenta el feed funciona
/// aunque la app todavía no tenga sesión.
class ServiceAccount {
  ServiceAccount(
    this._backend, {
    this.email,
    this.password,
    DateTime Function()? ahora,
    this.vigencia = const Duration(minutes: 20),
  }) : _ahora = ahora ?? DateTime.now;

  final BackendClient _backend;
  final String? email;
  final String? password;
  final Duration vigencia;
  final DateTime Function() _ahora;

  String? _token;
  DateTime? _vence;

  bool get configurada => email != null && password != null;

  Future<String> token() async {
    final vence = _vence;
    if (_token != null && vence != null && _ahora().isBefore(vence)) {
      return _token!;
    }
    final cuerpo = await _backend.postJson('/api/user/login', {
      'email': email,
      'password': password,
    });
    final token = cuerpo is Map ? cuerpo['token'] : null;
    if (token is! String || token.isEmpty) {
      throw BackendException(502, {
        'error': 'El backend no devolvió token para la cuenta de servicio.',
      });
    }
    _token = token;
    _vence = _ahora().add(vigencia);
    return token;
  }

  void invalidar() {
    _token = null;
    _vence = null;
  }
}
