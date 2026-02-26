---
name: VuFind Configuration Skill
description: Referencia completa y guía para configurar VuFind en Docker (config.ini, searches.ini, facets.ini, etc.).
---

# VuFind Configuration Skill

Este skill consolida todo el conocimiento necesario para configurar y personalizar VuFind en el entorno Docker.

## Parte 1: Guía de Configuración

Esta sección explica la arquitectura y las tareas comunes.

### 1. Arquitectura de Configuración

VuFind utiliza un sistema de configuración en cascada.
- **Configuración Base**: `vufind/config/vufind/` (**NO EDITAR**).
- **Configuración Local**: `vufind/local/docker/config/vufind/` (**EDITAR AQUÍ**).

Los archivos en el directorio local sobrescriben las configuraciones base.

### 2. Archivos Clave

| Archivo | Propósito | Principales Ajustes |
| :--- | :--- | :--- |
| `config.ini` | Configuración Global | URL, Tema, Base de Datos, Autenticación |
| `NoILS.ini` | Driver Simulado | Configuración cuando no hay ILS real |
| `searches.ini` | Búsqueda | Tipos de búsqueda, ordenamiento, recomendaciones |
| `facets.ini` | Filtros (Facetas) | Qué filtros mostrar en resultados |
| `permissions.ini` | Seguridad | Permisos de acceso |

### 3. Tareas Comunes

#### Cambiar Tema
En `vufind/local/docker/config/vufind/config.ini`:
```ini
[Site]
theme = mi-tema
```

#### Cambiar Posición de Sidebar
En `vufind/local/docker/config/vufind/config.ini`:
```ini
[Site]
sidebarOnLeft = true
```

#### Limpiar Caché
```bash
php public/index.php util/cleanup_record_cache
```

---

## Parte 2: Referencia Completa de Opciones

Esta sección actúa como un diccionario detallado de todas las opciones disponibles en los archivos .ini principales.

### 1. **config.ini** (Configuración Global)

## [System]
- `available`: `true`/`false`. Pone el sistema en modo mantenimiento.
- `debug`: `true`/`false`. Muestra mensajes de depuración en pantalla.
- `autoConfigure`: `true`/`false`. Deshabilita la pantalla de auto-configuración tras la instalación.
- `healthCheckFile`: Ruta a un archivo que simula un error del servidor (para balanceadores de carga).

## [Site]
- `url`: URL base de la instalación (ej. `http://localhost:8080`).
- `email`: Dirección de correo para soporte.
- `title`: Título del sitio web.
- `theme`: Tema activo (ej. `bootstrap5`, `sandal5`).
- `mobile_theme`: Tema para dispositivos móviles.
- `admin_theme`: Tema para el panel de administración.
- `language`: Idioma por defecto (ej. `es`, `en`).
- `locale`: Configuración regional (ej. `es_ES`, `en_US`).
- `timezone`: Zona horaria (ej. `America/New_York`).
- `defaultModule`: Módulo de inicio (usualmente `Search`).
- `defaultAccountPage`: Página de inicio tras login (usualmente `Favorites` o `Holds`).
- `sidebarOnLeft`: `true` para barra lateral a la izquierda.
- `showBookBag`: `true`/`false` para activar el "carrito".

## [Catalog]
- `driver`: Driver del ILS. Opciones: `Aleph`, `Alma`, `Koha`, `NoILS`, etc.
- `holds_mode`: Controla la visibilidad de enlaces de reservas (`all`, `holds`, `recalls`, `disabled`).
- `renewals_enabled`: `true`/`false` para permitir renovaciones.
- `cancel_holds_enabled`: `true`/`false` para cancelar reservas.

## [Authentication]
- `method`: Método de autenticación. `Database`, `LDAP`, `Shibboleth`, `CAS`, `ILS`.
- `hideLogin`: `true` para ocultar el botón de login.
- `change_password`: `true`/`false` para permitir cambio de contraseña.
- `recover_password`: `true`/`false` para permitir recuperación por email.

## [Index]
- `url`: URL del servidor Solr (ej. `http://solr:8983/solr`).
- `default_core`: Core bibliográfico (usualmente `biblio`).

## [Database]
- `database`: Cadena de conexión (ej. `mysql://user:pass@host/db`).
- `schema`: Esquema (para PostgreSQL).

## [Mail]
- `host`: Servidor SMTP.
- `port`: Puerto SMTP.
- `secure`: `tls` o `ssl`.
- `email_action`: `enabled`, `disabled`, `require_login` para enviar registros por correo.

## [Content]
Configuración para contenido enriquecido (portadas, reseñas):
- `coverimages`: Proveedores de portadas (Google, OpenLibrary, etc.).
- `reviews`: Proveedores de reseñas.
- `excerpts`: Proveedores de extractos.

---

### 2. **searches.ini** (Búsqueda)

## [General]
- `default_handler`: Búsqueda por defecto (`AllFields`).
- `default_sort`: Ordenación por defecto (`relevance`, `year`, `title`, `author`).
- `default_view`: Vista por defecto (`list`, `grid`).
- `default_limit`: Resultados por página (ej. 20).
- `highlighting`: `true` para resaltar términos de búsqueda.
- `snippets`: `true` para mostrar fragmentos con contexto.

