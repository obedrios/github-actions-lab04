sidebar_position: 0
title: "Roadmap — Lab 04"
description: "Roadmap de implementación del Lab 04 para containerizar Docusaurus, publicar la imagen en Amazon ECR, desplegarla en ECS con Fargate y automatizar el flujo mediante GitHub Actions y OIDC."
tags:

- aws
- docker
- docusaurus
- amazon-ecr
- amazon-ecs
- fargate
- github-actions
- devops
- lab04

# Roadmap — Lab 04: Docusaurus con Amazon ECR, ECS y Fargate

## 1. Propósito

Construir desde cero una aplicación Docusaurus, containerizarla con Docker y NGINX, publicar su imagen en Amazon ECR y desplegarla como servicio administrado mediante Amazon ECS y AWS Fargate.

Posteriormente se automatizará el flujo completo utilizando GitHub Actions y autenticación federada mediante AWS OIDC.

El laboratorio seguirá una progresión incremental:

```
Docusaurus
    │
    ▼
Docker
    │
    ▼
Amazon ECR
    │
    ▼
Amazon ECS
    │
    ▼
AWS Fargate
    │
    ▼
Observability
    │
    ▼
GitHub Actions
    │
    ▼
Rollback
    │
    ▼
Teardown
```

Cada milestone deberá completarse y validarse antes de avanzar al siguiente.

## 2. Objetivo general

Al finalizar el laboratorio se deberá poder demostrar el siguiente flujo:

```
Git Repository
      │
      ▼
GitHub Actions
      │
      ▼
Docker Build
      │
      ▼
Amazon ECR
      │
      ▼
OCI Image
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
HTTP Request
```

También se deberá poder:

- identificar exactamente qué imagen fue desplegada;
- consultar logs del contenedor;
- diagnosticar fallos;
- desplegar nuevas revisiones;
- realizar rollback;
- eliminar la infraestructura creada al finalizar.

## 3. Principios del laboratorio

Durante todo el Lab 04 conservaremos los siguientes principios:

1. Cada milestone debe ser verificable de forma independiente.
2. Primero se implementará manualmente el flujo y posteriormente se automatizará.
3. No se utilizarán credenciales AWS permanentes dentro del repositorio.
4. Las imágenes deberán ser identificables mediante tag y digest.
5. Se documentarán los errores reales encontrados durante la ejecución.
6. Se introducirán fallos controlados para practicar troubleshooting.
7. Se conservará evidencia de los checkpoints importantes.
8. Los recursos AWS serán eliminados cuando dejen de ser necesarios.
9. El laboratorio utilizará inicialmente un solo ambiente para reducir complejidad y costos.
10. La automatización no sustituirá la comprensión del proceso manual.

## 4. Roadmap de milestones

| Milestone | Tema                    | Objetivo principal                                      | Estado      |
| --------- | ----------------------- | ------------------------------------------------------- | ----------- |
| **M1**    | Bootstrap de Docusaurus | Crear desde cero la aplicación base                     | Completado  |
| **M2**    | Docker + NGINX          | Containerizar y validar la aplicación localmente        | Completado  |
| **M3**    | Amazon ECR              | Publicar y validar la imagen OCI en un registry privado | Completado  |
| **M4**    | ECS + Fargate           | Ejecutar manualmente la aplicación en AWS               | Completado  |
| **M5**    | Observabilidad          | Incorporar logs, health y troubleshooting               | En Progreso |
| **M6**    | GitHub Actions + OIDC   | Automatizar build, push y deployment                    | Pendiente   |
| **M7**    | Rollback                | Simular un fallo y recuperar el servicio                | Pendiente   |
| **M8**    | Cierre y teardown       | Consolidar evidencia y eliminar recursos                | Pendiente   |

## 5. M1 — Bootstrap de Docusaurus

### Objetivo

Crear desde cero una aplicación Docusaurus completamente independiente de laboratorios anteriores.

### Actividades

- Crear el repositorio del Lab 04.
- Inicializar Docusaurus.
- Utilizar JavaScript y npm.
- Personalizar mínimamente el sitio.
- Ejecutar el servidor de desarrollo.
- Generar el build de producción.
- Publicar el código inicial en GitHub.

### Flujo

```
Source Code
    │
    ▼
Docusaurus
    │
    ├── npm run start
    │       │
    │       ▼
    │ localhost:3000
    │
    └── npm run build
            │
            ▼
          build/
```

### Validaciones

```
[ ] npm run start funciona
[ ] localhost:3000 responde
[ ] La aplicación identifica claramente al Lab 04
[ ] npm run build funciona
[ ] build/index.html existe
[ ] Código almacenado en GitHub
```

### Criterio de salida

> Docusaurus funciona localmente y puede generar correctamente su build de producción.

