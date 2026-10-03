---
sidebar_position: 2
title: "M2 — Containerización de Docusaurus con Docker + NGINX"
description: "Containerización local de Docusaurus mediante un Dockerfile multi-stage y NGINX, incluyendo validación de rutas, smoke tests y troubleshooting de redirecciones HTTP 301."
tags:
  - docusaurus
  - docker
  - nginx
  - containers
  - devops
  - lab04
---



# M2 — Containerización de Docusaurus con Docker + NGINX



## Objetivo

Containerizar el sitio Docusaurus creado en **M1** utilizando un Dockerfile multi-stage.

El proceso utilizará:

- **Node.js** durante la etapa de construcción.
- `npm ci` para instalar las dependencias.
- `npm run build` para generar el sitio estático.
- **NGINX** como servidor web de producción.
- Docker para construir y ejecutar la imagen localmente.

En este milestone todavía no se utilizarán recursos de AWS.

El criterio principal de salida es:

> **PASS:** la imagen Docker se construye correctamente y el sitio Docusaurus puede navegarse desde `http://localhost:8080`, servido por NGINX dentro del contenedor.

## Alcance

Este milestone incluye:

- Crear un `Dockerfile`.
- Utilizar un build multi-stage.
- Crear `.dockerignore`.
- Configurar NGINX para servir Docusaurus.
- Construir la imagen Docker.
- Ejecutar el contenedor localmente.
- Validar la navegación del sitio.
- Validar rutas con y sin trailing slash.
- Inspeccionar redirecciones HTTP.
- Inspeccionar el contenedor.
- Detener y eliminar el contenedor.
- Registrar evidencia y troubleshooting real del milestone.

Este milestone no incluye:

- Amazon ECR.
- Amazon ECS.
- AWS Fargate.
- IAM.
- GitHub Actions.
- OIDC.
- CloudWatch.
- Deployment en AWS.

## Arquitectura de M2

```
Docusaurus Source
       │
       ▼
┌───────────────────────┐
│ Stage 1 — Builder     │
│                       │
│ Node.js 22            │
│ npm ci                │
│ npm run build         │
└───────────┬───────────┘
            │
            │ /app/build
            ▼
┌───────────────────────┐
│ Stage 2 — Runtime     │
│                       │
│ NGINX                 │
│ static files only     │
└───────────┬───────────┘
            │
            │ port 80
            ▼
       Docker Image
            │
            ▼
      Docker Container
            │
       localhost:8080
            │
            ▼
          Browser
```

Docusaurus genera durante su build archivos HTML, JavaScript, CSS y otros recursos estáticos dentro del directorio `build/`.

NGINX será responsable únicamente de servir esos archivos.

## 1. Prerrequisitos

M1 debe estar completado.

Verificar que estamos en el repositorio:

```
cd github-actions-lab04
```

Comprobar el estado:

```
git status
```

Verificar Docker:

```
docker --version
```

También podemos verificar que Docker Engine esté disponible:

```
docker info
```

El proyecto debe seguir construyéndose correctamente:

```
npm run build
```

Resultado esperado:

```
build/
```

## 2. Flujo que queremos containerizar

Antes de crear Docker, conviene recordar qué sucede actualmente:

```
Docusaurus source
       │
       ▼
npm run build
       │
       ▼
    build/
       │
       ├── index.html
       ├── assets/
       ├── docs/
       └── ...
```

Docusaurus termina su responsabilidad al producir estos archivos estáticos.

Nuestro contenedor agregará la siguiente pieza:

```
build/
   │
   ▼
NGINX
   │
   ▼
HTTP
```

## 3. Crear `.dockerignore`

Crear en la raíz:

```
.dockerignore
```

Agregar:

```
node_modules
build
.git
.gitignore
.github
npm-debug.log*
README.md
```

No se excluyen los archivos fuente de documentación porque forman parte del proyecto Docusaurus y deben estar disponibles durante:

```
npm run build
```

El directorio local `build/` sí se excluye deliberadamente porque el build será generado nuevamente dentro del contenedor.

Es decir:

```
Local build/
     X
     │
     │ no se copia
     ▼

Docker Builder
     │
     ├── npm ci
     └── npm run build
             │
             ▼
          /app/build
```

Esto mejora la reproducibilidad: Docker no depende del build previamente generado en nuestra máquina.