## [Basic_Searches]
Mapeo de nombres de búsqueda a índices de Solr:
- `AllFields = "Todos los campos"`
- `Title = "Título"`
- `Author = "Autor"`

## [Advanced_Searches]
Campos disponibles en búsqueda avanzada.

## [Sorting]
Opciones de ordenación disponibles para el usuario:
- `relevance = "Relevancia"`
- `year = "Año (Descendente)"`
- `year asc = "Año (Ascendente)"`

## [Autocomplete]
- `enabled`: `true`/`false`.
- `default_handler`: Handler usado para sugerencias (usualmente `Solr`).

---

### 3. **facets.ini** (Filtros)

## [Results]
Facetas que aparecen en la barra lateral de resultados:
- `institution = "Institución"`
- `format = "Formato"`
- `author_facet = "Autor"`
- `language = "Idioma"`
- `publishDateRange = "Año de publicación"`

## [ResultsTop]
Facetas que aparecen encima de los resultados (horizontal).

## [Advanced]
Facetas disponibles en la pantalla de búsqueda avanzada.

## [SpecialFacets]
Configuración especial para:
- `dateRange`: Faceta de rango de fechas (slider).
- `hierarchical`: Facetas jerárquicas.

---

### 4. **permissions.ini** (Seguridad y Acceso)

Define quién puede acceder a qué partes del sistema.

## [default.AdminModule]
Controla acceso al panel de administración.
- `role = loggedin`: Solo usuarios logueados.
- `ipRange = 127.0.0.1`: Solo desde localhost.

---

### 5. **export.ini** (Exportación)

Formatos disponibles para exportar registros:
- `[RefWorks]`
- `[EndNote]`
- `[MARC]`
- `[BibTeX]`
- `[RIS]`

Cada sección define:
- `requiredMethods`: Métodos necesarios en el driver.
- `headers`: Headers HTTP para la descarga.

---

### 6. **NoILS.ini** (Driver Simulado)

Usado cuando `driver = NoILS` en `config.ini`.

## [settings]
- `mode`: `ils-none` (sin ILS) o `ils-offline` (ILS caído).
- `hideLogin`: Ocultar login cuando se usa este driver.

## [Holdings]
Mensajes estáticos para disponibilidad:
- `availability = false`
- `status = "Library System Unavailable"`

---

### 7. Lista de Otros Archivos .ini Disponibles

Además de los anteriores, VuFind incluye configuraciones específicas para:

#### Drivers ILS
- `Aleph.ini`, `Alma.ini`, `Amicus.ini`, `DAIA.ini`, `Demo.ini`, `Evergreen.ini`, `Folio.ini`, `GeniePlus.ini`, `Horizon.ini`, `Innovative.ini`, `Koha.ini`, `MultiBackend.ini`, `NewGenLib.ini`, `PAIA.ini`, `Polaris.ini`, `Primo.ini`, `Sierra.ini`, `Symphony.ini`, `Unicorn.ini`, `Virtua.ini`, `Voyager.ini`, `XCNCIP2.ini`.

#### Funcionalidades Específicas
- `AccountMenu.yaml`: Menú de usuario.
- `AdminMenu.yaml`: Menú de administración.
- `alpha_browse.ini`: Navegación alfabética.
- `authority.ini`: Búsqueda de autoridades.
- `browse.ini`: Navegación por materias/autores.
- `channels.ini`: Canales de descubrimiento visual.
- `Collection.ini`: Configuración de colecciones.
- `contentsecuritypolicy.ini`: Cabeceras de seguridad CSP.
- `CookieConsent.yaml`: Configuración de consentimiento de cookies.
- `FeedbackForms.yaml`: Formularios de contacto.
- `fulltext.ini`: Búsqueda en texto completo.
- `geofeatures.ini`: Búsqueda por mapa.
- `NetCommons.ini`: Integración NetCommons.
- `oai.ini`: Servidor OAI-PMH.
- `OAuth2Server.yaml`: Servidor OAuth2.
- `OpenIDConnect.ini`: Login OIDC.
- `Primo.ini`: Búsqueda en Primo Central.
- `QRCode.ini`: Generación de códigos QR.
- `RateLimiter.yaml`: Límite de peticiones (anti-abuse).
- `RecordTabs.ini`: Pestañas en la vista de detalle del registro.
- `reserves.ini`: Búsqueda de reservas de cursos.
- `searchspecs.yaml`: Mapeo avanzado de campos Solr.
- `sitemap.ini`: Generación de sitemap.xml.
- `sms.ini`: Configuración de envío SMS.
- `Summon.ini`: Búsqueda en Summon.
- `website.ini`: Búsqueda en sitio web (Core separado).
- `WorldCat.ini`: API de WorldCat.

---

## Recomendación Final

Para cualquier personalización:
1.  **NO** edites los archivos en `config/vufind/`.
2.  **COPIA** el archivo deseado a `local/docker/config/vufind/`.
3.  **EDITA** solo las líneas que necesitas cambiar en la copia local.
