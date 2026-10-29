# BFF de CORON: Bitácora de Aves

Backend for Frontend en **Dart + Shelf**. Se ubica entre la app Flutter
(`mobile/`) y el backend Phoenix/Ash (`backend/aves/`):

```
App Flutter ──(contrato birds_apis.yaml)──▶ BFF (este proyecto) ──(/api/...)──▶ Phoenix
```

La app ya habla el contrato de `birds_apis.yaml` (`/images`, `/images/reports`,
textos en español, páginas desde 0). El backend implementa otra API
(`/api/photos`, `/api/sightings`, `/api/reports`, campos en inglés, páginas
desde 1). El BFF traduce entre las dos, así que **no hay que tocar ni la app ni
el backend**.

## Ejecutar

```bash
cd bff
dart pub get
BACKEND_URL=http://localhost:4000 dart run bin/server.dart
```

Escucha en el puerto `8080` (el backend usa el `4000`). Para apuntar la app:

```bash
# Emulador Android
flutter run --dart-define=BFF_ACTIVO=true --dart-define=BFF_URL=http://10.0.2.2:8080
```

Pruebas (usan un backend falso, no necesitan red ni Phoenix):

```bash
dart test
```

Docker:

```bash
docker build -t aves-bff .
docker run -p 8080:8080 -e BACKEND_URL=http://host.docker.internal:4000 aves-bff
```

## Variables de entorno

Ver `.env.example`. Ninguna clave va en el código.

| Variable | Por defecto | Para qué |
|---|---|---|
| `BACKEND_URL` | `http://localhost:4000` | URL del backend Phoenix |
| `PORT` | `8080` | Puerto del BFF |
| `SERVICE_EMAIL` / `SERVICE_PASSWORD` | vacío | Cuenta sin privilegios para el feed público |
| `CATEGORY_ALIASES` | vacío | `terrestres=Aves,otras=Aves`: categoría de la app → nombre en el backend |
| `MAX_UPLOAD_BYTES` | `5242880` | Tamaño máximo de foto (el backend también limita a 5 MB) |
| `BACKEND_TIMEOUT_SECONDS` | `15` | Espera máxima al backend |

## Rutas

| La app llama | El BFF llama al backend | Qué traduce |
|---|---|---|
| `POST /api/user/signin` | `POST /api/user/signin` | `confirm_pasword` → `confirm_password`; agrega `user.user` |
| `POST /api/user/login` | `POST /api/user/login` | agrega `user.user` (el nickname) |
| `GET /api/user/me` | `GET /api/user/me` | agrega `user.user` |
| `DELETE /api/user/logout` | `DELETE /api/user/logout` | passthrough |
| `GET /images?categoria&pagina&por_pagina` | `GET /api/photos?category_id&page&per_page` | nombre → UUID, página 0→1, `{urls, paginado}` |
| `POST /images` (multipart) | `POST /api/sightings` (multipart) | `file`→`photo`, `lugar`→`place`, `fecha`→`spotted_on`, `comentario`→`comment`, categoría → `bird_id` |
| `PUT /images?id=` | `POST /api/reports` | `motivo`+`detalle` → `reason`, `id` → `sighting_id` |
| `GET /images/reports?estado` | `GET /api/reports?status` | estados y estructura del reporte |
| `PUT /images/reports/{id}` | `POST /api/reports/:id/retire` o `/approve` | `estado` → acción |

Las rutas de usuario también responden sin el prefijo `/api` (`/user/login`),
como las declara el contrato. `GET /` y `GET /health` sirven de chequeo de vida.

Los errores salen siempre como `{"error": "codigo", "message": "texto"}`, el
formato que ya lee `ApiClient` en la app.

## Decisiones de diseño y límites conocidos

1. **Categoría de la foto.** La app clasifica por categoría general; el backend
   asocia la categoría al *ave*. Al subir una foto el BFF busca la categoría por
   nombre y usa **la primera ave de esa categoría** (orden alfabético) como
   `bird_id`. Si la app manda un campo `bird_id`, se respeta. Si la categoría no
   existe o no tiene aves, el avistamiento se guarda sin ave y **no aparecerá al
   filtrar el feed por categoría**.
2. **Nombres de categoría.** La app usa `terrestres, acuaticas, rapaces,
   marinas, otras`. Si en la base solo hay, por ejemplo, «Aves» y «Rapaces»,
   usa `CATEGORY_ALIASES` o crea las categorías faltantes en el backend. Una
   categoría de la app sin equivalente devuelve el feed **vacío** (no un error).
   Una categoría que la app no conoce devuelve 404.
3. **Autor de las fotos.** El backend solo manda `owner_id` (un UUID interno,
   que el BFF no expone). `autor` se omite hasta que el backend agregue
   `owner_nickname` a la serialización de avistamientos; en cuanto lo haga, el
   BFF lo reenvía sin cambios.
4. **Feed público.** El contrato dice que `GET /images` no requiere sesión, pero
   `/api/photos` sí. Con `SERVICE_EMAIL`/`SERVICE_PASSWORD` el BFF inicia sesión
   por su cuenta; sin ellos, el feed exige que el usuario esté logueado. Con
   sesión, el backend excluye las fotos del propio usuario.
5. **Estados de reporte.** El backend usa `pendiente / aprobado / retirado` y la
   app `abierto / revisado / descartado`. Se mapean por efecto:
   `retirado` (la foto se oculta) → `revisado`; `aprobado` (la foto se queda,
   el reporte no procedió) → `descartado`. Si tu criterio es el inverso, se
   cambia en un solo lugar: `_estadoAppPorStatus` en `lib/mappers.dart`
   (y el `switch` de `lib/routes/reports_routes.dart`).
6. **Reabrir un reporte** (`estado: abierto`) responde 409: el backend no lo
   permite.
7. **Motivo y detalle del reporte.** El backend guarda un solo texto (`reason`).
   Se codifica como `motivo` o `motivo: detalle` y se separa al leerlo.
8. **Lugar y fecha.** El backend los exige y la app los marca como opcionales.
   Si faltan, se usa «Sin especificar» y la fecha de hoy (UTC).
9. **URLs de las fotos.** El backend arma `photo_url` con su `PUBLIC_BASE_URL`.
   En desarrollo debe ser una dirección que el emulador alcance
   (`http://10.0.2.2:4000`, no `localhost`), o las imágenes no cargarán en la app.
10. **Moderación.** La app muestra la pantalla de reportes solo al rol `admin`
    (`Usuario.esAdmin`); el backend también permite al `moderador`.

## Estructura

```
bin/server.dart             arranque (puerto, logging, cierre limpio)
lib/app.dart                arma el router y las dependencias
lib/config.dart             variables de entorno
lib/mappers.dart            traducciones puras app <-> backend
lib/middleware.dart         errores a JSON {error, message}
lib/multipart.dart          lectura de la subida de fotos
lib/backend/                cliente HTTP, caché de catálogo, cuenta de servicio
lib/routes/                 auth, images, reports
test/                       pruebas con backend falso
```

## Estado de las pruebas

El código se escribió sin acceso a un SDK de Dart, así que **no se ejecutó**:
corre `dart pub get && dart analyze && dart test` antes de usarlo y corrige lo
que salga.
