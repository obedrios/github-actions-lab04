---
sidebar_position: 3
title: "M3 — Publicación de la imagen en Amazon ECR"
description: "Publicación manual de una imagen OCI single-platform de Docusaurus en Amazon ECR, incluyendo autenticación AWS, tags inmutables, digest, análisis de vulnerabilidades y estudio de OCI Image Manifest vs OCI Image Index."
tags:
  - aws
  - amazon-ecr
  - docker
  - buildkit
  - oci
  - containers
  - docusaurus
  - devops
  - lab04
---

# M3 — Publicación de la imagen en Amazon ECR

## Objetivo

Publicar en **Amazon Elastic Container Registry (Amazon ECR)** la imagen Docker de Docusaurus creada y validada durante **M2**.

Durante este milestone también estudiaremos una diferencia importante del estándar OCI:

- **OCI Image Manifest**
- **OCI Image Index**

El flujo principal publicará una imagen **single-platform** como OCI Image Manifest bajo un único tag:

```text
m3-v1
```

El OCI Image Index se generará únicamente como un artefacto local de aprendizaje para comprender por qué una imagen construida con provenance, SBOM o múltiples plataformas puede terminar representada mediante un índice.

El objetivo principal es demostrar:

```text
Docusaurus
    │
    ▼
Docker / BuildKit
    │
    ▼
OCI Image Manifest
    │
    ▼
Amazon ECR
    │
    ▼
m3-v1
    │
    ▼
Digest
    │
    ▼
Vulnerability Scan
```

En este milestone todavía **no utilizaremos Amazon ECS ni AWS Fargate**.

El criterio principal de salida será:

> **PASS:** la imagen `lab04-docusaurus:m3-v1` se publica en Amazon ECR como un image manifest single-platform, dispone de digest verificable, puede ser analizada por ECR Basic Scanning, descargada nuevamente y ejecutada correctamente de forma local.

---

## Alcance

M3 introduce:

- AWS CLI.
- Identidad AWS.
- Amazon ECR.
- Repositorios privados.
- Docker authentication contra ECR.
- Docker Buildx / BuildKit.
- OCI Image Manifest.
- OCI Image Index.
- Provenance attestations.
- SBOM attestations.
- Tags inmutables.
- Image digest.
- Vulnerability scanning.
- Pull desde ECR.
- Validación del artefacto recuperado.

Este milestone todavía no incluye:

```text
Amazon ECS
AWS Fargate
Application Load Balancer
CloudWatch Logs
GitHub Actions
OIDC CI/CD
```

---

## 1. Estado inicial

Al finalizar M2 disponemos localmente de:

```text
lab04-docusaurus:local
```

Verificar:

```bash
docker image ls lab04-docusaurus
```

Ejemplo:

```text
REPOSITORY          TAG       IMAGE ID       SIZE
lab04-docusaurus    local     abc123...      ...
```

Nuestra arquitectura hasta ahora es:

```text
Docusaurus Source
       │
       ▼
Docker Build
       │
       ▼
lab04-docusaurus:local
       │
       ▼
Local Container
```

M3 agregará un registry remoto:

```text
Local Image
    │
    ▼
Amazon ECR
    │
    ▼
Versioned Artifact
```

---

## 2. Arquitectura de M3

```text
                    AWS
                     │
                     ▼
            ┌─────────────────┐
            │   Amazon ECR    │
            │                 │
            │ Private Registry│
            └────────┬────────┘
                     │
                     ▼
            lab04-docusaurus
                     │
                     ▼
                   m3-v1
                     │
                     ▼
              OCI Manifest
                     │
                     ▼
                  digest
```

ECR será únicamente el **container registry**.

La aplicación todavía no estará ejecutándose en AWS.

---

## 3. Prerrequisitos

M2 debe estar completado.

Verificar Docker:

```bash
docker --version
```

Verificar Buildx:

```bash
docker buildx version
```

Verificar AWS CLI:

