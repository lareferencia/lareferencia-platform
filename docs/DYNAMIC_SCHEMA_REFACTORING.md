# Refactorización de Generación Dinámica de Esquemas y Validación

Este documento detalla el proceso de refactorización realizado para reemplazar la definición estática de esquemas JSON por una generación dinámica basada en clases Java, así como la implementación de internacionalización (I18n) para reglas de validación y transformación.

## 1. Objetivo

El objetivo principal fue eliminar la dependencia de archivos estáticos (`.js` o `.json`) para definir los formularios y esquemas de validación en el frontend. En su lugar, se optó por generar estos esquemas dinámicamente a partir de las propias clases Java que implementan las reglas, utilizando anotaciones personalizadas. Esto reduce la duplicación de código, facilita el mantenimiento y asegura que el frontend siempre esté sincronizado con el backend.

Adicionalmente, se implementó soporte completo para internacionalización (I18n) en los títulos, descripciones y textos de ayuda de las reglas.

## 2. Cambios en el Backend (`lareferencia-core-lib` y `lareferencia-lrharvester-app`)

### 2.1. Nuevas Anotaciones

Se crearon dos anotaciones en el paquete `org.lareferencia.core.worker.validation`:

*   **`@ValidatorRuleMeta`**: Se aplica a nivel de clase. Define metadatos generales de la regla.
    *   `name`: Nombre por defecto de la regla.
    *   `help`: Texto de ayuda por defecto.
*   **`@SchemaProperty`**: Se aplica a los campos de la clase. Define cómo se representará el campo en el formulario.
    *   `title`: Etiqueta del campo.
    *   `description`: Descripción o tooltip.
    *   `order`: Orden de aparición en el formulario.
    *   `type`: (Opcional) Tipo de dato forzado (ej: "string", "integer").
    *   `uiType`: (Opcional) Tipo de widget de UI (ej: "textarea").
    *   `defaultValue`: (Opcional) Valor por defecto.

### 2.2. Servicio de Generación de Esquemas (`ValidatorRuleSchemaService`)

Se implementó el servicio `ValidatorRuleSchemaService` que:
1.  **Escaneo Dinámico**: Utiliza `ClassPathScanningCandidateComponentProvider` de Spring para escanear el paquete `org.lareferencia` en busca de clases que implementen `IValidatorRule` o `ITransformerRule` y estén anotadas con `@ValidatorRuleMeta`.
2.  **Construcción de Esquemas**: Para cada clase encontrada, inspecciona sus campos anotados con `@SchemaProperty` (y `@JsonProperty`) para construir un objeto `RuleSchemaDefinition` que contiene el esquema JSON (compatible con `angular-schema-form`) y la definición del formulario.
3.  **Soporte de Tipos Complejos**: Maneja listas (`List<String>`, `List<ClaseCompleja>`) generando sub-esquemas anidados recursivamente.
4.  **Internacionalización**: Inyecta `MessageSource` para resolver los textos. Busca claves específicas en los archivos de propiedades (ver sección 3).

### 2.3. Controlador REST (`ValidationSchemaController`)

Se expusieron dos nuevos endpoints en `ValidationSchemaController`:

*   `GET /public/validation/validator-rules-schemas`
*   `GET /public/validation/transformer-rules-schemas`

Ambos aceptan un parámetro opcional `locale` (ej: `?locale=pt-BR`). Si no se provee, se utiliza el `Locale` resuelto por Spring (basado en el header `Accept-Language`).

### 2.4. Configuración de I18n

*   **`I18nConfig`**: Se configuró un bean `ReloadableResourceBundleMessageSource` que lee archivos de propiedades desde `file:config/i18n/messages`.
*   **Archivos de Propiedades**: Se crearon los archivos:
    *   `config/i18n/messages.properties` (Español - Default)
    *   `config/i18n/messages_en.properties` (Inglés)
    *   `config/i18n/messages_pt.properties` (Portugués)

Las claves siguen el patrón:
*   Regla: `rule.<SimpleClassName>.name` y `rule.<SimpleClassName>.help`
*   Campo: `rule.<SimpleClassName>.field.<fieldName>.title` y `rule.<SimpleClassName>.field.<fieldName>.description`

## 3. Cambios en el Frontend (`static/`)

### 3.1. Servicios de Esquemas

Se actualizaron `transformation-json-schemas.js` y `validation-json-schemas.js`.
*   **Eliminación de Estáticos**: Se eliminaron las definiciones JSON hardcodeadas.
*   **Carga Dinámica**: El método `load(locale)` ahora realiza una petición HTTP a los nuevos endpoints del backend.
*   **Parámetro Locale**: Se acepta un argumento `locale` que se pasa como query param al backend.

### 3.2. Controlador de Reglas (`rules.js`)

*   Se modificó la llamada a `load()` para pasar `navigator.language`, asegurando que el backend reciba la preferencia de idioma del navegador del usuario.
*   **Fallback de Paquetes**: Se agregó lógica para manejar nombres de clases "legacy" (paquetes antiguos `org.lareferencia.backend...`) y mapearlos a los nuevos (`org.lareferencia.core...`) para mantener compatibilidad con reglas ya guardadas en base de datos.

## 4. Guía para Desarrolladores

### Cómo agregar una nueva regla

1.  Cree la clase Java implementando `IValidatorRule` o `ITransformerRule`.
2.  Anote la clase con `@ValidatorRuleMeta(name = "...", help = "...")`.
3.  Anote los campos configurables con `@SchemaProperty(title = "...", description = "...", order = N)`. Asegúrese de tener getters/setters y `@JsonProperty` si es necesario para la serialización JSON.
4.  (Opcional) Agregue las traducciones en `config/i18n/messages_*.properties` utilizando las claves generadas (ver sección 2.4). Si no las agrega, se usarán los valores definidos en las anotaciones como fallback.

### Cómo agregar/modificar traducciones

Edite los archivos en `lareferencia-lrharvester-app/config/i18n/`. No es necesario recompilar el código Java, pero sí reiniciar la aplicación para que el `ReloadableResourceBundleMessageSource` tome los cambios (dependiendo de la configuración de caché).

## 5. Estado Actual

*   Todas las reglas de validación y transformación existentes han sido anotadas.
*   Los endpoints están funcionales y soportan I18n.
*   El frontend consume los esquemas dinámicos respetando el idioma del navegador.