## 4. Crear configuración de NGINX

Crear:

```
nginx.conf
```

en la raíz del proyecto.

Contenido:

```
server {
    listen 80;
    server_name _;

    absolute_redirect off;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ $uri.html =404;
    }
}
```

## 5. Entender la configuración de NGINX

La configuración establece como raíz:

```
/usr/share/nginx/html
```

que es donde copiaremos el build generado por Docusaurus.

La instrucción:

```
try_files $uri $uri/ $uri.html =404;
```

indica a NGINX que intente resolver:

1. El recurso solicitado directamente.
2. Un directorio correspondiente a la ruta.
3. Un archivo HTML equivalente.
4. Finalmente, responder `404`.

Por ejemplo:

```
/docs/m1-docusaurus-bootstrap/
```

puede resolverse físicamente como:

```
/usr/share/nginx/html/
└── docs/
    └── m1-docusaurus-bootstrap/
        └── index.html
```

Esto significa que ciertas rutas Docusaurus representan realmente directorios que contienen un `index.html`.

## 6. Por qué usamos `absolute_redirect off`

La línea:

```
absolute_redirect off;
```

es importante cuando ejecutamos NGINX dentro de Docker con un puerto publicado diferente.

Nuestro contenedor escucha internamente en:

```
80
```

pero Docker expone ese puerto como:

```
8080
```

mediante:

```
-p 8080:80
```

La relación es:

```
Host                    Container

localhost:8080  ──────► 80
```

Sin `absolute_redirect off`, si NGINX necesita agregar un trailing slash puede generar una redirección absoluta como:

```
Location: http://localhost/docs/m1-docusaurus-bootstrap/
```

perdiendo el puerto externo:

```
8080
```

Con:

```
absolute_redirect off;
```

esperamos una redirección relativa:

```
Location: /docs/m1-docusaurus-bootstrap/
```

El navegador o cliente conserva entonces:

```
localhost:8080
```

## 7. Crear el Dockerfile

Crear en la raíz:

```
Dockerfile
```

Contenido:

```
# syntax=docker/dockerfile:1

# ---------------------------------------------------------
# Stage 1 — Build Docusaurus
# ---------------------------------------------------------

FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY . .

RUN npm run build


# ---------------------------------------------------------
# Stage 2 — Serve static site with NGINX
# ---------------------------------------------------------

FROM nginx:stable-alpine AS runtime

COPY nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /app/build /usr/share/nginx/html

EXPOSE 80
```

## 8. Entender el Dockerfile

### Stage 1 — Builder

```
FROM node:22-alpine AS builder
```

Utilizamos Node.js únicamente para construir Docusaurus.

```
WORKDIR /app
```

Define:

```
/app
```

como directorio de trabajo.

Primero copiamos:

```
COPY package*.json ./
```

Después:

```
RUN npm ci
```

Esto permite aprovechar mejor el sistema de capas y caché de Docker.

Mientras `package.json` y `package-lock.json` no cambien, Docker puede reutilizar la capa correspondiente a las dependencias.

Después copiamos el código:

```
COPY . .
```

Y finalmente:

```
RUN npm run build
```

Generando:

```
/app/build/
```

### 9. Stage 2 — Runtime

La segunda etapa comienza con:

```
FROM nginx:stable-alpine AS runtime
```

La imagen final ya no contiene:

```
Node.js
npm
node_modules
source code utilizado para compilar
herramientas del builder
```

Solamente contiene lo necesario para ejecutar el sitio:

```
NGINX
+
Docusaurus static files
```

Esta separación es la finalidad principal de un build multi-stage.

## 10. Copiar configuración de NGINX

La instrucción:

```
COPY nginx.conf /etc/nginx/conf.d/default.conf
```

reemplaza la configuración por defecto utilizada para servir nuestro sitio.

## 11. Copiar el artefacto entre stages

La línea:

```
COPY --from=builder /app/build /usr/share/nginx/html
```

es una de las instrucciones fundamentales de este milestone.

Conceptualmente:

```
Builder
/app/build/
      │
      │ COPY --from=builder
      ▼
Runtime
/usr/share/nginx/html/
```

Estamos promoviendo únicamente el **artefacto generado**, no todo el entorno de construcción.

## 12. Puerto del contenedor

