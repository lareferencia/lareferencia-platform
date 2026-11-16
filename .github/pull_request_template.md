Describe el cambio y su comportamiento esperado.

PR de módulos involucrados:

- <!-- repositorio#PR -->

Validación:

- [ ] Actualicé `workspace.lock` con los commits exactos que quiero integrar.
- [ ] Revisé la compilación y los tests de la combinación completa.

Si este PR coordina una release:

- [ ] Los PR de módulos ya están mergeados; el lock apunta a sus SHA finales.
- [ ] Tiene exactamente una etiqueta: `release:rc`, `release:stable`, `release:patch`, `release:minor` o `release:major`.
- [ ] Revisé la versión prevista en el resumen de CI.

El merge de un PR con etiqueta `release:*` publica la plataforma si los checks de release pasan.
