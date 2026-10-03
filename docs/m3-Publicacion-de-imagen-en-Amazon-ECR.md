---
sidebar_position: 3
title: "M3 — Publicación de la imagen en Amazon ECR"
description: "Publicación manual de la imagen Docker de Docusaurus en Amazon ECR, utilizando autenticación AWS, tags inmutables, verificación mediante digest, análisis de vulnerabilidades y prueba de descarga."
tags:

- aws
- amazon-ecr
- docker
- containers
- docusaurus
- devops
- lab04
---



# M3 — Publicación de la imagen en Amazon ECR

## Objetivo

Publicar en **Amazon Elastic Container Registry (Amazon ECR)** la imagen Docker de Docusaurus creada y validada durante **M2**.

El objetivo es comprobar manualmente el flujo completo:

```
Local Docker Image
        │
        ▼
AWS Authentication
        │
        ▼
Amazon ECR Repository
        │
        ▼
Docker Tag
        │
        ▼
docker push
        │
        ▼
Versioned Image
        │
        ▼
Image Digest
```

En este milestone todavía **no utilizaremos Amazon ECS ni AWS Fargate**.

El criterio principal de salida será:

> **PASS:** la imagen `lab04-docusaurus` puede publicarse en un repositorio privado de Amazon ECR, verificarse mediante su tag y digest, descargarse nuevamente y ejecutarse correctamente de forma local.

## Alcance

M3 introduce:

- AWS CLI.
- Identidad AWS.
- Amazon ECR.
- Repositorios privados.
- Autenticación Docker contra ECR.
- Docker tags.
- Tags inmutables.
- Push de imágenes.
- Image digest.
- Vulnerability scanning.
- Pull desde ECR.
- Validación de la imagen recuperada.

El flujo de deployment todavía no incluirá:

```
Amazon ECS
AWS Fargate
Application Load Balancer
CloudWatch Logs
GitHub Actions
OIDC
CI/CD
```

Estos componentes aparecerán en milestones posteriores.

## 1. Estado inicial

Al finalizar M2 disponemos localmente de:

```
lab04-docusaurus:local
```

Podemos verificarlo con:

```
docker image ls lab04-docusaurus
```

Ejemplo:

```
REPOSITORY          TAG       IMAGE ID       SIZE
lab04-docusaurus    local     abc123...      ...
```

La arquitectura actual es:

```
Local Machine

Docusaurus Source
       │
       ▼
Docker Build
       │
       ▼
lab04-docusaurus:local
```

La imagen todavía existe únicamente en nuestra máquina.

## 2. Arquitectura de M3

Al completar M3 tendremos:

```
                    AWS
                     │
                     ▼
            ┌─────────────────┐
            │   Amazon ECR    │
            │                 │
            │ Private Registry│
            └────────┬────────┘
                     │
                     │ repository
                     ▼
            lab04-docusaurus
                     │
                     ▼
                  m3-v1
                     │
                     ▼
                  digest
                     ▲
                     │
                  docker push
                     │
                     │
              Local Machine
                     │
                     ▼
       lab04-docusaurus:local
```

ECR será únicamente el **registry**.

La aplicación todavía no estará ejecutándose en AWS.

## 3. Prerrequisitos

M2 debe estar completado.

Verificar la imagen local:

```
docker image ls lab04-docusaurus:local
```

Verificar Docker:

```
docker --version
```

Verificar AWS CLI:

```
aws --version
```

Comprobar que existe una sesión AWS válida:

```
aws sts get-caller-identity
```

Esperamos una respuesta similar a:

```
{
    "UserId": "...",
    "Account": "123456789012",
    "Arn": "..."
}
```

Esta operación nos permite verificar qué identidad AWS estamos utilizando antes de crear recursos.

## 4. Definir variables del laboratorio

Para simplificar los comandos utilizaremos variables de shell.

Definir primero la región AWS donde realizaremos el laboratorio.

Por ejemplo:

```
export AWS_REGION="us-west-2"
```

Si se utiliza otra región, modificarla antes de continuar.

Definir el nombre del repositorio:

```
export ECR_REPOSITORY="lab04-docusaurus"
```

Obtener automáticamente el Account ID:

```
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account \
  --output text)
```

Construir la URI del registry:

```
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
```

Construir la URI completa del repositorio:

```
export ECR_REPOSITORY_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}"
```

Definir el tag de esta versión:

```
export IMAGE_TAG="m3-v1"
```

Verificar:

```
echo "AWS_REGION=${AWS_REGION}"
echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
echo "ECR_REGISTRY=${ECR_REGISTRY}"
echo "ECR_REPOSITORY_URI=${ECR_REPOSITORY_URI}"
echo "IMAGE_TAG=${IMAGE_TAG}"
```