El Dockerfile declara:

```
EXPOSE 80
```

NGINX escucha internamente en:

```
80
```

Posteriormente mapearemos ese puerto a:

```
localhost:8080
```

La relación será:

```
Host                 Container

localhost:8080  ───►  port 80
```

## 13. Construir la imagen Docker

Desde la raíz del proyecto ejecutar:

```
docker build -t lab04-docusaurus:local .
```

Docker ejecutará aproximadamente:

```
Dockerfile
    │
    ├── Node builder
    │     │
    │     ├── npm ci
    │     └── npm run build
    │
    └── NGINX runtime
          │
          └── copy build/
```

El proceso debe finalizar correctamente.

## 14. Checkpoint 1 — Docker build

Verificar:

```
[ ] Docker procesa correctamente el Dockerfile
[ ] npm ci termina correctamente
[ ] npm run build termina correctamente
[ ] Stage runtime se genera correctamente
[ ] La imagen lab04-docusaurus:local existe
```

Resultado esperado:

```
Checkpoint 1: PASS
```

## 15. Verificar la imagen

Ejecutar:

```
docker image ls
```

También:

```
docker image inspect lab04-docusaurus:local
```

Consultar específicamente su tamaño:

```
docker image ls lab04-docusaurus:local
```

Registrar como evidencia:

```
Repository:
lab04-docusaurus

Tag:
local

Image ID:
...

Size:
...
```

## 16. Ejecutar el contenedor

Ejecutar:

```
docker run \
  --name lab04-docusaurus \
  -d \
  -p 8080:80 \
  lab04-docusaurus:local
```

La relación de puertos será:

```
localhost:8080
       │
       ▼
Docker Host
       │
       ▼
container:80
       │
       ▼
NGINX
```

## 17. Verificar el contenedor

Ejecutar:

```
docker ps
```

Deberá aparecer:

```
lab04-docusaurus
```

con un mapeo similar a:

```
0.0.0.0:8080->80/tcp
```

## 18. Abrir Docusaurus

Abrir en el navegador:

```
http://localhost:8080
```

Debemos ver el sitio creado durante M1.

Verificar especialmente que aparezcan elementos que identifiquen claramente el Lab 04.

Navegar también hacia una página de documentación, por ejemplo:

```
/docs/m1-docusaurus-bootstrap/
```

## 19. Checkpoint 2 — Ejecución local

Verificar:

```
[ ] docker run termina correctamente
[ ] docker ps muestra el contenedor
[ ] localhost:8080 responde
[ ] La página principal carga correctamente
[ ] CSS y JavaScript cargan correctamente
[ ] Una página de documentación es accesible
[ ] La navegación entre páginas funciona
[ ] Las imágenes y otros assets cargan correctamente
```

Resultado esperado:

```
Checkpoint 2: PASS
```

## 20. Verificar mediante `curl`

Primero verificar la raíz:

```
curl -I http://localhost:8080
```

Resultado esperado:

```
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/html
```

Después probar una ruta Docusaurus:

```
curl -I http://localhost:8080/docs/m1-docusaurus-bootstrap
```

Dependiendo de cómo haya sido generado el sitio, una respuesta válida puede ser:

```
HTTP/1.1 301 Moved Permanently
```

con:

```
Location: /docs/m1-docusaurus-bootstrap/
```

Esto no representa un error.

Indica que NGINX está canonicalizando una ruta que corresponde a un directorio.

## 21. Validar la URL canónica

Ejecutar:

```
curl -I http://localhost:8080/docs/m1-docusaurus-bootstrap/
```

Esperamos:

```
HTTP/1.1 200 OK
```

Conceptualmente:

```
/docs/m1-docusaurus-bootstrap
            │
            ▼
301 Moved Permanently
            │
            ▼
/docs/m1-docusaurus-bootstrap/
            │
            ▼
200 OK
```

## 22. Seguir automáticamente la redirección

Podemos pedir a `curl` que siga redirecciones:

```
curl -I -L http://localhost:8080/docs/m1-docusaurus-bootstrap
```

El resultado deberá mostrar conceptualmente:

```
301 Moved Permanently
        │
        ▼
200 OK
```

Esto demuestra que:

```
Route without trailing slash
        │
        ▼
Canonical redirect
        │
        ▼
Valid Docusaurus page
```

