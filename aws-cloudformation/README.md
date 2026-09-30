# AWS CloudFormation

La infraestructura se divide en un stack base y dos stacks de máquinas. La
base usa la VPC/subnet públicas existentes, despliega Headscale/Headplane y
exporta la red. Las máquinas importan esos exports, crean su Security Group y
EBS, usan SSM y se enrolan automáticamente en Headscale.

| Stack | Plantilla | Preparación |
|---|---|---|
| `lareferencia-base` | `base.yaml` | Headscale, Headplane, EIP, DNS y exports de red |
| `lareferencia-semantic-services` | `semantic-services.yaml` | Docker, Java 21 y Solr standalone con core `biblio` persistido en EBS |
| `lareferencia-vufind-services` | `vufind-services.yaml` | Apache, PHP y MariaDB; instala dos checkouts VuFind desde el repo/ref parametrizado |

El stack base configura Headscale con policy ACL en la base de datos. Durante
el bootstrap crea el usuario indicado por `HeadscaleTagOwnerUsername` y valida
antes de guardar la policy inicial: solo permite tráfico entre nodos con
`tag:lareferencia`, y solo ese usuario puede asignar el tag. Para este entorno
el usuario inicial es `lmatas`; el mismo valor se usa en
`machines/lareferencia-base.yaml`.

Cada plantilla contiene el bootstrap de su máquina. El disco de datos semantic
usa 500 GiB, incluidos Docker y los datos de Solr; VuFind usa 50 GiB además del
root de 30 GiB.

El checkout de VuFind se selecciona en
`machines/lareferencia-vufind-services.yaml` mediante `VufindRepositoryUrl` y
`VufindRef` (tag o branch). El stack semántico recibe los mismos parámetros
para cargar el configset `biblio` y sus JAR en Solr. Mantén repo/ref iguales en
ambos archivos. El bootstrap instala dependencias con Composer, omite la
descarga de un Solr local, inicializa dos bases MariaDB separadas con
contraseñas aleatorias y configura cada sitio para su endpoint Solr.

La imagen de Solr se selecciona en
`machines/lareferencia-semantic-services.yaml`, en `SolrImage`. El parámetro
acepta cualquier referencia de imagen accesible por Docker, sin una lista de
versiones permitidas; por ejemplo, tags estables, `-slim`, snapshots o tags de
desarrollo publicados por el proyecto. Si el tag no existe o no es accesible,
el bootstrap de la instancia falla al ejecutar `docker pull`.

`machines/` guarda los parámetros particulares. El nombre del YAML determina
el stack; el sufijo de la plantilla se obtiene quitando `lareferencia-`. Por
ejemplo, el config
`machines/lareferencia-vufind-services.yaml` se despliega con
`vufind-services.yaml`.

## Despliegue

Primero completa `HostedZoneId` y `HeadscaleHostname` en
`machines/lareferencia-base.yaml`. Planifica y aplica la base antes de crear
change sets para las máquinas:

```bash
aws-cloudformation/deploy-ec2.sh \
  --config aws-cloudformation/machines/lareferencia-base.yaml \
  --stack lareferencia-base --region us-east-1 --plan
```

Después de aplicar la base y comprobar Headscale, despliega primero Semantic:
VuFind importa el output `SolrUrl` de ese stack, por lo que Semantic debe
existir antes de crear el stack VuFind. Al aplicar, Rain solicita
`HeadscaleAuthKey`; la clave se omite deliberadamente de los archivos
versionados.

```bash
aws-cloudformation/deploy-ec2.sh \
  --config aws-cloudformation/machines/lareferencia-semantic-services.yaml \
  --stack lareferencia-semantic-services --region us-east-1 --plan

aws-cloudformation/deploy-ec2.sh \
  --config aws-cloudformation/machines/lareferencia-vufind-services.yaml \
  --stack lareferencia-vufind-services --region us-east-1 --plan
```

`--apply` ejecuta el change set. No se ha ejecutado durante la preparación de
estas plantillas.

La base reserva `100.64.0.0/24` para esta tailnet. dARK usa
`100.64.1.0/24`, por lo que ambos rangos quedan separados.

## Red y acceso

Cada plantilla da IP pública a la instancia para salida a Internet. Semantic
permite HTTP y la API de embeddings desde el proxy; Solr (`8983`) solo se abre
al CIDR interno de la VPC. VuFind permite HTTP desde el proxy. Las reglas son
parámetros del stack y se corrigen actualizando el change set. No añadir
Security Groups amplios como `AllOpenWarning`.

## Verificación operativa

```bash
aws-cloudformation/check-bootstrap.sh \
  --stack lareferencia-vufind-services --region us-east-1
python3 aws-cloudformation/monitor-ec2.py \
  --stack lareferencia-vufind-services --region us-east-1
```

VuFind deja los árboles de aplicación y datos MariaDB en el volumen de datos.
La configuración local institucional de VuFind, datos de catálogo y
certificados se incorporan en el paso de despliegue de aplicaciones. El core
`biblio` de Solr se prepara con la configuración y los JAR de la misma
referencia de VuFind seleccionada en ambos stacks.

Para administrar Headscale y Headplane:

```bash
aws-cloudformation/connect-ssm-headscale.sh --region us-east-1
aws-cloudformation/forward-headplane-ssm.sh --region us-east-1
```