## 5. Convención de versionado

No utilizaremos únicamente:

```
latest
```

Para este milestone utilizaremos:

```
m3-v1
```

De esta manera podemos identificar exactamente qué imagen fue publicada.

Conceptualmente:

```
lab04-docusaurus
        │
        └── m3-v1
```

Posteriormente, cuando GitHub Actions automatice el proceso, podremos utilizar identificadores como:

```
Git commit SHA
```

por ejemplo:

```
a7f1c42
```

Esto permitirá relacionar:

```
Git Commit
    │
    ▼
Docker Image
    │
    ▼
ECR Digest
    │
    ▼
ECS Deployment
```

## 6. Crear el repositorio privado de Amazon ECR

Crear:

```
aws ecr create-repository \
  --repository-name "${ECR_REPOSITORY}" \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --region "${AWS_REGION}"
```

Esperamos una respuesta que incluya información similar a:

```
repositoryName
repositoryArn
repositoryUri
imageTagMutability
```

La propiedad:

```
IMMUTABLE
```

significa que, una vez utilizado un tag, no podremos reemplazar silenciosamente la imagen asociada a ese tag.

Por ejemplo:

```
m3-v1
   │
   ▼
Image A
```

no podrá convertirse posteriormente en:

```
m3-v1
   │
   ▼
Image B
```

Para publicar otra versión utilizaríamos:

```
m3-v2
```

o, posteriormente, el SHA correspondiente al commit.

## 7. Verificar el repositorio

Ejecutar:

```
aws ecr describe-repositories \
  --repository-names "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}"
```

Podemos obtener solamente la URI:

```
aws ecr describe-repositories \
  --repository-names "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}" \
  --query 'repositories[0].repositoryUri' \
  --output text
```

El resultado será similar a:

```
123456789012.dkr.ecr.us-west-2.amazonaws.com/lab04-docusaurus
```

## 8. Checkpoint 1 — Repositorio ECR

Verificar:

```
[ ] AWS CLI funciona
[ ] aws sts get-caller-identity funciona
[ ] Región AWS definida
[ ] Account ID obtenido
[ ] Repositorio lab04-docusaurus creado
[ ] Repositorio es privado
[ ] Tags configurados como IMMUTABLE
[ ] Image scanning habilitado para push
[ ] Repository URI obtenida
```

Resultado esperado:

```
Checkpoint 1: PASS
```

## 9. Autenticar Docker contra Amazon ECR

Docker necesita autenticarse contra nuestro registry privado.

Ejecutar:

```
aws ecr get-login-password \
  --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${ECR_REGISTRY}"
```

Resultado esperado:

```
Login Succeeded
```

Conceptualmente:

```
AWS CLI
   │
   │ temporary registry credential
   ▼
Docker
   │
   ▼
Amazon ECR
```

No estamos almacenando manualmente una contraseña ECR dentro del repositorio.

## 10. Checkpoint 2 — Autenticación

Verificar:

```
[ ] aws ecr get-login-password funciona
[ ] docker login termina correctamente
[ ] El registry corresponde a la región correcta
[ ] Login Succeeded
```

Resultado esperado:

```
Checkpoint 2: PASS
```

## 11. Verificar nuevamente la imagen local

Ejecutar:

```
docker image ls lab04-docusaurus:local
```

Antes de publicarla tenemos:

```
lab04-docusaurus:local
```

ECR necesita que la imagen tenga un tag con la URI completa del repositorio.

## 12. Etiquetar la imagen para Amazon ECR

Ejecutar:

```
docker tag \
  lab04-docusaurus:local \
  "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Ahora verificar:

```
docker image ls
```

Podremos observar dos referencias a la misma imagen:

```
lab04-docusaurus:local

123456789012.dkr.ecr.us-west-2.amazonaws.com/lab04-docusaurus:m3-v1
```

Conceptualmente:

```
                  Docker Image
                       │
           ┌───────────┴────────────┐
           │                        │
           ▼                        ▼
lab04-docusaurus:local      ECR URI:m3-v1
```

No hemos duplicado necesariamente el contenido de la imagen.

Hemos creado otra referencia hacia ella.

## 13. Publicar la imagen

Ejecutar:

```
docker push "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Docker comenzará a enviar las capas de la imagen.

La salida será similar conceptualmente a:

```
layer A: pushed
layer B: pushed
layer C: pushed
...
m3-v1: digest: sha256:...
```

El dato más importante será:

```
sha256:...
```

Este es el **digest** de la imagen.

## 14. Tag vs Digest