```bash
aws --version
```

Iniciar sesión con el perfil utilizado para el laboratorio:

```bash
aws login --profile aws-lab
```

Comprobar la identidad:

```bash
aws sts get-caller-identity --profile aws-lab
```

Esperamos una respuesta similar a:

```json
{
  "UserId": "...",
  "Account": "123456789012",
  "Arn": "..."
}
```

Esta operación confirma qué identidad AWS estamos utilizando.

---

## 4. Definir variables del laboratorio

Definir la región:

```bash
export AWS_REGION="us-east-1"
```

Definir el repositorio:

```bash
export ECR_REPOSITORY="lab04-docusaurus"
```

Obtener el Account ID:

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
  --profile aws-lab \
  --query Account \
  --output text)
```

Construir la URI del registry:

```bash
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
```

Construir la URI del repositorio:

```bash
export ECR_REPOSITORY_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}"
```

Definir el único tag utilizado durante M3:

```bash
export IMAGE_TAG="m3-v1"
```

Verificar:

```bash
echo "AWS_REGION=${AWS_REGION}"
echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
echo "ECR_REGISTRY=${ECR_REGISTRY}"
echo "ECR_REPOSITORY_URI=${ECR_REPOSITORY_URI}"
echo "IMAGE_TAG=${IMAGE_TAG}"
```

---

## 5. Convención de versionado

Durante todo M3 utilizaremos exclusivamente:

```text
m3-v1
```

No utilizaremos:

```text
latest
```

ni tags alternativos para corregir errores durante el laboratorio.

Conceptualmente:

```text
lab04-docusaurus
        │
        └── m3-v1
```

Posteriormente, durante CI/CD, podremos utilizar identificadores derivados del Git commit SHA.

En M3 queremos mantener el experimento deliberadamente simple.

---

## 6. OCI Image Manifest vs OCI Image Index

Antes de publicar la imagen debemos distinguir dos estructuras OCI.

### OCI Image Manifest

Un **OCI Image Manifest** describe una imagen concreta:

```
OCI Image Manifest
      │
      ├── config
      │
      ├── layer
      ├── layer
      └── layer
```

Su media type es:

```
application/vnd.oci.image.manifest.v1+json
```

Este será el formato objetivo para:

```
m3-v1
```

### OCI Image Index

Un **OCI Image Index** es un nivel superior que puede referenciar varios manifests.

Ejemplo:

```
OCI Image Index
       │
       ├── linux/amd64 manifest
       │
       ├── linux/arm64 manifest
       │
       └── attestation manifest
```

Su media type es:

```
application/vnd.oci.image.index.v1+json
```

Los índices son útiles para:

- imágenes multi-platform;
- provenance;
- SBOM;
- otros artefactos y attestations.

Por tanto:

```
Manifest
   ≠
Index
```

Un manifest describe normalmente una imagen concreta.

Un index puede describir o agrupar múltiples manifests.

---

## 7. Hallazgo experimental

Durante la primera ejecución de M3 se publicó una imagen cuyo media type fue:

```text
application/vnd.oci.image.index.v1+json
```

Al consultar el scan:

```bash
aws ecr describe-image-scan-findings \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

se obtuvo inicialmente:

```text
aws ecr describe-image-scan-findings \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

Al intentar iniciar manualmente el scan:

```bash
aws ecr start-image-scan \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

se obtuvo:

```text
UnsupportedImageTypeException
```

con el mensaje:

```text
An artifact with media type
'application/vnd.oci.image.index.v1+json'
cannot be scanned.
```

Esto nos permitió identificar una diferencia importante entre:

```text
OCI Image Index
```

y:

```text
OCI Image Manifest
```

---

## 8. Generar un OCI Image Index como experimento local

Antes de construir la imagen que publicaremos, podemos producir deliberadamente un artefacto OCI con attestations.

Este artefacto **no será publicado en ECR**.

Ejecutar:

```bash
docker buildx build \
  --platform linux/amd64 \
  --provenance=mode=max \
  --sbom=true \
  --output type=oci,dest=lab04-oci-index.tar \
  .
```

Esto genera:

```text
lab04-oci-index.tar
```

Podemos inspeccionar el OCI layout:

```bash
mkdir -p /tmp/lab04-oci-index
tar -xf lab04-oci-index.tar -C /tmp/lab04-oci-index
```

Revisar:

```bash
cat /tmp/lab04-oci-index/index.json
```

Si `jq` está disponible:

```bash
jq . /tmp/lab04-oci-index/index.json
```

Conceptualmente encontraremos una estructura tipo:

```text
OCI Layout
    │
    ▼
index.json
    │
    ├── image manifest
    │
    └── attestation information
```

Este ejercicio sirve únicamente para entender cómo BuildKit puede producir estructuras OCI más complejas.

No utilizaremos este artefacto como la imagen final de M3.

---

## 9. Arquitectura que queremos publicar

Nuestro flujo final será deliberadamente:

```text
Docusaurus
    │
    ▼
BuildKit
    │
    │ single platform
    │ provenance disabled
    │ SBOM disabled
    ▼
OCI Image Manifest
    │
    ▼
Amazon ECR
    │
    ▼
m3-v1
    │
    ▼
Basic Image Scan
```

De esta manera aislamos el concepto principal del laboratorio:

> Una aplicación, una plataforma, un image manifest, un tag.

---

## 10. Crear el repositorio privado ECR

Ejecutar:

```bash
aws ecr create-repository \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --region "${AWS_REGION}"
```

Esperamos información como:

```json
{
    "repository": {
        "repositoryArn": "arn:aws:ecr:us-east-1:565866186032:repository/lab04-docusaurus",
        "registryId": "565866186032",
        "repositoryName": "lab04-docusaurus",
        "repositoryUri": "565866186032.dkr.ecr.us-east-1.amazonaws.com/lab04-docusaurus",
        "createdAt": "2026-10-10T16:26:58.597000-07:00",
        "imageTagMutability": "IMMUTABLE",
        "imageScanningConfiguration": {
            "scanOnPush": true
        },
        "encryptionConfiguration": {
            "encryptionType": "AES256"
        }
    }
}

```

La propiedad:

```text
IMMUTABLE
```

significa que mientras:

```text
m3-v1
```

exista, no podremos sustituir silenciosamente su contenido por otra imagen.

---

## 11. Verificar el repositorio

Ejecutar:

```bash
aws ecr describe-repositories \
  --profile aws-lab \
  --repository-names "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}"
```

Resultando,

```json
{
    "repositories": [
        {
            "repositoryArn": "arn:aws:ecr:us-east-1:565866186032:repository/lab04-docusaurus",
            "registryId": "565866186032",
            "repositoryName": "lab04-docusaurus",
            "repositoryUri": "565866186032.dkr.ecr.us-east-1.amazonaws.com/lab04-docusaurus",
            "createdAt": "2026-10-10T16:26:58.597000-07:00",
            "imageTagMutability": "IMMUTABLE",
            "imageScanningConfiguration": {
                "scanOnPush": true
            },
            "encryptionConfiguration": {
                "encryptionType": "AES256"
            }
        }
    ]
}
```



Obtener únicamente la URI:

```bash
aws ecr describe-repositories \
  --profile aws-lab \
  --repository-names "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}" \
  --query 'repositories[0].repositoryUri' \
  --output text
```

Resulta en, `565866186032.dkr.ecr.us-east-1.amazonaws.com/lab04-docusaurus`



---

## 12. Checkpoint 1 — Repositorio ECR

```text
[ ] AWS CLI funciona
[ ] aws-lab tiene una sesión válida
[ ] Región definida
[ ] Account ID obtenido
[ ] ECR repository creado
[ ] Repository es privado
[ ] Tags configurados como IMMUTABLE
[ ] scanOnPush habilitado
[ ] Repository URI obtenida
```

