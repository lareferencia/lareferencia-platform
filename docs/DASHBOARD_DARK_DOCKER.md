# Verificación de dARK y estadísticas en Docker

El 24 de noviembre de 2026 se probó Dashboard `4371435` con Harvester `52b8202` en Chrome, usando un Harvester Docker y una copia PostgreSQL local. Un proxy local dirigió las rutas profundas a la SPA. Ambos módulos cargaron desde el appConfig publicado.

- AREANDINA (red 33) tenía 3.856 ARK documentados en la copia, con 3.229 publicados y 627 borradores. El filtro **Publicado**, con el 11 de octubre de 2026 como inicio y fin UTC, devolvió 3.229 resultados. La primera página mostró 25 y el CSV descargado por la URL de la interfaz incluyó las 3.229 filas publicadas de ese día. La búsqueda por un ARK del resultado devolvió una coincidencia y el 12 de octubre devolvió cero.
- En Uruguay se configuró el identificador conocido `SITEID::58` en la copia. El widget consultó el proveedor real y recibió HTTP 200 con 716.933 vistas y 112.413 descargas para su consulta inicial.