## 23. Checkpoint 3 — Smoke test

El smoke test debe considerar correctamente el comportamiento de URLs canónicas.

Verificar:

```
[ ] GET / responde HTTP 200
[ ] Una ruta Docusaurus responde directamente 200
    o realiza una redirección canónica válida
[ ] Si existe redirección, Location conserva correctamente host y puerto mediante URL relativa
[ ] La URL canónica responde HTTP 200
[ ] La respuesta es servida por NGINX
```

Resultado:

```
Checkpoint 3: PASS
```

Este tipo de comprobación será especialmente útil posteriormente dentro de GitHub Actions.

Conceptualmente:

```
docker run
    │
    ▼
curl
    │
    ├── 200 → PASS
    │
    ├── 301 → seguir redirect
    │           │
    │           ▼
    │          200 → PASS
    │
    └── error → FAIL
```

## 24. Troubleshooting real — HTTP 301 en rutas Docusaurus

Durante la ejecución de M2 se observó el siguiente comportamiento:

```
curl -I http://localhost:8080/docs/m1-docusaurus-bootstrap
```

Respuesta:

```
HTTP/1.1 301 Moved Permanently
Server: nginx
Location: http://localhost/docs/m1-docusaurus-bootstrap/
```

El archivo sí existía, pero la respuesta no era `200`.

Diagnóstico

La página Docusaurus estaba físicamente representada como:

```
/usr/share/nginx/html/
└── docs/
    └── m1-docusaurus-bootstrap/
        └── index.html
```

La petición:

```
/docs/m1-docusaurus-bootstrap
```

apuntaba realmente a un directorio.

NGINX agregó automáticamente:

```
/
```

para canonicalizar la URL.

Por tanto:

```
301 Moved Permanently
```

era un comportamiento esperado.

## 25. Problema adicional detectado

Aunque el `301` era correcto, se detectó que el header:

```
Location
```

contenía:

```
http://localhost/docs/m1-docusaurus-bootstrap/
```

en lugar de:

```
http://localhost:8080/docs/m1-docusaurus-bootstrap/
```

El puerto `8080` desaparecía.

La causa es que:

```
Docker Host
8080
  │
  ▼
Container
80
```

NGINX solamente conoce su puerto interno `80`.

Al generar una URL absoluta, no tiene conocimiento directo del puerto publicado por Docker.

## 26. Resolución

Se agregó:

```
absolute_redirect off;
```

a la configuración:

```
server {
    listen 80;
    server_name _;

    absolute_redirect off;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ $uri.html =404;
    }
}
```

Después fue necesario reconstruir la imagen.

## 27. Reconstruir después del cambio

Detener el contenedor:

```
docker stop lab04-docusaurus
```

Eliminarlo:

```
docker rm lab04-docusaurus
```

Reconstruir:

```
docker build -t lab04-docusaurus:local .
```

Ejecutar nuevamente:

```
docker run \
  --name lab04-docusaurus \
  -d \
  -p 8080:80 \
  lab04-docusaurus:local
```

## 28. Validar la corrección

Ejecutar:

```
curl -I http://localhost:8080/docs/m1-docusaurus-bootstrap
```

Esperamos algo similar a:

```
HTTP/1.1 301 Moved Permanently
Location: /docs/m1-docusaurus-bootstrap/
```

La diferencia importante es:

```
Antes:
Location: http://localhost/docs/m1-docusaurus-bootstrap/

Después:
Location: /docs/m1-docusaurus-bootstrap/
```

Al ser una URL relativa, el cliente conserva:

```
localhost:8080
```

Después:

```
curl -I http://localhost:8080/docs/m1-docusaurus-bootstrap/
```

deberá responder:

```
HTTP/1.1 200 OK
```

## 29. Evidencia de troubleshooting

Registrar:

```
Issue:
Docusaurus documentation route without trailing slash returned HTTP 301.

Cause:
The generated Docusaurus page is represented as a directory
containing index.html.

Observed behavior:
NGINX canonicalized the directory URL by adding a trailing slash.

Additional issue:
The absolute redirect omitted Docker's externally mapped port 8080.

Resolution:
Added `absolute_redirect off;` to nginx.conf so redirects remain relative.

Validation:
The canonical route with trailing slash returns HTTP 200.
The redirect now uses a relative Location header.
```