```
M1 STATUS: PASS
```

## 6. M2 — Containerización con Docker + NGINX

### Objetivo

Convertir la aplicación Docusaurus en una imagen Docker reproducible utilizando un build multi-stage.

### Arquitectura

```
Docusaurus Source
       │
       ▼
Node.js Builder
       │
       ├── npm ci
       └── npm run build
               │
               ▼
             build/
               │
               ▼
             NGINX
               │
               ▼
          Docker Image
               │
               ▼
          Docker Container
               │
               ▼
        localhost:8080
```

### Actividades

- Crear `.dockerignore`.
- Crear `Dockerfile`.
- Utilizar Node.js como builder.
- Utilizar NGINX como runtime.
- Crear `nginx.conf`.
- Construir la imagen.
- Ejecutar el contenedor.
- Realizar smoke tests HTTP.
- Inspeccionar logs.
- Comprobar que Node.js no existe en el runtime.

### Hallazgo relevante

Las rutas Docusaurus pueden estar representadas físicamente como:

```
/docs/example/
└── index.html
```

Por ello:

```
/docs/example
```

puede responder:

```
301 Moved Permanently
```

y redirigir hacia:

```
/docs/example/
```

que posteriormente responde:

```
200 OK
```

También se incorporó:

```
absolute_redirect off;
```

para evitar que NGINX pierda el puerto externo publicado por Docker en las redirecciones.

### Criterio de salida

> La imagen puede construirse y ejecutarse localmente, y Docusaurus funciona correctamente servido mediante NGINX.

```
M2 STATUS: PASS
```

## 7. M3 — Publicación de la imagen en Amazon ECR

### Objetivo

Publicar la imagen de Docusaurus en un repositorio privado de Amazon ECR y comprobar su identidad, formato OCI, seguridad y reproducibilidad.

### Arquitectura

```
Docker / BuildKit
       │
       ▼
OCI Image Manifest
       │
       ▼
Amazon ECR
       │
       ▼
lab04-docusaurus:m3-v1
       │
       ▼
Digest
```

### Actividades

- Verificar identidad AWS.
- Crear repositorio privado ECR.
- Configurar tags inmutables.
- Habilitar scanning.
- Autenticar Docker contra ECR.
- Trabajar con Docker Buildx.
- Estudiar OCI Image Manifest.
- Estudiar OCI Image Index.
- Construir una imagen single-platform.
- Publicar `m3-v1`.
- Registrar digest.
- Ejecutar vulnerability scan.
- Descargar nuevamente la imagen.
- Ejecutarla localmente.
- Realizar smoke test.

### OCI Image Manifest vs OCI Image Index

Durante M3 se introduce la diferencia entre:

```
OCI Image Manifest
```

y:

```
OCI Image Index
```

Un manifest representa una imagen concreta:

```
Image Manifest
    │
    ├── config
    ├── layer
    ├── layer
    └── layer
```

Un index puede agrupar múltiples manifests:

```
Image Index
    │
    ├── linux/amd64
    ├── linux/arm64
    └── attestations
```

Para el flujo principal del laboratorio se utilizará:

```
application/vnd.oci.image.manifest.v1+json
```

y se conservará únicamente:

```
m3-v1
```

como tag.

### Hallazgos relevantes

Durante el laboratorio aparecieron:

```
ScanNotFoundException
```

y posteriormente:

```
UnsupportedImageTypeException
```

El artefacto originalmente publicado era:

```
application/vnd.oci.image.index.v1+json
```

y no podía ser analizado directamente mediante el flujo de ECR Basic Scanning utilizado en el ejercicio.

La solución consiste en construir el artefacto final como:

```
single platform
+
provenance disabled
+
SBOM disabled
+
OCI Image Manifest
```

sin introducir un nuevo tag.

### Criterio de salida

> `lab04-docusaurus:m3-v1` existe en Amazon ECR como un OCI Image Manifest verificable mediante digest, puede analizarse, descargarse y ejecutarse correctamente.

```
M3 STATUS: PASS
```

## 8. M4 — Deployment manual en Amazon ECS + AWS Fargate

### Objetivo

Ejecutar por primera vez la aplicación dentro de AWS utilizando Amazon ECS y AWS Fargate.

### Arquitectura objetivo

```
Amazon ECR
      │
      ▼
lab04-docusaurus:m3-v1
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
Container
      │
      ▼
NGINX
      │
      ▼
Docusaurus
```

### Conceptos principales

- ECS Cluster.
- Task Definition.
- Task.
- Service.
- Fargate.
- Container definition.
- CPU.
- Memory.
- Port mappings.
- VPC.
- Subnet.
- Security Group.
- Public networking.
- IAM Task Execution Role.

### Actividades

