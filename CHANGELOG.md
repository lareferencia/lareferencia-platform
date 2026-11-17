# Changelog

Los cambios relevantes de la plataforma se registran aquí antes de publicarse.
Al preparar una release, mover las entradas incluidas de `Unreleased` a una
sección con su versión y fecha, y conservar `Unreleased` para nuevos cambios.

## Unreleased

### Correcciones

- Corrige la copia de recursos estáticos al construir la imagen Docker del
  proveedor OAI-PMH: utiliza el directorio `static/` en lugar de `static_en/`.
  ([#112](https://github.com/lareferencia/lareferencia-platform/pull/112))
