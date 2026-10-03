---
sidebar_position: 1
title: "M1 — Bootstrap de Docusaurus"
description: "Creación desde cero del proyecto Docusaurus para el Lab 04, validación local y generación del build de producción."
tags:
  - docusaurus
  - nodejs
  - npm
  - devops
  - lab04
---



# M1 - Bootstrap de Docusaurus

## Objetivo

Crear desde cero el proyecto base de Docusaurus para el **Lab 04 — Amazon ECR + ECS/Fargate**, validarlo localmente y generar correctamente su build de producción.

En este milestone todavía no se utilizarán Docker ni recursos de AWS.

El criterio principal de salida es:

> **PASS:** el sitio Docusaurus inicia correctamente en local, puede abrirse en `http://localhost:3000` y genera correctamente su build de producción.

## Alcance

Este milestone incluye:

- Crear un nuevo repositorio para el Lab 04.
- Inicializar Docusaurus desde cero.
- Utilizar JavaScript y npm.
- Ejecutar el sitio en modo desarrollo.
- Personalizar mínimamente el sitio para identificar el Lab 04.
- Generar el build de producción.
- Realizar el commit inicial.

Este milestone no incluye:

- Docker.
- NGINX.
- Amazon ECR.
- Amazon ECS.
- AWS Fargate.
- GitHub Actions.
- IAM u OIDC.

## Arquitectura de M1

```
Source Code
    │
    ▼
Docusaurus
    │
    ├── Development
    │      │
    │      ▼
    │  npm run start
    │      │
    │      ▼
    │ localhost:3000
    │
    └── Production
           │
           ▼
       npm run build
           │
           ▼
         build/
```

## 1. Crear el repositorio

Crear un nuevo repositorio llamado:

```
github-actions-lab04
```

Clonarlo localmente:

```
git clone <URL_DEL_REPOSITORIO>
cd github-actions-lab04
```

Verificar el estado:

```
git status
```

## 2. Verificar Node.js y npm

Ejecutar:

```
node --version
npm --version
```

Se utilizará Node.js 20 o superior.

Para mantener consistencia con los laboratorios anteriores puede utilizarse Node.js 22.

Ejemplo:

```
Node.js 22.x
npm
```

## 3. Crear Docusaurus

Desde la raíz del repositorio ejecutar:

```bash
# If wanted to create in a existing folder 
npx create-docusaurus@latest . classic

# Otherwise
npx create-docusaurus@latest github-actions-lab04 classic --typescript
cd github-actions-lab04
npm install
npm run start
# Navegar a http://localhost:3000
```



Al finalizar, el proyecto tendrá una estructura similar a:

```
github-actions-lab04/
├── blog/
├── docs/
├── src/
│   ├── components/
│   ├── css/
│   └── pages/
├── static/
├── docusaurus.config.js
├── package.json
├── package-lock.json
├── sidebars.js
└── README.md
```

## 4. Ejecutar Docusaurus en desarrollo

Ejecutar:

```
npm run start
```

Docusaurus deberá iniciar el servidor local.

Abrir:

```
http://localhost:3000
```

### Checkpoint 1

Verificar:

```
[ ] npm run start termina sin errores
[ ] http://localhost:3000 responde
[ ] La página inicial se muestra correctamente
[ ] La documentación puede abrirse
```

Resultado esperado:

```
Checkpoint 1: PASS
```

## 5. Personalizar el sitio para el Lab 04

Modificar las propiedades existentes en:

```
docusaurus.config.js
```

Utilizar valores similares a:

```
const config = {
  title: 'Cloud & DevOps Hands-on Labs',
  tagline: 'Lab 04 — Amazon ECR + ECS/Fargate',

  // resto de la configuración...
};
```

No es necesario reemplazar el archivo completo.

Guardar los cambios y verificar que el sitio los refleje correctamente.

## 6. Personalizar la página de introducción

Modificar:

```
docs/intro.md
```

Ejemplo:

```
---
sidebar_position: 1
---

# Lab 04 — Containers on AWS

Este sitio Docusaurus forma parte del laboratorio:

**Amazon ECR + Amazon ECS + AWS Fargate**

## Objetivo

Construir, publicar y desplegar esta aplicación como una imagen
Docker utilizando servicios administrados de AWS.
```

Esta página servirá posteriormente como evidencia visual de que el contenedor desplegado corresponde al Lab 04.

## 7. Generar el build de producción

Ejecutar:

```
npm run build
```

Si el proceso termina correctamente, Docusaurus generará:

```
build/
```

Revisar su contenido:

```
ls build
```

Deberán aparecer archivos y directorios similares a:

```
index.html
assets/
docs/
blog/
```

### Checkpoint 2

Verificar:

```
[ ] npm run build termina correctamente
[ ] El directorio build/ existe
[ ] build/index.html existe
```

Resultado esperado:

```
Checkpoint 2: PASS
```

## 8. Revisar el estado del repositorio

Ejecutar:

```
git status
```

Agregar los archivos:

```
git add .
```

Crear el commit inicial:

```
git commit -m "feat: bootstrap Docusaurus for lab04"
```

Publicar los cambios:

```
git push
```

## 9. Checklist final de M1

```
M1 — Bootstrap Docusaurus

[ ] Repositorio github-actions-lab04 creado
[ ] Node.js >= 20 disponible
[ ] Docusaurus creado desde cero
[ ] npm utilizado como package manager
[ ] JavaScript utilizado como lenguaje
[ ] npm run start funciona
[ ] localhost:3000 es accesible
[ ] El sitio identifica claramente al Lab 04
[ ] docs/intro.md fue personalizado
[ ] npm run build funciona
[ ] build/ fue generado correctamente
[ ] build/index.html existe
[ ] Commit inicial creado
[ ] Código publicado en GitHub
```

Si todas las validaciones son correctas:

```
M1 STATUS: PASS
```

## 10. Evidencia sugerida

Registrar los siguientes datos:

```
Milestone: M1 — Bootstrap Docusaurus

Status:
PASS / FAIL

Environment:
- Node:
- npm:
- Docusaurus:

Validation:
- npm run start:
- npm run build:

Evidence:
- Repository:
- Commit:
- Screenshot localhost:3000:

Issues found:
- Ninguno / descripción

Resolution:
- N/A / descripción
```

## 11. Qué demostramos en M1

Al finalizar este milestone se habrá comprobado el siguiente flujo:

```
Docusaurus Source
      │
      ├── npm run start
      │        │
      │        ▼
      │  Development Server
      │
      └── npm run build
               │
               ▼
             build/
```

El directorio:

```
build/
```

será el artefacto principal utilizado en el siguiente milestone.

## 12. Preparación para M2

El siguiente milestone será:

```
M2 — Containerización con Docker + NGINX
```

El flujo esperado será:

```
Docusaurus Source
      │
      ▼
Node Build Stage
      │
      ▼
npm run build
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
docker run
```

El objetivo de M2 será demostrar que el sitio Docusaurus puede ejecutarse correctamente dentro de una imagen Docker reproducible.

## Criterio de salida

El milestone puede considerarse cerrado cuando:

> El proyecto Docusaurus fue creado desde cero, funciona correctamente mediante `npm run start`, genera sin errores su build de producción y el código correspondiente fue almacenado en GitHub.

```
M1 STATUS: PASS
```