- Crear un ECS Cluster.
- Crear IAM execution role.
- Crear Task Definition.
- Referenciar la imagen ECR.
- Configurar arquitectura compatible.
- Configurar CPU y memoria.
- Configurar puerto 80.
- Crear networking.
- Crear ECS Service.
- Ejecutar una Fargate Task.
- Acceder remotamente a Docusaurus.
- Confirmar que la imagen ejecutada corresponde a `m3-v1`.

### Criterio de salida

> Docusaurus se ejecuta correctamente como contenedor administrado mediante ECS/Fargate y puede accederse remotamente.

```
M4 STATUS: PASS
```

## 9. M5 — Observabilidad y troubleshooting

### Objetivo

Aprender a observar y diagnosticar el comportamiento del servicio desplegado.

### Arquitectura

```
Fargate Task
     │
     ├── Task State
     ├── ECS Events
     ├── Health
     └── Container Logs
                │
                ▼
        Amazon CloudWatch
```

### Actividades

- Habilitar CloudWatch Logs.
- Revisar logs de NGINX.
- Revisar ECS events.
- Inspeccionar estado de las tasks.
- Inspeccionar reason codes.
- Revisar stopped tasks.
- Introducir un fallo controlado.
- Diagnosticar el incidente.

Ejemplos de fallos:

```
Wrong container port
Invalid image
Incorrect architecture
Missing IAM permission
Incorrect security group
```

### Criterio de salida

> Un fallo controlado puede identificarse mediante ECS y CloudWatch y su causa puede determinarse sin reconstruir toda la infraestructura.

```
M5 STATUS: PASS
```

## 10. M6 — CI/CD con GitHub Actions + AWS OIDC

### Objetivo

Automatizar el flujo manual construido durante M1–M5.

### Arquitectura

```
git push
    │
    ▼
GitHub Actions
    │
    ▼
Build / Validation
    │
    ▼
Docker Build
    │
    ▼
AWS OIDC
    │
    ▼
Amazon ECR
    │
    ▼
New Image
    │
    ▼
ECS Task Definition
    │
    ▼
ECS Deployment
    │
    ▼
Service Stable
```

### Actividades

- Crear IAM Role para GitHub Actions.
- Configurar trust policy OIDC.
- Aplicar mínimo privilegio.
- Crear workflow.
- Ejecutar build de Docusaurus.
- Construir imagen Docker.
- Publicar imagen en ECR.
- Registrar nueva revisión de Task Definition.
- Actualizar ECS Service.
- Esperar estabilidad.
- Verificar deployment.

### Trazabilidad

La automatización deberá permitir relacionar:

```
Git Commit
    │
    ▼
Docker Image
    │
    ▼
Image Digest
    │
    ▼
Task Definition Revision
    │
    ▼
ECS Deployment
```

### Criterio de salida

> Un cambio aprobado en GitHub produce automáticamente una nueva imagen y actualiza el servicio ECS sin utilizar access keys AWS permanentes.

```
M6 STATUS: PASS
```

## 11. M7 — Fallo controlado y rollback

### Objetivo

Demostrar que un deployment defectuoso puede identificarse y recuperarse de forma controlada.

### Escenario

```
Known Good Version
        │
        ▼
New Deployment
        │
        ▼
Failure
        │
        ▼
Diagnosis
        │
        ▼
Rollback
        │
        ▼
Service Restored
```

### Actividades

- Identificar una versión estable.
- Introducir deliberadamente un cambio defectuoso.
- Realizar deployment.
- Observar el fallo.
- Revisar ECS Events.
- Revisar CloudWatch Logs.
- Identificar causa raíz.
- Recuperar la Task Definition estable.
- Verificar restauración del servicio.

### Evidencia

Registrar:

```
Symptom
→ Evidence
→ Root Cause
→ Corrective Action
→ Rollback
→ Validation
```

### Criterio de salida

> El servicio puede recuperarse de un deployment defectuoso utilizando una versión conocida como estable.

```
M7 STATUS: PASS
```

## 12. M8 — Cierre, evidencia y teardown

### Objetivo

Cerrar formalmente el laboratorio y eliminar recursos AWS innecesarios.

### Evidencia final

Conservar:

- repositorio GitHub;
- commits;
- Dockerfile;
- nginx.conf;
- GitHub Actions workflow;
- ECR repository URI;
- tags utilizados;
- image digests;
- ECS Task Definition revisions;
- ECS deployment evidence;
- CloudWatch logs relevantes;
- resultados del vulnerability scan;
- evidencia del rollback;
- incidentes encontrados;
- soluciones aplicadas.

### Consolidación documental

Los documentos:

```
M1
M2
M3
M4
M5
M6
M7
M8
```

se utilizarán para producir posteriormente:

```
Lab 04 — Complete Hands-on Lab
```