El tag proporciona un nombre amigable:

```
m3-v1
```

El digest representa la identidad criptográfica del contenido publicado:

```
sha256:abc123...
```

Conceptualmente:

```
lab04-docusaurus:m3-v1
            │
            ▼
sha256:abc123...
```

El digest será particularmente importante cuando queramos conocer exactamente qué imagen está ejecutando ECS.

## 15. Checkpoint 3 — Docker push

Verificar:

```
[ ] Imagen local etiquetada para ECR
[ ] docker push termina correctamente
[ ] Todas las capas fueron publicadas
[ ] Tag m3-v1 existe
[ ] Docker muestra un sha256 digest
```

Resultado:

```
Checkpoint 3: PASS
```

## 16. Verificar la imagen desde AWS CLI

Ejecutar:

```
aws ecr describe-images \
  --repository-name "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}"
```

Podemos obtener únicamente la información relevante:

```
aws ecr describe-images \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query 'imageDetails[0].[imageTags,imageDigest,imagePushedAt,imageSizeInBytes]' \
  --output table
```

Debemos encontrar:

```
m3-v1
sha256:...
push timestamp
image size
```

## 17. Capturar el digest

Podemos almacenar el digest:

```
export IMAGE_DIGEST=$(aws ecr describe-images \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query 'imageDetails[0].imageDigest' \
  --output text)
```

Verificar:

```
echo "${IMAGE_DIGEST}"
```

Resultado esperado:

```
sha256:...
```

Ahora tenemos tres identificadores importantes:

```
Repository
lab04-docusaurus

Tag
m3-v1

Digest
sha256:...
```

## 18. Identidad de la imagen

Podemos representar la imagen mediante tag:

```
<ECR_REPOSITORY_URI>:m3-v1
```

o mediante digest:

```
<ECR_REPOSITORY_URI>@sha256:...
```

Conceptualmente:

```
Human-friendly reference

lab04-docusaurus:m3-v1
          │
          ▼
Immutable content identity

sha256:...
```

## 19. Verificar el vulnerability scan

Como el repositorio fue configurado con:

```
scanOnPush=true
```

Amazon ECR iniciará el análisis correspondiente después del push.

Podemos consultar el estado:

```
aws ecr describe-image-scan-findings \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

Si el análisis todavía está ejecutándose, puede ser necesario volver a consultar posteriormente.

Cuando finalice podremos revisar:

```
scanStatus
findingSeverityCounts
imageDigest
```

Para una vista compacta:

```
aws ecr describe-image-scan-findings \
  --repository-name "${ECR_REPOSITORY}" \
  --image-id imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query '[imageScanStatus.status,imageScanFindings.findingSeverityCounts]' \
  --output table
```

La existencia de findings no significa automáticamente que la imagen no pueda ejecutarse.

La información debe utilizarse para conocer y evaluar vulnerabilidades presentes en las capas de la imagen.

## 20. Checkpoint 4 — Verificación ECR

Verificar:

```
[ ] describe-images encuentra m3-v1
[ ] La imagen tiene digest sha256
[ ] imagePushedAt está disponible
[ ] El digest fue registrado
[ ] El estado del vulnerability scan puede consultarse
```

Resultado esperado:

```
Checkpoint 4: PASS
```

## 21. Verificar la imagen desde AWS Console

También podemos revisar:

```
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

Dentro del repositorio debemos observar la imagen:

```
Tag:
m3-v1

Digest:
sha256:...

Pushed at:
...

Size:
...
```

Esta validación visual puede conservarse como evidencia del milestone.

## 22. Prueba de inmutabilidad

Nuestro repositorio fue creado utilizando:

```
IMMUTABLE
```

Podemos comprobar conceptualmente qué protege esta configuración.

El tag:

```
m3-v1
```

ya identifica una imagen.

Si posteriormente modificáramos el contenido, reconstruyéramos una imagen diferente e intentáramos publicar nuevamente:

```
m3-v1
```

ECR debe impedir reemplazar el tag existente.

No es necesario provocar este error para cerrar M3.

La regla operacional será:

```
Nueva imagen
    │
    ▼
Nuevo tag
```

Por ejemplo:

```
m3-v1
m3-v2
m3-v3
```

Posteriormente:

```
<git-sha>
```

## 23. Prueba importante — recuperar la imagen desde ECR

Hasta aquí comprobamos:

```
Local
  │
  ▼
ECR
```

Ahora probaremos también:

```
ECR
 │
 ▼
Local
```

Esto nos permite demostrar que la imagen almacenada en ECR puede recuperarse.

Primero eliminar únicamente la referencia ECR local:

```
docker image rm "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

La referencia original:

```
lab04-docusaurus:local
```

puede permanecer.

## 24. Descargar la imagen desde ECR

Ejecutar:

```
docker pull "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Esperamos que Docker descargue o reutilice las capas correspondientes y muestre el digest.

Verificar:

```
docker image ls
```

Ahora deberá aparecer nuevamente:

```
${ECR_REPOSITORY_URI}:m3-v1
```

## 25. Ejecutar directamente la imagen proveniente de ECR

Ejecutar:

```
docker run \
  --name lab04-ecr-test \
  -d \
  -p 8080:80 \
  "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Verificar:

```
docker ps
```

## 26. Smoke test

Comprobar:

```
curl -I http://localhost:8080
```

Resultado esperado:

```
HTTP/1.1 200 OK
Server: nginx
```

También podemos reutilizar la prueba de rutas aprendida durante M2:

```
curl -I -L \
  http://localhost:8080/docs/m1-docusaurus-bootstrap
```

El flujo puede ser:

```
301
 ↓
200
```

Esto es válido según lo documentado en M2.

## 27. Checkpoint 5 — Registry round trip

Esta prueba completa un ciclo muy importante:

```
Local Image
     │
     ▼
docker push
     │
     ▼
Amazon ECR
     │
     ▼
docker pull
     │
     ▼
Local Container
     │
     ▼
HTTP 200
```

Verificar:

```
[ ] Imagen descargada desde ECR
[ ] docker run funciona utilizando la URI ECR
[ ] localhost:8080 responde HTTP 200
[ ] Docusaurus carga correctamente
[ ] Las rutas funcionan
```

Resultado:

```
Checkpoint 5: PASS
```

## 28. Limpiar el contenedor de prueba

Ejecutar:

```
docker stop lab04-ecr-test
```

Después:

```
docker rm lab04-ecr-test
```

El repositorio ECR y la imagen publicada **no se eliminarán todavía**, porque serán utilizados por M4.

## 29. Troubleshooting — No basic auth credentials

Síntoma posible:

```
no basic auth credentials
```

Revisar primero la autenticación:

```
aws ecr get-login-password \
  --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${ECR_REGISTRY}"
```

También verificar que la región de:

```
get-login-password
```

corresponda con la región donde existe el repositorio ECR.

Conceptualmente:

```
ECR repository region
        =
docker login region
```

## 30. Troubleshooting — Repository does not exist

Si `docker push` indica que el repositorio no existe, verificar:

```
aws ecr describe-repositories \
  --region "${AWS_REGION}"
```

También revisar:

```
echo "${ECR_REPOSITORY_URI}"
```

Las causas comunes incluyen:

```
Wrong AWS Region
Wrong repository name
Wrong AWS account
Incorrect URI
```

## 31. Troubleshooting — AccessDenied

Si AWS responde con:

```
AccessDenied
```

verificar primero qué identidad estamos utilizando:

```
aws sts get-caller-identity
```

La identidad debe tener permisos suficientes para las operaciones de ECR utilizadas durante el laboratorio.

No debemos resolver este problema creando credenciales dentro del repositorio.

## 32. Troubleshooting — Immutable tag

Si posteriormente intentamos publicar una imagen diferente utilizando un tag ya existente como:

```
m3-v1
```

ECR puede rechazar la operación porque configuramos:

```
IMMUTABLE
```

La solución es crear una nueva versión:

```
export IMAGE_TAG="m3-v2"
```

Etiquetar:

```
docker tag \
  lab04-docusaurus:local \
  "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Y publicar:

```
docker push "${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Esto es un comportamiento deseado, no un defecto.

## 33. Revisar arquitectura de la imagen

Antes de utilizar la imagen posteriormente en Fargate podemos registrar su arquitectura:

```
docker image inspect \
  lab04-docusaurus:local \
  --format '{{.Os}}/{{.Architecture}}'
```

Ejemplo:

```
linux/amd64
```

Conservaremos este dato para M4, ya que la arquitectura configurada para la tarea ECS debe ser compatible con la imagen que ejecutaremos.

## 34. Evidencia del milestone

Registrar:

```
Milestone:
M3 — Publicación de la imagen en Amazon ECR

Status:
PASS / FAIL

AWS:
- Region:
- Account ID:
- ECR Repository:
- Repository URI:

Image:
- Local image: lab04-docusaurus:local
- ECR tag: m3-v1
- Digest: sha256:...
- Architecture:
- Size:

Repository configuration:
- Visibility: Private
- Tag mutability: IMMUTABLE
- Scan on push: Enabled