Resultado:

```text
Checkpoint 1: PASS
```

---

## 13. Autenticar Docker contra Amazon ECR

Ejecutar:

```bash
aws ecr get-login-password \
  --profile aws-lab \
  --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${ECR_REGISTRY}"
```

Resultado esperado:

```bash
WARNING! Your credentials are stored unencrypted in '~/.docker/config.json'.
Configure a credential helper to remove this warning. See

Login Succeeded
```

Conceptualmente:

```text
AWS CLI
   │
   ▼
Temporary ECR Credential
   │
   ▼
Docker / BuildKit
   │
   ▼
Amazon ECR
```

---

## 14. Checkpoint 2 — Authentication

```text
[ ] get-login-password funciona
[ ] docker login funciona
[ ] Registry corresponde a la región correcta
[ ] Login Succeeded
```

Resultado:

```text
Checkpoint 2: PASS
```

---

## 15. Construir y publicar un OCI Image Manifest

Ahora construiremos específicamente una imagen:

```text
linux/amd64
```

sin provenance ni SBOM attestations.

Ejecutar:

```bash
docker buildx build \
  --platform linux/amd64 \
  --provenance=false \
  --sbom=false \
  --output type=image,push=true,oci-mediatypes=true \
  -t "${ECR_REPOSITORY_URI}:${IMAGE_TAG}" \
  .
```

Los parámetros importantes son:

```text
--platform linux/amd64
```

Limita el build a una sola plataforma.

```text
--provenance=false
```

Evita adjuntar provenance attestations.

```text
--sbom=false
```

Evita adjuntar SBOM attestations durante este ejercicio.

```text
oci-mediatypes=true
```

Solicita media types OCI.

```text
push=true
```

Publica directamente el resultado en el registry.

---

## 16. Por qué no usamos attestations en la imagen final de M3

Esto no significa que:

```text
provenance
```

o:

```text
SBOM
```

sean características negativas.

Por el contrario, son mecanismos importantes para software supply-chain security.

La decisión de M3 es únicamente pedagógica.

Queremos aislar:

```text
Single Platform
      +
OCI Image Manifest
      +
ECR Basic Scanning
```

Antes de introducir estructuras OCI más sofisticadas.

---

## 17. Verificar el push

La salida de BuildKit deberá terminar mostrando información relacionada con el push y el digest.

Conceptualmente:

```text
layers
   │
   ▼
manifest
   │
   ▼
Amazon ECR
   │
   ▼
sha256:...
```

---

## 18. Verificar la imagen desde ECR

Ejecutar:

```bash
aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

Podemos solicitar información compacta:

```bash
aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query 'imageDetails[0].[imageTags,imageDigest,imageManifestMediaType,imagePushedAt,imageSizeInBytes]' \
  --output table
```

Esperamos encontrar:

```markdown
-----------------------------------------------------------------------------
|                              DescribeImages                               |
+---------------------------------------------------------------------------+
|  m3-v1                                                                    |
|  sha256:2cf6092a4d4bacb046667a418511119752a904523c1c4e404ef1e1b6e1c40fa0  |
|  application/vnd.oci.image.manifest.v1+json                               |
|  2026-10-10T16:32:38.135000-07:00                                         |
|  26646042                                                                 |
+---------------------------------------------------------------------------+
```

El dato crítico es:

```text
application/vnd.oci.image.manifest.v1+json
```

y no:

```text
application/vnd.oci.image.index.v1+json
```

---

## 19. Checkpoint 3 — Media type

Verificar:

```text
[ ] m3-v1 existe en ECR
[ ] Tiene un digest sha256
[ ] imageManifestMediaType puede consultarse
[ ] El media type es OCI Image Manifest
[ ] El tag no apunta a un OCI Image Index
```

Resultado esperado:

```text
Checkpoint 3: PASS
```

---

## 20. Capturar el digest

Ejecutar:

```bash
export IMAGE_DIGEST=$(aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query 'imageDetails[0].imageDigest' \
  --output text)
