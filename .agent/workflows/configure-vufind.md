---
description: Workflow para configurar opciones comunes en VuFind (Tema, ILS, Búsqueda).
---

# Configurar VuFind

Sigue estos pasos para modificar la configuración de VuFind en tu entorno local Docker.

## 1. Identificar el archivo de configuración

La mayoría de las configuraciones globales están en `config.ini` dentro del directorio local.

```bash
ls -l /home/juan-manitta/Escritorio/Trabajo/LA_Referencia/lareferencia-platform/vufind/local/docker/config/vufind/
```

## 2. Editar `config.ini` (Configuración Global)

Abre el archivo `config.ini` para modificar:
- [Site] -> `theme` (Tema visual)
- [Site] -> `sidebarOnLeft` (Posición de la barra lateral)
- [Catalog] -> `driver` (Driver del ILS)
- [Authentication] -> `method` (Método de login)

Haz tus cambios usando un editor o solicita al asistente que lo haga.

Ejemplo: Cambiar el tema
```ini
[Site]
theme = nuevo-tema
```

## 3. Editar `searches.ini` (Opcional - Búsqueda)

Si necesitas cambiar cómo funcionan las búsquedas o qué campos se usan, edita `searches.ini`.

**Nota**: Si este archivo no existe en tu carpeta local `vufind/local/docker/config/vufind/`, debes copiarlo desde `vufind/config/vufind/searches.ini` antes de editarlo. **NUNCA** edites el archivo en `vufind/config/vufind/` directamente.

## 4. Editar `facets.ini` (Opcional - Filtros)

Para cambiar los filtros (facetas) en la barra lateral. Al igual que `searches.ini`, asegúrate de tener una copia local.

## 5. Aplicar cambios

Para que algunos cambios surtan efecto (especialmente en `facets.ini` o cambios de estructura), puede ser necesario limpiar la caché.

// turbo
```bash
# Comando para limpiar caché (si es necesario)
# En este entorno Docker, a veces un simple refresh del navegador basta para config.ini
echo "Recuerda recargar tu navegador con Ctrl+Shift+R"
```

## 6. Verificar

Abre tu navegador y verifica que los cambios se hayan aplicado correctamente.
- ¿La barra lateral cambió de lado?
- ¿El tema es el correcto?