Validation:
- aws sts get-caller-identity:
- docker login:
- docker push:
- describe-images:
- vulnerability scan:
- docker pull:
- docker run:
- HTTP smoke test:

Evidence:
- ECR console screenshot:
- docker push output:
- image digest:
- describe-images:
- curl HTTP 200:

Issues found:
- Ninguno / descripción

Resolution:
- N/A / descripción
```

## 35. Checklist final de M3

```
M3 — Publicación de la imagen en Amazon ECR

[ ] M2 está completado
[ ] Imagen lab04-docusaurus:local existe
[ ] AWS CLI funciona
[ ] Identidad AWS verificada
[ ] Región AWS definida
[ ] Amazon ECR repository creado
[ ] Repository es privado
[ ] Tag mutability configurado como IMMUTABLE
[ ] Scan on push configurado
[ ] Docker autenticado contra ECR
[ ] Imagen etiquetada como m3-v1
[ ] docker push completado
[ ] Imagen visible en Amazon ECR
[ ] Digest sha256 registrado
[ ] describe-images encuentra la imagen
[ ] Vulnerability scan consultado
[ ] Imagen descargada nuevamente desde ECR
[ ] Imagen ECR ejecutada localmente
[ ] GET / responde HTTP 200
[ ] Navegación Docusaurus funciona
[ ] Arquitectura de la imagen registrada
```

Si todas las verificaciones son correctas:

```
M3 STATUS: PASS
```

## 36. Qué demostramos en M3

M1 demostró:

```
Source
  │
  ▼
Docusaurus Build
```

M2 extendió el flujo:

```
Source
  │
  ▼
Docker Image
  │
  ▼
Local Container
```

M3 incorpora un registry remoto:

```
Source
  │
  ▼
Docker Image
  │
  ▼
Amazon ECR
  │
  ▼
Versioned Image
  │
  ▼
Digest
```

Y, mediante la prueba de descarga:

```
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

Con esto demostramos que Amazon ECR almacena correctamente un artefacto que ya habíamos validado localmente.

## 37. Separación conceptual importante

Al terminar M3 tendremos:

```
Image published
```

pero todavía no:

```
Application deployed
```

Es decir:

```
Amazon ECR
     │
     ▼
Stores images
```

no equivale a:

```
Application running
```

Esta distinción será fundamental durante el siguiente milestone.

## 38. Conservación del recurso para M4

Normalmente nuestros laboratorios terminan eliminando los recursos creados.

Sin embargo, **no eliminaremos todavía el repositorio ECR**, porque será utilizado directamente por:

```
M4 — Deployment manual en Amazon ECS + AWS Fargate
```

M4 utilizará:

```
ECR Repository
      │
      ▼
lab04-docusaurus:m3-v1
      │
      ▼
ECS Task Definition
      │
      ▼
Fargate Task
```

El teardown definitivo se realizará durante M8.

## 39. Limpieza opcional

Si se decide detener completamente el laboratorio antes de continuar con M4, el repositorio puede eliminarse.

**Advertencia:** eliminar un repositorio ECR elimina también sus imágenes cuando se utiliza eliminación forzada.

Comando:

```
aws ecr delete-repository \
  --repository-name "${ECR_REPOSITORY}" \
  --force \
  --region "${AWS_REGION}"
```

No ejecutar este comando si se continuará inmediatamente con M4.

## 40. Commit del milestone

La creación del repositorio ECR no modifica necesariamente el código fuente.

Sin embargo, después de agregar esta documentación podemos registrar el milestone:

```
git status
```

Después:

```
git add .
```

Commit sugerido:

```
git commit -m "docs: add Amazon ECR milestone"
```

Publicar:

```
git push
```

## 41. Preparación para M4

El siguiente milestone será:

```
M4 — Deployment manual en Amazon ECS + AWS Fargate
```

Partiremos de:

```
Amazon ECR
    │
    ▼
lab04-docusaurus:m3-v1
```

y construiremos:

```
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

Por primera vez tendremos nuestra aplicación ejecutándose dentro de AWS.

Todavía realizaremos este deployment **manualmente**.

GitHub Actions y OIDC aparecerán posteriormente, una vez que hayamos demostrado que:

```
Docker
  +
ECR
  +
ECS
  +
Fargate
```

funcionan correctamente por sí mismos.

## Criterio de salida

M3 puede considerarse cerrado cuando:

> La imagen Docker de Docusaurus puede autenticarse, etiquetarse y publicarse manualmente en un repositorio privado Amazon ECR; la imagen dispone de un tag versionado y un digest verificable, puede descargarse nuevamente desde ECR y ejecutarse localmente con un smoke test HTTP satisfactorio.

```
M3 STATUS: PASS
```