El documento final deberá eliminar redundancias y conservar principalmente:

```
Architecture
Implementation
Validation
Troubleshooting
Evidence
Lessons Learned
Teardown
```

### Teardown

Eliminar los recursos que ya no sean necesarios, incluyendo según la arquitectura final:

- ECS Service.
- ECS Tasks.
- ECS Cluster.
- Task Definitions cuando corresponda.
- ECR images.
- ECR repository.
- CloudWatch Log Groups opcionales.
- Security Groups específicos.
- Load Balancer si fue creado.
- Target Groups si fueron creados.
- IAM Roles exclusivos del laboratorio.

Revisar que no queden recursos generando cargos innecesarios.

### Criterio de salida

> Toda la evidencia del laboratorio está documentada y los recursos AWS que ya no son necesarios han sido eliminados.

```
M8 STATUS: PASS
```

## 13. Dependencias entre milestones

```
M1 — Docusaurus
 │
 ▼
M2 — Docker + NGINX
 │
 ▼
M3 — Amazon ECR
 │
 ▼
M4 — ECS + Fargate
 │
 ▼
M5 — Observability
 │
 ▼
M6 — GitHub Actions + OIDC
 │
 ▼
M7 — Failure + Rollback
 │
 ▼
M8 — Evidence + Teardown
```

Cada milestone construye sobre evidencia previamente validada.

## 14. Evolución arquitectónica

### M1

```
Docusaurus
```

### M2

```
Docusaurus
    │
    ▼
Docker + NGINX
```

M3

```
Docusaurus
    │
    ▼
Docker
    │
    ▼
Amazon ECR
```

M4

```
Docusaurus
    │
    ▼
Docker
    │
    ▼
Amazon ECR
    │
    ▼
ECS + Fargate
```

### M5

```
ECS + Fargate
      │
      ▼
CloudWatch
```

### M6

```
GitHub
   │
   ▼
GitHub Actions
   │
   ▼
OIDC
   │
   ▼
ECR
   │
   ▼
ECS/Fargate
```

### M7

```
Deployment
    │
    ▼
Failure
    │
    ▼
Diagnosis
    │
    ▼
Rollback
```

### M8

```
Evidence
   │
   ▼
Documentation
   │
   ▼
Teardown
```

## 15. Método de trabajo

Cada milestone seguirá un ciclo similar:

```
PLAN
 │
 ▼
Define objective
and exit criteria
 │
 ▼
DO
 │
 ▼
Implement
 │
 ▼
CHECK
 │
 ▼
Validate
Observe
Troubleshoot
 │
 ▼
ACT
 │
 ▼
Document findings
and refine next milestone
```

No se considerará terminado un milestone únicamente porque los comandos hayan ejecutado correctamente.

Debe existir evidencia verificable del comportamiento esperado.

## 16. Plantilla de cierre por milestone

Cada milestone deberá registrar:

```
Milestone:
M#

Status:
PASS / FAIL

Objective:
...

Environment:
...

Implementation:
...

Validation:
...

Evidence:
...

Issues found:
...

Root cause:
...

Resolution:
...

Lessons learned:
...

Next milestone:
...
```

## 17. Criterio final del Lab 04

El Lab 04 podrá considerarse completado cuando se haya demostrado:

```
[ ] Docusaurus creado desde cero
[ ] Build de producción funcionando
[ ] Docker multi-stage funcionando
[ ] NGINX sirviendo Docusaurus
[ ] Imagen reproducible
[ ] OCI Image Manifest comprendido
[ ] OCI Image Index comprendido
[ ] Imagen publicada en Amazon ECR
[ ] Tag y digest registrados
[ ] Vulnerability scan ejecutado
[ ] ECS Cluster funcionando
[ ] Task Definition creada
[ ] Fargate Task funcionando
[ ] ECS Service operativo
[ ] Aplicación accesible remotamente
[ ] CloudWatch Logs disponibles
[ ] Fallo controlado diagnosticado
[ ] GitHub Actions integrado
[ ] AWS OIDC utilizado
[ ] Deployment automático funcionando
[ ] Rollback ejecutado
[ ] Evidencia consolidada
[ ] Recursos AWS eliminados
```

Resultado final:

```
LAB 04 STATUS: PASS
```

## 18. Resultado esperado

Al terminar el laboratorio habremos recorrido una cadena completa de entrega de contenedores:

```
Source
  │
  ▼
Build
  │
  ▼
Container
  │
  ▼
Registry
  │
  ▼
Orchestrator
  │
  ▼
Runtime
  │
  ▼
Observability
  │
  ▼
Automation
  │
  ▼
Recovery
```

Esta experiencia servirá como base para los siguientes laboratorios de Kubernetes, donde varios de estos conceptos volverán a aparecer bajo un modelo de orquestación diferente.