```

Verificar:

```bash
echo "${IMAGE_DIGEST}"
```

Resultado:

```text
sha256:...
```

Ahora tenemos:

```text
+ Repository: lab04-docusaurus
+ Tag: m3-v1
+ Media Type: application/vnd.oci.image.manifest.v1+json
+ Digest: sha256:...
```

---

## 21. Tag vs Digest

El tag proporciona una referencia amigable:

```text
lab04-docusaurus:m3-v1
```

El digest identifica exactamente el contenido:

```text
sha256:...
```

Conceptualmente:

```text
m3-v1
  │
  ▼
OCI Image Manifest
  │
  ▼
sha256:...
```

Esta relación será muy importante durante M4.

---

## 22. Vulnerability scan

Como configuramos:

```text
scanOnPush=true
```

ECR puede iniciar el scan cuando recibe una imagen compatible.

Consultar:

```bash
aws ecr describe-image-scan-findings \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

Si todavía no existe un scan, iniciar manualmente:

```bash
aws ecr start-image-scan \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

Después consultar nuevamente:

```bash
aws ecr describe-image-scan-findings \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

---

## 23. Vista compacta del scan

Ejecutar:

```bash
aws ecr describe-image-scan-findings \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query '{
    Status: imageScanStatus.status,
    Findings: imageScanFindings.findingSeverityCounts
  }' \
  --output table
  
# O bien si se desea la salida en json
aws ecr describe-image-scan-findings \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query '{
    Status: imageScanStatus.status,
    Findings: imageScanFindings.findingSeverityCounts
  }' \
  --output json
```

Podemos encontrar categorías como:

```text
CRITICAL
HIGH
MEDIUM
LOW
INFORMATIONAL
```

La existencia de findings no significa automáticamente que la imagen no pueda ejecutarse.

El scan proporciona información para evaluar el riesgo de las dependencias y paquetes presentes.

---

## 24. Checkpoint 4 — Vulnerability scan

```text
[ ] El image manifest es compatible con el scanner
[ ] describe-image-scan-findings funciona
[ ] El scan puede iniciarse si fuera necesario
[ ] El estado del scan puede consultarse
[ ] findingSeverityCounts puede revisarse
```

Resultado:

```text
Checkpoint 4: PASS
```

---

## 25. Si m3-v1 ya existe por una ejecución anterior

Como el repositorio utiliza:

```text
IMMUTABLE
```

no debemos intentar sobrescribir:

```text
m3-v1
```

Si estamos repitiendo M3 porque una ejecución anterior publicó un OCI Image Index, eliminaremos primero esa imagen y reutilizaremos **el mismo tag**.

Ejecutar:

```bash
aws ecr batch-delete-image \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

Verificar:

```bash
aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}"
```

Después ejecutar nuevamente el build correcto.

La secuencia será:

```text
Incorrect m3-v1
OCI Image Index
       │
       ▼
delete image
       │
       ▼
rebuild
       │
       ▼
m3-v1
OCI Image Manifest
```

No introducimos otro tag.

---

## 26. Verificar desde AWS Console

Navegar:

```text
AWS Console
   │
   ▼
Amazon ECR
   │
   ▼
Private repositories
   │
   ▼
lab04-docusaurus
```

Localizar:

```text
m3-v1
```

Registrar como evidencia:

```text
Tag
Digest
Media type
Pushed at
Size
Scan status
```

---

## 27. Descargar la imagen desde ECR

Autenticar Docker si fuera necesario:

```bash
aws ecr get-login-password \
  --profile aws-lab \
  --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${ECR_REGISTRY}"
```

Descargar:

```bash
docker pull "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Verificar:

```bash
docker image ls
```

---

## 28. Ejecutar la imagen obtenida desde ECR

Ejecutar:

```bash
docker run \
  --rm \
  --name lab04-ecr-test \
  -d \
  -p 8080:80 \
  "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Verificar:

```bash
docker ps
```

---

## 29. Smoke test

Comprobar:

```bash
curl -I http://localhost:8080
```

Resultado esperado:

```text
HTTP/1.1 200 OK
Server: nginx
```

También podemos verificar una página Docusaurus:

```bash
curl -I -L \
  http://localhost:8080/docs/m1-docusaurus-bootstrap
```

Como aprendimos en M2, un flujo válido puede ser:

```text
301
 ↓
200
```

---

## 30. Checkpoint 5 — Registry round trip

```text
OCI Image Manifest
       │
       ▼
Amazon ECR
       │
       ▼
docker pull
       │
       ▼
Docker Image
       │
       ▼
Container
       │
       ▼
HTTP 200
```

Verificar:

```text
[ ] Imagen descargada desde ECR
[ ] docker run funciona
[ ] localhost:8080 responde HTTP 200
[ ] Docusaurus carga correctamente
[ ] Rutas de documentación funcionan
```

Resultado:

```text
Checkpoint 5: PASS
```

---

## 31. Limpiar el contenedor local

Ejecutar:

```bash
docker stop lab04-ecr-test
```

Después:

```bash
docker rm lab04-ecr-test
```

No eliminar:

```text
Amazon ECR repository
m3-v1
```

porque serán utilizados durante M4.

---

## 32. Revisar arquitectura de la imagen

Ejecutar:

```bash
docker image inspect \
  "${ECR_REPOSITORY_URI}:${IMAGE_TAG}" \
  --format '{{.Os}}/{{.Architecture}}'
```

Resultado esperado:

```text
linux/amd64
```

Este dato será necesario al configurar posteriormente la Task Definition de ECS/Fargate.

---

## 33. Evidencia del milestone

Registrar:

```text
Milestone:
M3 — Publicación de la imagen en Amazon ECR

Status:
PASS / FAIL

AWS:
- Profile: aws-lab
- Region:
- Account ID:
- ECR Repository:
- Repository URI:

Image:
- Tag: m3-v1
- Platform: linux/amd64
- Media Type:
- Digest:
- Size:

Repository:
- Visibility: Private
- Tag mutability: IMMUTABLE
- Scan on push: Enabled

OCI Experiment:
- OCI Image Index artifact generated:
- Provenance enabled:
- SBOM enabled:
- index.json inspected:

Final OCI Image:
- Provenance disabled:
- SBOM disabled:
- Media Type verified:
- Expected: application/vnd.oci.image.manifest.v1+json

Validation:
- AWS login:
- Docker/ECR authentication:
- Buildx push:
- describe-images:
- vulnerability scan:
- docker pull:
- docker run:
- HTTP smoke test:

Observed issues:
- ScanNotFoundException
- UnsupportedImageTypeException

Root cause:
- m3-v1 initially referenced an OCI Image Index.

Resolution:
- Built a single-platform OCI Image Manifest without provenance/SBOM
  attestations for this exercise.

Final validation:
- Media type is OCI Image Manifest.
- Vulnerability scan can be queried.
- Image can be pulled.
- Container returns HTTP 200.
```

---

## 34. Checklist final de M3

```text
M3 — Publicación de la imagen en Amazon ECR

[ ] M2 completado
[ ] Docker funciona
[ ] Docker Buildx funciona
[ ] AWS CLI funciona
[ ] aws-lab autenticado
[ ] Región definida
[ ] ECR repository creado
[ ] Repository es privado
[ ] IMMUTABLE habilitado
[ ] scanOnPush habilitado
[ ] Docker autenticado contra ECR

OCI concepts:

[ ] Diferencia entre Image Manifest e Image Index comprendida
[ ] OCI Image Index experimental generado localmente
[ ] index.json inspeccionado
[ ] Provenance/SBOM relacionados con attestations observados

Final image:

[ ] Una sola plataforma utilizada
[ ] linux/amd64 configurado
[ ] provenance=false
[ ] sbom=false
[ ] OCI media types habilitados
[ ] Único tag m3-v1 utilizado
[ ] Imagen publicada en ECR
[ ] Media type verificado
[ ] Media type corresponde a un Image Manifest
[ ] Digest sha256 registrado

Security:

[ ] Vulnerability scan consultado
[ ] ScanNotFoundException comprendido
[ ] UnsupportedImageTypeException comprendido

Registry round trip:

[ ] docker pull completado
[ ] docker run completado
[ ] GET / responde HTTP 200
[ ] Navegación Docusaurus funciona
[ ] Arquitectura linux/amd64 registrada
```

Si todo es correcto:

```text
M3 STATUS: PASS
```

## 35. Qué demostramos en M3

M1:

```text
Source
  │
  ▼
Docusaurus Build
```

M2:

```text
Source
  │
  ▼
Docker Image
  │
  ▼
Local Container
```

M3:

```text
Source
  │
  ▼
BuildKit
  │
  ▼
OCI Image Manifest
  │
  ▼
Amazon ECR
  │
  ├── tag: m3-v1
  │
  ├── digest: sha256
  │
  └── vulnerability scan
  │
  ▼
docker pull
  │
  ▼
Container
  │
  ▼
HTTP 200
```

También demostramos que:

```text
OCI Image Manifest
        ≠
OCI Image Index
```

y comprendimos por qué una estructura OCI válida puede no ser adecuada para una operación concreta como el Basic Image Scan del escenario estudiado.

---

## 36. Aprendizaje adicional — Software Supply Chain

El hallazgo de M3 introduce anticipadamente conceptos de software supply-chain security:

```text
Container Image
     │
     ├── provenance
     ├── SBOM
     ├── attestations
     └── signatures
```

En este laboratorio deshabilitamos provenance y SBOM únicamente para obtener un artefacto simple y compatible con el flujo de scanning que estamos estudiando.

En un entorno productivo estos mecanismos deberían evaluarse como características de seguridad, no eliminarse automáticamente.

---

## 37. Separación conceptual importante

Al finalizar M3 tenemos:

```text
Image Published
```

pero todavía no:

```text
Application Deployed
```

Amazon ECR:

```text
stores container artifacts
```

No ejecuta nuestra aplicación.

---

## 38. Conservación del recurso para M4

No eliminaremos:

```text
lab04-docusaurus:m3-v1
```

ni el repositorio ECR.

M4 utilizará exactamente este artefacto:

```text
Amazon ECR
      │
      ▼
lab04-docusaurus:m3-v1
      │
      ▼
OCI Image Manifest
      │
      ▼
ECS Task Definition
      │
      ▼
AWS Fargate
```

Esto nos permitirá conectar directamente:

```text
Tag
+
Digest
+
Architecture
```

con la Task Definition.

---

46. Limpieza opcional

Si se decide abandonar completamente el laboratorio antes de M4:

```bash
aws ecr delete-repository \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --force \
  --region "${AWS_REGION}"
```

No ejecutar este comando si se continuará con M4.

También podemos eliminar el artefacto local utilizado para estudiar OCI Index:

```bash
rm -f lab04-oci-index.tar
rm -rf /tmp/lab04-oci-index
```

---

## 39. Commit del milestone

Revisar:

```bash
git status
```

Agregar la documentación:

```bash
git add .
```

Commit sugerido:

```bash
git commit -m "docs: complete Amazon ECR milestone"
```

Publicar:

```bash
git push
```

---

## 40. Preparación para M4

El siguiente milestone será:

```text
M4 — Deployment manual en Amazon ECS + AWS Fargate
```

Partiremos exactamente de:

```text
Amazon ECR
      │
      ▼
lab04-docusaurus:m3-v1
      │
      ▼
linux/amd64
      │
      ▼
OCI Image Manifest
```

y construiremos:

```text
Amazon ECR
      │
      ▼