Este hallazgo debe conservarse para la sección de troubleshooting del documento final del Lab 04.

## 30. Revisar los logs

Ejecutar:

```
docker logs lab04-docusaurus
```

Después de navegar por el sitio deberían aparecer solicitudes HTTP realizadas contra NGINX.

Por ejemplo:

```
GET /
GET /docs/m1-docusaurus-bootstrap
GET /docs/m1-docusaurus-bootstrap/
GET /assets/...
```

Aquí podremos observar incluso la secuencia:

```
301
→
200
```

Este es nuestro primer contacto en el Lab 04 con la observabilidad de la aplicación.

Posteriormente, en AWS, el mismo concepto evolucionará hacia:

```
NGINX logs
      │
      ▼
container logs
      │
      ▼
Amazon CloudWatch Logs
```

## 31. Inspeccionar el contenedor

Podemos entrar temporalmente:

```
docker exec -it lab04-docusaurus sh
```

Dentro del contenedor:

```
ls /usr/share/nginx/html
```

Deberíamos encontrar los archivos generados por Docusaurus.

Por ejemplo:

```
index.html
assets/
docs/
blog/
```

También podemos comprobar directamente la página:

```
ls /usr/share/nginx/html/docs/m1-docusaurus-bootstrap
```

Esperamos:

```
index.html
```

Salir:

```
exit
```

Esto demuestra físicamente:

```
Docusaurus build
        │
        ▼
/usr/share/nginx/html
        │
        ▼
NGINX
```

## 32. Verificar que Node.js no está en el runtime

Una ventaja importante del multi-stage build es que Node.js solo pertenece al builder.

Podemos comprobarlo:

```
docker exec lab04-docusaurus node --version
```

Esperamos que el comando no exista.

Esto confirma:

```
Builder                  Runtime

Node.js                  NGINX
npm                      Static Files
node_modules       →     No Node.js
source code              No npm
```

El runtime contiene solamente lo necesario para servir la aplicación.

## 33. Detener el contenedor

Ejecutar:

```
docker stop lab04-docusaurus
```

Verificar:

```
docker ps
```

El contenedor ya no deberá estar en ejecución.

Podemos observarlo con:

```
docker ps -a
```

## 34. Eliminar el contenedor

Ejecutar:

```
docker rm lab04-docusaurus
```

La imagen permanecerá disponible:

```
docker image ls lab04-docusaurus
```

Esto demuestra nuevamente la separación:

```
Image
  │
  ├── puede existir
  │
  └── sin que exista un container ejecutándose
```

## 35. Reconstrucción de reproducibilidad

Como prueba adicional podemos volver a levantar un nuevo contenedor utilizando exactamente la misma imagen:

```
docker run \
  --name lab04-docusaurus \
  -d \
  -p 8080:80 \
  lab04-docusaurus:local
```

Comprobar:

```
curl -I http://localhost:8080
```

Después comprobar una ruta canónica:

```
curl -I -L http://localhost:8080/docs/m1-docusaurus-bootstrap
```

Y volver a limpiar:

```
docker stop lab04-docusaurus
docker rm lab04-docusaurus
```

Resultado esperado:

```
Root:
HTTP 200

Docusaurus route:
301 → 200
```

## 36. Checklist final de M2

```
M2 — Containerización con Docker + NGINX

[ ] M1 está completado
[ ] Docker funciona localmente
[ ] .dockerignore creado
[ ] nginx.conf creado
[ ] absolute_redirect off configurado
[ ] Dockerfile creado
[ ] Dockerfile utiliza multi-stage build
[ ] Stage builder utiliza Node.js
[ ] npm ci se ejecuta dentro del builder
[ ] npm run build se ejecuta dentro del builder
[ ] Stage runtime utiliza NGINX
[ ] build/ se copia desde builder hacia runtime
[ ] Imagen lab04-docusaurus:local creada
[ ] Contenedor ejecuta correctamente
[ ] localhost:8080 responde HTTP 200
[ ] Página principal carga correctamente
[ ] Páginas de documentación funcionan
[ ] Assets funcionan correctamente
[ ] Ruta canónica responde HTTP 200
[ ] Ruta sin trailing slash puede responder 301 correctamente
[ ] Redirect Location es relativo y conserva el puerto externo
[ ] curl -L termina en HTTP 200
[ ] NGINX genera logs
[ ] Contenido existe en /usr/share/nginx/html
[ ] Node.js no forma parte del runtime
[ ] Contenedor puede detenerse y recrearse
[ ] Troubleshooting del HTTP 301 documentado
```

