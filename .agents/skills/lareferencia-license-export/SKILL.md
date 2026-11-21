---
name: lareferencia-license-export
description: Extraer licencias de dc.rights de una o varias redes de LA Referencia, revisar valores únicos y contar los registros que declaran cada valor.
---

# Exportación de licencias

La entrega por registro contiene `data.licenses`. Si ya hay un export, comprobar su manifiesto y su `mapping.json` antes de reutilizarlo. Para extraerlo del LGK usar el perfil del shell `config/exports/licenses-v1.json`. Ejemplo para todos los activos de UY con metadata original:

```text
export-metadata --network UY --variant original --format jsonl --mapping config/exports/licenses-v1.json --compression gzip --output /srv/metadata-exports
```

Respetar la variante y el alcance solicitados. Para un inventario por país, contar un paquete completo de una sola red por vez. Desde el checkout de plataforma:

```sh
python3 scripts/count_export_licenses.py "$EXPORT_DIR" --max-text-length 120 > "$LICENSES_JSONL"
```

El inventario contiene una línea por valor con `value` y `recordCount`. Una repetición dentro del mismo registro cuenta una vez. El contador omite vacíos y vocabularios COAR e info:eu-repo. Acepta URL web más largas que el límite aplicado al texto libre; para un límite estricto aplicable también a URL, respetar el criterio pedido al filtrar la entrega. Consultar `docs/LICENSE_METADATA_EXTRACTION.md` en plataforma para los detalles del proceso y verificar los filtros del perfil que quedó en el paquete.