ECS Task Definition
      │
      ▼
ECS Service
      │
      ▼
AWS Fargate
      │
      ▼
Docusaurus + NGINX
      │
      ▼
Remote HTTP Request
```

Por primera vez tendremos la aplicación ejecutándose dentro de AWS.

---

## Criterio de salida

M3 puede considerarse cerrado cuando:

> Se comprende experimentalmente la diferencia entre OCI Image Index y OCI Image Manifest; `lab04-docusaurus:m3-v1` se publica como una imagen single-platform con media type de image manifest, dispone de digest verificable, puede analizarse mediante Amazon ECR Basic Scanning, descargarse nuevamente desde ECR y ejecutarse localmente con un smoke test HTTP satisfactorio.

```text
M3 STATUS: PASS
```

## Troubleshooting

### Troubleshooting real — ScanNotFoundException

Durante la primera ejecución observamos:

```text
ScanNotFoundException
```

al ejecutar:

```bash
aws ecr describe-image-scan-findings ...
```

Interpretación:

```text
Image exists
     │
     ▼
No scan exists for that artifact
```

Esto no indicaba que:

```text
docker push
```

hubiera fallado.

Indicaba únicamente que ECR no tenía un scan asociado al artefacto consultado.

---

### Troubleshooting real — UnsupportedImageTypeException

Posteriormente se ejecutó:

```bash
aws ecr start-image-scan ...
```

y se obtuvo:

```text
UnsupportedImageTypeException
```

con:

```text
application/vnd.oci.image.index.v1+json
```

La cadena del diagnóstico fue:

```text
m3-v1
   │
   ▼
OCI Image Index
   │
   ▼
ECR Basic Scanner
   │
   X
UnsupportedImageTypeException
```

El problema no estaba en:

- NGINX;
- Docusaurus;
- Alpine;
- Docker layers;
- ECR authentication.

El problema era el **tipo de artefacto** que estaba siendo solicitado al scanner.

---

### Resolución del hallazgo

La imagen se reconstruye deliberadamente como:

```text
single platform
+
no provenance attestation
+
no SBOM attestation
+
OCI media types
```

mediante:

```bash
docker buildx build \
  --platform linux/amd64 \
  --provenance=false \
  --sbom=false \
  --output type=image,push=true,oci-mediatypes=true \
  -t "${ECR_REPOSITORY_URI}:${IMAGE_TAG}" \
  .
```

El resultado deseado es:

```text
application/vnd.oci.image.manifest.v1+json
```

---

### Troubleshooting — No basic auth credentials

Síntoma:

```text
no basic auth credentials
```

Solución:

```bash
aws ecr get-login-password \
  --profile aws-lab \
  --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${ECR_REGISTRY}"
```

Verificar siempre:

```text
ECR Region
=
Login Region
```

---

### Troubleshooting — Repository does not exist

Verificar:

```bash
aws ecr describe-repositories \
  --profile aws-lab \
  --region "${AWS_REGION}"
```

Después:

```bash
echo "${ECR_REPOSITORY_URI}"
```

Posibles causas:

```text
Wrong AWS region
Wrong repository name
Wrong AWS account
Incorrect repository URI
```

---

### Troubleshooting — AccessDenied

Comprobar la identidad:

```bash
aws sts get-caller-identity \
  --profile aws-lab
```

La identidad debe disponer de permisos ECR suficientes para las operaciones del laboratorio.

No debemos solucionar problemas de permisos almacenando access keys dentro del repositorio.

---

### Troubleshooting — Immutable tag

Si:

```text
m3-v1
```

ya existe, ECR no permitirá reemplazarlo porque configuramos:

```text
IMMUTABLE
```

Para reiniciar este milestone conservando el mismo tag:

```bash
aws ecr batch-delete-image \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

Después volver a construir y publicar:

```text
m3-v1
```

Esto preserva la simplicidad del hands-on:

```text
M3
└── m3-v1
```

---


---