Si todas las verificaciones son correctas:

```
M2 STATUS: PASS
```

## 37. Evidencia sugerida

Registrar:

```
Milestone:
M2 — Containerización con Docker + NGINX

Status:
PASS / FAIL

Environment:
- Docker:
- Node builder:
- NGINX runtime:

Docker image:
- Repository: lab04-docusaurus
- Tag: local
- Image ID:
- Size:

Validation:
- docker build:
- docker run:
- GET /:
- GET canonical docs route:
- GET docs route without trailing slash:
- curl -L:

Evidence:
- Dockerfile:
- nginx.conf:
- docker image ls:
- docker ps:
- curl:
- docker logs:
- Screenshot localhost:8080:

Issues found:
- HTTP 301 on directory-style Docusaurus route.
- Absolute redirect initially omitted Docker external port 8080.

Resolution:
- Confirmed 301 is valid canonical redirect behavior.
- Added absolute_redirect off to nginx.conf.

Final validation:
- Redirect uses relative Location.
- Canonical URL returns HTTP 200.
```

## 38. Commit del milestone

Revisar:

```
git status
```

Agregar:

```
git add .
```

Crear commit:

```
git commit -m "feat: containerize Docusaurus with nginx"
```

Publicar:

```
git push
```

Si la corrección de `absolute_redirect` se realizó en un commit independiente, también puede utilizarse:

```
git commit -m "fix: preserve docker port in nginx redirects"
```

## 39. Qué demostramos en M2

Al finalizar M2 habremos demostrado:

```
Source Code
     │
     ▼
Docker Build
     │
     ├───────────────────────────┐
     │                           │
     ▼                           │
Node Builder                    │
     │                           │
     ▼                           │
npm ci                          │
     │                           │
     ▼                           │
npm run build                   │
     │                           │
     ▼                           │
Docusaurus build/               │
     │                           │
     └──────────────┐            │
                    ▼            │
                  NGINX          │
                    │            │
                    ▼            │
                Docker Image ◄───┘
                    │
                    ▼
               Container
                    │
                    ▼
            localhost:8080
```

También hemos comprobado una separación conceptual fundamental:

```
BUILD ENVIRONMENT
Node.js + npm + source
          │
          │ artifact
          ▼
      build/
          │
          ▼
RUNTIME ENVIRONMENT
NGINX + static files
```

Y además aprendimos un comportamiento operativo real:

```
Docusaurus directory route
          │
          ▼
NGINX canonical redirect
          │
         301
          │
          ▼
Trailing-slash URL
          │
          ▼
         200
```

## 40. Relación con M1

En M1 demostramos:

```
Docusaurus
    │
    ▼
npm run build
    │
    ▼
build/
```

En M2 extendimos el flujo:

```
Docusaurus
    │
    ▼
Docker Builder
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
Container
```

La aplicación ya está empaquetada como una unidad reproducible.

## 41. Preparación para M3

El siguiente milestone será:

```
M3 — Publicación de la imagen en Amazon ECR
```

Hasta este momento nuestra imagen existe únicamente en nuestra máquina:

```
Local Machine

lab04-docusaurus:local
```

M3 introducirá por primera vez AWS:

```
Local Docker
      │
      ▼
docker tag
      │
      ▼
AWS Authentication
      │
      ▼
Amazon ECR
      │
      ▼
Docker Registry
```

El objetivo será transformar:

```
Local Image
```

en:

```
Versioned Image
      +
Amazon ECR Repository
      +
Image Digest
```

Todavía no ejecutaremos la aplicación en AWS.

Eso sucederá en:

```
M4 — ECS + Fargate
```

## Criterio de salida

El milestone puede considerarse cerrado cuando:

> La aplicación Docusaurus puede construirse mediante un Dockerfile multi-stage, la imagen final utiliza NGINX como runtime, el contenedor puede iniciarse localmente, las rutas Docusaurus funcionan correctamente y las redirecciones canónicas conservan adecuadamente el acceso mediante el puerto publicado por Docker.

```
M2 STATUS: PASS
```