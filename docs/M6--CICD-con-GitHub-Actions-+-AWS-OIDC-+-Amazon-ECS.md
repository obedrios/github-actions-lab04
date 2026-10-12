---
sidebar_position: 6
title: "M6 — CI/CD con GitHub Actions + AWS OIDC + Amazon ECS"
description: "Automatización completa del build, publicación en Amazon ECR y deployment en Amazon ECS/Fargate mediante GitHub Actions y autenticación federada AWS OIDC sin credenciales de larga duración."
tags:
  - aws
  - github-actions
  - oidc
  - amazon-ecr
  - amazon-ecs
  - fargate
  - docker
  - cicd
  - iam
  - devops
  - docusaurus
  - lab04
---

# M6 — CI/CD con GitHub Actions + AWS OIDC + Amazon ECS

## Objetivo

Automatizar el flujo que hasta ahora realizamos manualmente:

```text
Source Change
     │
     ▼
Docker Build
     │
     ▼
Container Image
     │
     ▼
Amazon ECR
     │
     ▼
Task Definition Revision
     │
     ▼
ECS Service Update
     │
     ▼
Fargate Deployment
     │
     ▼
Verification
```

utilizando:

```text
GitHub Actions
      +
GitHub OIDC
      +
AWS IAM
      +
Amazon ECR
      +
Amazon ECS / Fargate
```

El resultado será un pipeline:

```text
git push
   │
   ▼
GitHub Actions
   │
   ├── validate
   ├── authenticate with AWS using OIDC
   ├── build Docker image
   ├── push image to ECR
   ├── render Task Definition
   ├── deploy ECS Service
   ├── wait for stability
   └── verify deployment
```

sin almacenar:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

como secrets permanentes en GitHub.

---

## 1. Resultado esperado

Al finalizar M6:

```text
Developer
    │
    │ git push
    ▼
GitHub
    │
    ▼
GitHub Actions
    │
    ├── npm build
    │
    ├── request OIDC token
    │
    ▼
AWS STS
    │
    ▼
Temporary Credentials
    │
    ├── ECR push
    │
    └── ECS deploy
    │
    ▼
Amazon ECS
    │
    ▼
Fargate Task
    │
    ▼
Docusaurus
```

El criterio principal de salida será:

> **PASS:** un `git push` a la rama `development` construye una nueva imagen identificable, la publica en ECR, genera una nueva revisión de la Task Definition, actualiza el ECS Service y deja una nueva Fargate Task estable cuyo digest corresponde exactamente con la imagen publicada por el workflow.

---

## 2. Qué cambia respecto a M4

En M4 realizábamos manualmente:

```text
docker build
docker push
aws ecs register-task-definition
aws ecs update-service
aws ecs wait services-stable
```

Ahora GitHub Actions realizará ese mismo proceso.

Antes:

```text
Developer
   │
   ▼
AWS CLI
   │
   ▼
AWS
```

Ahora:

```text
Developer
   │
   │ git push
   ▼
GitHub
   │
   ▼
GitHub Actions
   │
   │ OIDC
   ▼
AWS
```

---

## 3. Qué reutilizamos de milestones anteriores

No construiremos nueva infraestructura.

Reutilizaremos:

```text
M3
└── Amazon ECR repository
    └── lab04-docusaurus

M4
├── ECS Cluster
├── ECS Service
├── Fargate networking
├── Security Group
├── Task Execution Role
└── Task Definition

M5
├── CloudWatch Log Group
├── awslogs
└── observability
```

M6 agregará:

```text
IAM OIDC Provider
        │
        ▼
GitHub Actions IAM Role
        │
        ▼
GitHub Actions Workflow
```

---

## 4. Dos IAM Roles diferentes

Es muy importante distinguir los dos roles.

### ECS Task Execution Role

Creado anteriormente:

```text
ecsTaskExecutionRole
```

Es utilizado por:

```text
ECS / Fargate
```

para:

```text
Pull image from ECR
Send logs to CloudWatch
```

Flujo:

```text
Fargate
   │
   ▼
ecsTaskExecutionRole
   │
   ├── ECR
   └── CloudWatch
```

---

### GitHub Actions Deployment Role

Crearemos:

```text
lab04-github-actions-deploy-role
```

Será utilizado por:

```text
GitHub Actions
```

para:

```text
Push image to ECR
Register Task Definition
Update ECS Service
Inspect deployment
```

Flujo:

```text
GitHub Actions
      │
      │ OIDC
      ▼
lab04-github-actions-deploy-role
      │
      ├── ECR
      ├── ECS
      ├── EC2 describe ENI
      └── iam:PassRole
```

Por tanto:

```text
ecsTaskExecutionRole
        ≠
lab04-github-actions-deploy-role
```

---

## 5. Arquitectura de autenticación

No utilizaremos Access Keys.

El mecanismo será:

```text
GitHub Workflow
      │
      │ requests OIDC token
      ▼
GitHub OIDC Provider
      │
      ▼
AWS STS
      │
      │ AssumeRoleWithWebIdentity
      ▼
Temporary AWS Credentials
      │
      ▼
AWS APIs
```

Las credenciales temporales:

```text
expire automatically
```

y no necesitan almacenarse permanentemente.

---

## 6. Precondiciones

Antes de comenzar verificar:

```text
[ ] AWS CLI funciona
[ ] aws-lab funciona
[ ] GitHub CLI opcionalmente instalado
[ ] Repository existe en GitHub
[ ] development branch existe
[ ] ECR repository existe
[ ] ECS Cluster existe
[ ] ECS Service existe
[ ] Service puede ejecutar desiredCount = 1
[ ] Task Definition de M5 funciona
[ ] CloudWatch logs funcionan
```

Verificar AWS:

```bash
aws sts get-caller-identity \
  --profile aws-lab
```

---

## 7. Variables locales

Definir:

```bash
export AWS_REGION="us-east-1"
export ECR_REPOSITORY="lab04-docusaurus"
export ECS_CLUSTER="lab04-cluster"
export ECS_SERVICE="lab04-service"
export TASK_FAMILY="lab04-docusaurus"
export CONTAINER_NAME="lab04-docusaurus"
export GITHUB_ENVIRONMENT="development"
export GITHUB_ACTIONS_ROLE_NAME="lab04-github-actions-deploy-role"
```

Obtener Account ID:

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
  --profile aws-lab \
  --query Account \
  --output text)
```

Verificar:

```bash
echo "${AWS_ACCOUNT_ID}"
echo "${AWS_REGION}"
echo "${ECS_CLUSTER}"
echo "${ECS_SERVICE}"
echo "${ECR_REPOSITORY}"
```

---

## 8. Identificar repositorio GitHub

Desde el repositorio local:

```bash
git remote -v
```

Si tenemos GitHub CLI:

```bash
gh repo view
```

Obtener owner:

```bash
export GITHUB_OWNER=$(gh repo view \
  --json owner \
  --jq '.owner.login')
```

Obtener repository:

```bash
export GITHUB_REPOSITORY_NAME=$(gh repo view \
  --json name \
  --jq '.name')
```

Verificar:

```bash
echo "${GITHUB_OWNER}"
echo "${GITHUB_REPOSITORY_NAME}"
```

Esperamos conceptualmente:

```text
OWNER/github-actions-lab04
```

---

## 9. Obtener IDs inmutables de GitHub

Para repositorios que utilizan el formato moderno de claims OIDC, podemos obtener los identificadores numéricos del owner y repository.

Ejecutar:

```bash
gh api \
  "repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY_NAME}" \
  --jq '{
    repository: .full_name,
    repository_id: .id,
    owner: .owner.login,
    owner_id: .owner.id
  }'
```

Guardar:

```bash
export GITHUB_OWNER_ID=$(gh api \
  "repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY_NAME}" \
  --jq '.owner.id')
```

```bash
export GITHUB_REPOSITORY_ID=$(gh api \
  "repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY_NAME}" \
  --jq '.id')
```

Verificar:

```bash
echo "OWNER=${GITHUB_OWNER}"
echo "OWNER_ID=${GITHUB_OWNER_ID}"

echo "REPOSITORY=${GITHUB_REPOSITORY_NAME}"
echo "REPOSITORY_ID=${GITHUB_REPOSITORY_ID}"
```

---

## 10. El claim `sub` de GitHub OIDC

AWS utilizará el claim:

```text
sub
```

para determinar qué workflow puede asumir el IAM Role.

Como utilizaremos un GitHub Environment:

```text
development
```

el subject estará asociado a ese environment.

Dependiendo de la configuración y antigüedad del repositorio, pueden existir dos formatos.

### Formato clásico

```text
repo:OWNER/REPOSITORY:environment:development
```

Ejemplo conceptual:

```text
repo:my-user/github-actions-lab04:environment:development
```

---

### Formato con IDs inmutables

Repositorios modernos pueden utilizar:

```text
repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:environment:development
```

Ejemplo conceptual:

```text
repo:my-user@1234567/github-actions-lab04@987654321:environment:development
```

Para este laboratorio preferiremos el formato con IDs cuando corresponda a la configuración del repositorio.

Construirlo:

```bash
export GITHUB_OIDC_SUB="repo:${GITHUB_OWNER}@${GITHUB_OWNER_ID}/${GITHUB_REPOSITORY_NAME}@${GITHUB_REPOSITORY_ID}:environment:${GITHUB_ENVIRONMENT}"
```

Verificar:

```bash
echo "${GITHUB_OIDC_SUB}"
```

Este valor será crítico para la trust policy.

---

## 11. Verificar si el GitHub OIDC Provider ya existe

El provider es:

```text
token.actions.githubusercontent.com
```

Construir ARN:

```bash
export GITHUB_OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
```

Intentar consultarlo:

```bash
aws iam get-open-id-connect-provider \
  --profile aws-lab \
  --open-id-connect-provider-arn "${GITHUB_OIDC_PROVIDER_ARN}"
```

Si funciona:

```text
OIDC Provider already exists
```

No debemos crear otro.

Esto es común si ya realizamos anteriormente otros laboratorios con GitHub Actions + AWS OIDC.

---

## 12. Crear OIDC Provider si no existe

Solo ejecutar este paso si el provider no existe.

```bash
aws iam create-open-id-connect-provider \
  --profile aws-lab \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

Después verificar:

```bash
aws iam get-open-id-connect-provider \
  --profile aws-lab \
  --open-id-connect-provider-arn "${GITHUB_OIDC_PROVIDER_ARN}"
```

Debemos encontrar:

```text
Url:
token.actions.githubusercontent.com

ClientIDList:
sts.amazonaws.com
```

---

## 13. Relación Provider vs Role

El OIDC Provider dice:

```text
AWS trusts tokens issued by GitHub
```

pero eso por sí mismo **no da permisos**.

Necesitamos:

```text
OIDC Provider
      │
      ▼
IAM Trust Policy
      │
      ▼
IAM Role
      │
      ▼
Permission Policy
```

---

## 14. Crear Trust Policy

Crear:

```text
github-actions-oidc-trust-policy.json
```

Contenido:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "GITHUB_OIDC_PROVIDER_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "GITHUB_OIDC_SUB"
        }
      }
    }
  ]
}
```

Reemplazar:

```text
GITHUB_OIDC_PROVIDER_ARN
```

por:

```bash
echo "${GITHUB_OIDC_PROVIDER_ARN}"
```

y:

```text
GITHUB_OIDC_SUB
```

por:

```bash
echo "${GITHUB_OIDC_SUB}"
```

---

## 15. Ejemplo conceptual de Trust Policy

El archivo final tendrá una estructura equivalente a:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:environment:development"
        }
      }
    }
  ]
}
```

No copiar literalmente los placeholders.

---

## 16. Crear GitHub Actions IAM Role

Ejecutar:

```bash
aws iam create-role \
  --profile aws-lab \
  --role-name "${GITHUB_ACTIONS_ROLE_NAME}" \
  --assume-role-policy-document file://github-actions-oidc-trust-policy.json
```

Si ya existe:

```text
EntityAlreadyExists
```

no eliminarlo automáticamente.

Consultar:

```bash
aws iam get-role \
  --profile aws-lab \
  --role-name "${GITHUB_ACTIONS_ROLE_NAME}"
```

---

## 17. Obtener ARN del deployment role

Ejecutar:

```bash
export GITHUB_ACTIONS_ROLE_ARN=$(aws iam get-role \
  --profile aws-lab \
  --role-name "${GITHUB_ACTIONS_ROLE_NAME}" \
  --query 'Role.Arn' \
  --output text)
```

Verificar:

```bash
echo "${GITHUB_ACTIONS_ROLE_ARN}"
```

Conceptualmente:

```text
arn:aws:iam::<ACCOUNT_ID>:role/lab04-github-actions-deploy-role
```

---

## 18. Obtener ARN del ECS Task Execution Role

Necesitaremos permitir:

```text
iam:PassRole
```

al deployment role.

Obtener:

```bash
export ECS_EXECUTION_ROLE_ARN=$(aws iam get-role \
  --profile aws-lab \
  --role-name ecsTaskExecutionRole \
  --query 'Role.Arn' \
  --output text)
```

Verificar:

```bash
echo "${ECS_EXECUTION_ROLE_ARN}"
```

---

## 19. ¿Por qué GitHub necesita `iam:PassRole`?

GitHub no utilizará directamente:

```text
ecsTaskExecutionRole
```

pero registrará una Task Definition que contiene:

```json
"executionRoleArn": "..."
```

Por tanto:

```text
GitHub Actions Role
       │
       │ RegisterTaskDefinition
       │ references
       ▼
ecsTaskExecutionRole
```

AWS debe permitir explícitamente:

```text
iam:PassRole
```

Esto **no significa** que GitHub asuma ese role.

Significa:

```text
GitHub is allowed to tell ECS:

"Use this role when the Task runs"
```

---

## 20. Crear permissions policy

Crear:

```text
github-actions-deploy-policy.json
```

Contenido base:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuthorization",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECRPushAndInspect",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:DescribeImages"
      ],
      "Resource": "ECR_REPOSITORY_ARN"
    },
    {
      "Sid": "ECSDeployment",
      "Effect": "Allow",
      "Action": [
        "ecs:RegisterTaskDefinition",
        "ecs:DescribeTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:ListTasks",
        "ecs:DescribeTasks"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassECSTaskExecutionRole",
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "ECS_EXECUTION_ROLE_ARN",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ecs-tasks.amazonaws.com"
        }
      }
    },
    {
      "Sid": "InspectFargateNetworkInterface",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeNetworkInterfaces"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 21. Obtener ARN del ECR Repository

Ejecutar:

```bash
export ECR_REPOSITORY_ARN=$(aws ecr describe-repositories \
  --profile aws-lab \
  --repository-names "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}" \
  --query 'repositories[0].repositoryArn' \
  --output text)
```

Verificar:

```bash
echo "${ECR_REPOSITORY_ARN}"
```

---

## 22. Completar permissions policy

Reemplazar:

```text
ECR_REPOSITORY_ARN
```

por el resultado de:

```bash
echo "${ECR_REPOSITORY_ARN}"
```

Reemplazar:

```text
ECS_EXECUTION_ROLE_ARN
```

por:

```bash
echo "${ECS_EXECUTION_ROLE_ARN}"
```

---

## 23. Adjuntar policy al GitHub Actions Role

Utilizaremos una inline policy para mantener el laboratorio autocontenido.

Ejecutar:

```bash
aws iam put-role-policy \
  --profile aws-lab \
  --role-name "${GITHUB_ACTIONS_ROLE_NAME}" \
  --policy-name Lab04GitHubActionsDeployPolicy \
  --policy-document file://github-actions-deploy-policy.json
```

Verificar:

```bash
aws iam list-role-policies \
  --profile aws-lab \
  --role-name "${GITHUB_ACTIONS_ROLE_NAME}" \
  --output table
```

Esperamos:

```text
Lab04GitHubActionsDeployPolicy
```

---

## 24. Inspeccionar policy

Ejecutar:

```bash
aws iam get-role-policy \
  --profile aws-lab \
  --role-name "${GITHUB_ACTIONS_ROLE_NAME}" \
  --policy-name Lab04GitHubActionsDeployPolicy
```

Verificar especialmente:

```text
ECR permissions
ECS permissions
iam:PassRole
ec2:DescribeNetworkInterfaces
```

---

## 25. Checkpoint 1 — IAM

```text
[ ] GitHub OIDC Provider existe
[ ] Audience = sts.amazonaws.com
[ ] GitHub repository identificado
[ ] GitHub owner ID obtenido
[ ] GitHub repository ID obtenido
[ ] OIDC subject definido
[ ] Trust Policy creada
[ ] GitHub Actions Role creado
[ ] Deployment permissions configuradas
[ ] iam:PassRole limitado a ecsTaskExecutionRole
```

Resultado:

```text
Checkpoint 1: PASS
```

---

## 26. Crear GitHub Environment

En GitHub:

```text
Repository
    ↓
Settings
    ↓
Environments
    ↓
New environment
```

Crear:

```text
development
```

Debe coincidir exactamente con:

```bash
echo "${GITHUB_ENVIRONMENT}"
```

El nombre es sensible porque forma parte del OIDC subject.

---

## 27. Configurar variable AWS_ROLE_ARN

Dentro de:

```text
Settings
  → Environments
    → development
```

crear una Environment Variable:

```text
AWS_ROLE_ARN
```

Valor:

```bash
echo "${GITHUB_ACTIONS_ROLE_ARN}"
```

El ARN del role no es una contraseña ni una Access Key.

No necesitamos crear:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

---

## 28. Variables vs Secrets

Para este laboratorio:

```text
AWS_ROLE_ARN
```

puede ser:

```text
GitHub Environment Variable
```

porque el ARN no es una credencial secreta.

El workflow utilizará:

```yaml
${{ vars.AWS_ROLE_ARN }}
```

La seguridad real está en:

```text
IAM Trust Policy
+
OIDC claims
```

---

## 29. Verificar `task-definition.json`

El archivo:

```text
task-definition.json
```

debe permanecer en el repositorio.

Debe conservar la configuración funcional obtenida en M5.

Ejemplo:

```json
{
  "family": "lab04-docusaurus",
  "networkMode": "awsvpc",
  "requiresCompatibilities": [
    "FARGATE"
  ],
  "cpu": "256",
  "memory": "512",
  "runtimePlatform": {
    "cpuArchitecture": "X86_64",
    "operatingSystemFamily": "LINUX"
  },
  "executionRoleArn": "arn:aws:iam::<ACCOUNT_ID>:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "lab04-docusaurus",
      "image": "<CURRENT_IMAGE_URI>",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/lab04-docusaurus",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

No necesitamos modificar manualmente:

```text
image
```

en cada deployment.

GitHub Actions lo hará.

---

## 30. Task Definition as Code

A partir de M6:

```text
task-definition.json
```

forma parte del código del deployment.

Conceptualmente:

```text
Application Source
Dockerfile
nginx.conf
task-definition.json
workflow YAML
```

quedan versionados juntos.

Esto nos da:

```text
Git commit
     │
     ├── application version
     ├── container definition
     └── deployment instructions
```

---

## 31. Estrategia de tags

No utilizaremos:

```text
latest
```

Tampoco sobrescribiremos:

```text
m3-v1
m4-v2
```

ECR fue configurado como:

```text
IMMUTABLE
```

Por ello cada workflow debe generar un tag único.

---

## 32. Tag trazable

Utilizaremos:

```text
Git SHA
+
GitHub Run Number
+
Run Attempt
```

Formato:

```text
sha-<SHORT_SHA>-run-<RUN_NUMBER>-attempt-<ATTEMPT>
```

Ejemplo:

```text
sha-abc123def456-run-17-attempt-1
```

Esto proporciona:

```text
Source traceability
+
Deployment traceability
+
Compatibility with immutable ECR
+
Safe workflow reruns
```

---

## 33. Por qué no usar únicamente `${GITHUB_SHA}`

En principio:

```text
GITHUB_SHA
```

es un excelente identificador.

Sin embargo, nuestro ECR utiliza:

```text
IMMUTABLE
```

Si volvemos a ejecutar un workflow para el mismo commit, intentar publicar nuevamente el mismo tag podría producir:

```text
ImageTagAlreadyExistsException
```

Al incorporar:

```text
RUN_NUMBER
RUN_ATTEMPT
```

cada publicación permanece única.

---

## 34. Crear directorio de workflows

Si no existe:

```bash
mkdir -p .github/workflows
```

Crear:

```text
.github/workflows/deploy-development.yml
```

---

## 35. Workflow completo

Crear:

```yaml
name: Deploy Lab04 to ECS

on:
  push:
    branches:
      - development

  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: lab04-ecs-development
  cancel-in-progress: false

env:
  AWS_REGION: us-east-1

  ECR_REPOSITORY: lab04-docusaurus

  ECS_CLUSTER: lab04-cluster
  ECS_SERVICE: lab04-service

  ECS_TASK_DEFINITION: task-definition.json

  CONTAINER_NAME: lab04-docusaurus

jobs:

  validate:
    name: Validate application
    runs-on: ubuntu-latest

    steps:

      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Build Docusaurus
        run: npm run build


  deploy:
    name: Build image and deploy to ECS

    needs:
      - validate

    runs-on: ubuntu-latest

    environment:
      name: development

    permissions:
      contents: read
      id-token: write

    steps:

      - name: Checkout repository
        uses: actions/checkout@v4


      - name: Configure AWS credentials with OIDC
        uses: aws-actions/configure-aws-credentials@v6.3.0
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: lab04-github-actions


      - name: Verify AWS identity
        run: |
          aws sts get-caller-identity


      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2


      - name: Setup Docker Buildx
        uses: docker/setup-buildx-action@v3


      - name: Define image metadata
        id: image
        shell: bash
        run: |
          SHORT_SHA="${GITHUB_SHA::12}"

          IMAGE_TAG="sha-${SHORT_SHA}-run-${GITHUB_RUN_NUMBER}-attempt-${GITHUB_RUN_ATTEMPT}"

          IMAGE_URI="${{ steps.login-ecr.outputs.registry }}/${ECR_REPOSITORY}:${IMAGE_TAG}"

          echo "tag=${IMAGE_TAG}" >> "${GITHUB_OUTPUT}"
          echo "uri=${IMAGE_URI}" >> "${GITHUB_OUTPUT}"

          echo "IMAGE_TAG=${IMAGE_TAG}"
          echo "IMAGE_URI=${IMAGE_URI}"


      - name: Build and push Docker image
        run: |
          docker buildx build \
            --platform linux/amd64 \
            --provenance=false \
            --sbom=false \
            --push \
            -t "${{ steps.image.outputs.uri }}" \
            .


      - name: Read ECR image digest
        id: ecr-image
        shell: bash
        run: |
          IMAGE_DIGEST=$(aws ecr describe-images \
            --repository-name "${ECR_REPOSITORY}" \
            --image-ids imageTag="${{ steps.image.outputs.tag }}" \
            --region "${AWS_REGION}" \
            --query 'imageDetails[0].imageDigest' \
            --output text)

          echo "digest=${IMAGE_DIGEST}" >> "${GITHUB_OUTPUT}"

          echo "ECR image digest:"
          echo "${IMAGE_DIGEST}"


      - name: Render ECS task definition
        id: task-def
        uses: aws-actions/amazon-ecs-render-task-definition@v1.9.0
        with:
          task-definition: ${{ env.ECS_TASK_DEFINITION }}
          container-name: ${{ env.CONTAINER_NAME }}
          image: ${{ steps.image.outputs.uri }}


      - name: Deploy ECS task definition
        uses: aws-actions/amazon-ecs-deploy-task-definition@v2.6.3
        with:
          task-definition: ${{ steps.task-def.outputs.task-definition }}
          service: ${{ env.ECS_SERVICE }}
          cluster: ${{ env.ECS_CLUSTER }}
          desired-count: 1
          wait-for-service-stability: true


      - name: Inspect ECS service
        run: |
          aws ecs describe-services \
            --cluster "${ECS_CLUSTER}" \
            --services "${ECS_SERVICE}" \
            --region "${AWS_REGION}" \
            --query 'services[0].[status,desiredCount,runningCount,pendingCount,taskDefinition]' \
            --output table


      - name: Get running task
        id: running-task
        shell: bash
        run: |
          TASK_ARN=$(aws ecs list-tasks \
            --cluster "${ECS_CLUSTER}" \
            --service-name "${ECS_SERVICE}" \
            --desired-status RUNNING \
            --region "${AWS_REGION}" \
            --query 'taskArns[0]' \
            --output text)

          if [ -z "${TASK_ARN}" ] || [ "${TASK_ARN}" = "None" ]; then
            echo "ERROR: No RUNNING task found"
            exit 1
          fi

          echo "task-arn=${TASK_ARN}" >> "${GITHUB_OUTPUT}"

          echo "TASK_ARN=${TASK_ARN}"


      - name: Verify running image
        id: running-image
        shell: bash
        run: |
          RUNNING_IMAGE=$(aws ecs describe-tasks \
            --cluster "${ECS_CLUSTER}" \
            --tasks "${{ steps.running-task.outputs.task-arn }}" \
            --region "${AWS_REGION}" \
            --query 'tasks[0].containers[0].image' \
            --output text)

          RUNNING_DIGEST=$(aws ecs describe-tasks \
            --cluster "${ECS_CLUSTER}" \
            --tasks "${{ steps.running-task.outputs.task-arn }}" \
            --region "${AWS_REGION}" \
            --query 'tasks[0].containers[0].imageDigest' \
            --output text)

          echo "RUNNING_IMAGE=${RUNNING_IMAGE}"
          echo "RUNNING_DIGEST=${RUNNING_DIGEST}"

          echo "image=${RUNNING_IMAGE}" >> "${GITHUB_OUTPUT}"
          echo "digest=${RUNNING_DIGEST}" >> "${GITHUB_OUTPUT}"


      - name: Verify digest traceability
        shell: bash
        run: |
          EXPECTED_DIGEST="${{ steps.ecr-image.outputs.digest }}"
          RUNNING_DIGEST="${{ steps.running-image.outputs.digest }}"

          echo "Expected digest:"
          echo "${EXPECTED_DIGEST}"

          echo "Running digest:"
          echo "${RUNNING_DIGEST}"

          if [ "${EXPECTED_DIGEST}" != "${RUNNING_DIGEST}" ]; then
            echo "FAIL: Running ECS digest does not match ECR image digest"
            exit 1
          fi

          echo "PASS: ECS is running the exact image published by this workflow"


      - name: Get Fargate ENI and Public IP
        id: network
        shell: bash
        run: |
          TASK_ARN="${{ steps.running-task.outputs.task-arn }}"

          ENI_ID=$(aws ecs describe-tasks \
            --cluster "${ECS_CLUSTER}" \
            --tasks "${TASK_ARN}" \
            --region "${AWS_REGION}" \
            --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" \
            --output text)

          PUBLIC_IP=$(aws ec2 describe-network-interfaces \
            --network-interface-ids "${ENI_ID}" \
            --region "${AWS_REGION}" \
            --query 'NetworkInterfaces[0].Association.PublicIp' \
            --output text)

          echo "ENI_ID=${ENI_ID}"
          echo "PUBLIC_IP=${PUBLIC_IP}"

          echo "eni-id=${ENI_ID}" >> "${GITHUB_OUTPUT}"
          echo "public-ip=${PUBLIC_IP}" >> "${GITHUB_OUTPUT}"


      - name: HTTP smoke test
        shell: bash
        run: |
          PUBLIC_IP="${{ steps.network.outputs.public-ip }}"

          if [ -z "${PUBLIC_IP}" ] || [ "${PUBLIC_IP}" = "None" ]; then
            echo "ERROR: No Public IP found"
            exit 1
          fi

          echo "Testing http://${PUBLIC_IP}"

          curl \
            --fail \
            --silent \
            --show-error \
            --retry 10 \
            --retry-delay 3 \
            --retry-connrefused \
            "http://${PUBLIC_IP}/" \
            > /dev/null

          echo "PASS: HTTP smoke test completed successfully"


      - name: Deployment summary
        shell: bash
        run: |
          {
            echo "## Lab04 ECS Deployment"
            echo ""
            echo "- Environment: development"
            echo "- Region: ${AWS_REGION}"
            echo "- ECS Cluster: ${ECS_CLUSTER}"
            echo "- ECS Service: ${ECS_SERVICE}"
            echo "- Image tag: ${{ steps.image.outputs.tag }}"
            echo "- Image digest: ${{ steps.ecr-image.outputs.digest }}"
            echo "- Task ARN: ${{ steps.running-task.outputs.task-arn }}"
            echo "- ENI: ${{ steps.network.outputs.eni-id }}"
            echo "- Public IP: ${{ steps.network.outputs.public-ip }}"
            echo "- Digest verification: PASS"
            echo "- HTTP smoke test: PASS"
          } >> "${GITHUB_STEP_SUMMARY}"
```

---

## 36. Estructura del workflow

Tenemos dos jobs:

```text
validate
   │
   ▼
deploy
```

### `validate`

Realiza:

```text
checkout
npm ci
npm run build
```

No necesita acceso a AWS.

---

### `deploy`

Realiza:

```text
OIDC authentication
ECR login
Docker build
Docker push
Task Definition render
ECS deployment
Digest validation
HTTP smoke test
```

Solo este job obtiene acceso temporal a AWS.

---

37. Principio de mínimo acceso

Esto es importante:

```text
validate
```

no tiene:

```text
id-token: write
```

Solo:

```text
deploy
```

puede solicitar un OIDC token.

Conceptualmente:

```text
CI validation
      │
      X
   AWS access


Deployment
      │
      ▼
   AWS OIDC
```

---

## 38. `permissions: id-token: write`

Esta línea:

```yaml
permissions:
  contents: read
  id-token: write
```

no da permisos directos sobre AWS.

Permite que GitHub Actions solicite:

```text
OIDC token
```

Después:

```text
OIDC token
   │
   ▼
AWS STS
   │
   ▼
IAM Role
```

AWS decide finalmente si el workflow puede asumir el role.

---

## 39. Importancia de `environment: development`

Tenemos:

```yaml
environment:
  name: development
```

Esto hace que el deployment pertenezca al GitHub Environment:

```text
development
```

y además forma parte de la identidad OIDC.

Por ello la Trust Policy puede restringirse a:

```text
repository
+
environment
```

en lugar de confiar en cualquier workflow.

---

## 40. Validar YAML antes del push

Verificar:

```bash
git status
```

Archivos esperados:

```text
.github/workflows/deploy-development.yml
task-definition.json
github-actions-oidc-trust-policy.json
github-actions-deploy-policy.json
docs/...
```

Las policies utilizadas exclusivamente para crear IAM pueden conservarse como documentación del laboratorio.

---

## 41. Seguridad antes del commit

Antes de hacer commit verificar que no exista:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
password
private key
```

Buscar accidentalmente:

```bash
grep -R "AWS_SECRET_ACCESS_KEY" . \
  --exclude-dir=.git
```

y:

```bash
grep -R "AWS_ACCESS_KEY_ID" . \
  --exclude-dir=.git
```

Idealmente no debe encontrarse ninguna credencial real.

---

## 42. Commit inicial de M6

Ejemplo:

```bash
git add .
```

```bash
git commit -m "ci: deploy Docusaurus to ECS with GitHub OIDC"
```

---

## 43. Publicar rama development

Verificar rama:

```bash
git branch --show-current
```

Si estamos en:

```text
development
```

ejecutar:

```bash
git push origin development
```

Esto debe disparar:

```text
Deploy Lab04 to ECS
```

---

## 44. Observar workflow

En GitHub:

```text
Repository
   ↓
Actions
   ↓
Deploy Lab04 to ECS
```

Deberíamos observar:

```text
validate
   │
   ├── checkout
   ├── npm ci
   └── npm run build
          │
          ▼
deploy
   │
   ├── AWS OIDC
   ├── ECR login
   ├── build image
   ├── push image
   ├── render task definition
   ├── deploy ECS
   ├── verify digest
   └── HTTP smoke test
```

---

## 45. Verificar autenticación OIDC

El step:

```text
Verify AWS identity
```

ejecuta:

```bash
aws sts get-caller-identity
```

El ARN debe corresponder a una sesión del role:

```text
lab04-github-actions-deploy-role
```

Conceptualmente:

```text
arn:aws:sts::<ACCOUNT>:assumed-role/lab04-github-actions-deploy-role/...
```

Esto demuestra que:

```text
GitHub
   │
   ▼
OIDC
   │
   ▼
STS
   │
   ▼
temporary role session
```

funcionó correctamente.

---

## 46. Verificar imagen creada en ECR

Después de un workflow exitoso:

```bash
aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}" \
  --query 'reverse(sort_by(imageDetails,& imagePushedAt))[0:5].[imageTags,imageDigest,imagePushedAt]' \
  --output table
```

Deberemos encontrar un tag:

```text
sha-xxxxxxxxxxxx-run-X-attempt-1
```

---

## 47. Verificar nueva Task Definition

Ejecutar:

```bash
aws ecs describe-task-definition \
  --profile aws-lab \
  --task-definition "${TASK_FAMILY}" \
  --region "${AWS_REGION}" \
  --query 'taskDefinition.[family,revision,containerDefinitions[0].image]' \
  --output table
```

Debemos observar:

```text
lab04-docusaurus
<new revision>
.../lab04-docusaurus:sha-...
```

---

## 48. Verificar ECS Service

Ejecutar:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].[status,desiredCount,runningCount,pendingCount,taskDefinition]' \
  --output table
```

Esperamos:

```text
ACTIVE
1
1
0
...lab04-docusaurus:<NEW_REVISION>
```

---

## 49. Verificar Task

Obtener:

```bash
export TASK_ARN=$(aws ecs list-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service-name "${ECS_SERVICE}" \
  --desired-status RUNNING \
  --region "${AWS_REGION}" \
  --query 'taskArns[0]' \
  --output text)
```

Consultar:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].containers[0].[image,imageDigest,lastStatus]' \
  --output table
```

---

## 50. Trazabilidad completa

Después de M6 podemos establecer:

```text
Git Commit
   │
   ▼
GitHub SHA
   │
   ▼
GitHub Workflow Run
   │
   ▼
ECR Image Tag
   │
   ▼
Image Digest
   │
   ▼
ECS Task Definition Revision
   │
   ▼
ECS Running Task
```

Esto nos permite responder:

> ¿Qué código está ejecutándose en AWS?

mediante evidencia verificable.

---

## 51. Ejercicio real — modificar documentación

Realizar ahora un cambio pequeño en Docusaurus.

Ejemplo:

```markdown
## M6 Deployment Test

Esta página fue publicada automáticamente mediante GitHub Actions.
```

Verificar localmente:

```bash
npm run build
```

Commit:

```bash
git add .
```

```bash
git commit -m "docs: validate automated ECS deployment"
```

Push:

```bash
git push origin development
```

---

## 52. Qué debería suceder

Sin ejecutar comandos AWS manualmente:

```text
git push
   │
   ▼
GitHub Actions
   │
   ▼
New Docker Image
   │
   ▼
ECR
   │
   ▼
New Task Definition
   │
   ▼
ECS Deployment
   │
   ▼
New Fargate Task
```

Después:

```text
Browser
   │
   ▼
new Public IP
   │
   ▼
Updated Docusaurus
```

---

## 53. Ver CloudWatch después del deployment

M5 continúa siendo útil.

Ejecutar:

```bash
aws logs tail "/ecs/lab04-docusaurus" \
  --profile aws-lab \
  --since 10m \
  --region "${AWS_REGION}"
```

Podremos observar los requests de smoke test realizados por GitHub Actions.

Esto conecta:

```text
M5 Observability
        │
        ▼
M6 Automated Deployment
```

---

## 54. GitHub Step Summary

El workflow genera automáticamente un resumen:

```text
Lab04 ECS Deployment

Environment: development
Region: us-east-1
ECS Cluster: lab04-cluster
ECS Service: lab04-service
Image tag: ...
Image digest: sha256:...
Task ARN: ...
ENI: ...
Public IP: ...
Digest verification: PASS
HTTP smoke test: PASS
```

Esto constituye evidencia útil para nuestro laboratorio.

---

## 55. Checkpoint 2 — Primer deployment automatizado

```text
[ ] validate job PASS
[ ] deploy job PASS
[ ] OIDC authentication PASS
[ ] ECR login PASS
[ ] Docker build PASS
[ ] ECR push PASS
[ ] New image tag created
[ ] New image digest obtained
[ ] Task Definition rendered
[ ] New revision registered
[ ] ECS Service updated
[ ] ECS Service stable
[ ] Running Task identified
[ ] Running digest matches ECR digest
[ ] Public IP identified
[ ] HTTP smoke test PASS
```

Resultado:

```text
Checkpoint 2: PASS
```

---

## 56. Troubleshooting — OIDC `Not authorized`

Uno de los errores más importantes puede ser:

```text
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

Esto normalmente indica un problema en:

```text
Trust Policy
```

y no necesariamente en la permission policy.

Verificar:

```bash
aws iam get-role \
  --profile aws-lab \
  --role-name "${GITHUB_ACTIONS_ROLE_NAME}" \
  --query 'Role.AssumeRolePolicyDocument'
```

Revisar especialmente:

```text
aud
sub
```

---

## 57. Troubleshooting — `sub` mismatch

Si GitHub genera:

```text
repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:development
```

pero AWS espera:

```text
repo:OWNER/REPO:environment:development
```

la comparación falla.

Conceptualmente:

```text
Token sub
     ≠
Trust Policy sub
```

Resultado:

```text
AssumeRoleWithWebIdentity denied
```

La solución es alinear exactamente ambos valores.

---

## 58. Troubleshooting — Environment faltante

Si nuestra trust policy espera:

```text
:environment:development
```

pero el job no contiene:

```yaml
environment:
  name: development
```

el OIDC subject puede ser diferente.

Por tanto estas dos configuraciones están relacionadas:

```text
GitHub Workflow Environment
           │
           ▼
OIDC sub claim
           │
           ▼
AWS Trust Policy
```

---

## 59. Troubleshooting — `id-token: write`

Si olvidamos:

```yaml
id-token: write
```

la Action no podrá obtener el OIDC token.

Verificar:

```yaml
deploy:

  permissions:
    contents: read
    id-token: write
```

---

## 60. Troubleshooting — `iam:PassRole`

Un error como:

```text
is not authorized to perform iam:PassRole
```

puede ocurrir al registrar la Task Definition.

Revisar:

```text
GitHub Actions Role
     │
     ▼
iam:PassRole
     │
     ▼
ecsTaskExecutionRole
```

Consultar policy:

```bash
aws iam get-role-policy \
  --profile aws-lab \
  --role-name "${GITHUB_ACTIONS_ROLE_NAME}" \
  --policy-name Lab04GitHubActionsDeployPolicy
```

---

## 61. Troubleshooting — ECR push AccessDenied

Si Docker falla durante:

```text
push
```

verificar:

```text
ecr:GetAuthorizationToken
ecr:BatchCheckLayerAvailability
ecr:InitiateLayerUpload
ecr:UploadLayerPart
ecr:CompleteLayerUpload
ecr:PutImage
```

También comprobar que:

```text
ECR_REPOSITORY
```

coincida con:

```text
lab04-docusaurus
```

---

## 62. Troubleshooting — ImageTagAlreadyExistsException

Si ECR responde con:

```text
ImageTagAlreadyExistsException
```

recordar que el repository está configurado como:

```text
IMMUTABLE
```

Nunca reutilizar un tag existente.

Nuestro formato:

```text
SHA + RUN_NUMBER + RUN_ATTEMPT
```

debe evitar este problema.

---

## 63. Troubleshooting — Task Definition container not found

La Action:

```text
amazon-ecs-render-task-definition
```

busca:

```yaml
container-name: lab04-docusaurus
```

Esto debe coincidir exactamente con:

```json
"name": "lab04-docusaurus"
```

dentro de:

```text
task-definition.json
```

Si no coincide, el render fallará.

---

## 64. Troubleshooting — Service no alcanza estabilidad

Si:

```text
wait-for-service-stability
```

falla, revisar primero:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].events[0:15].[createdAt,message]' \
  --output table
```

Después revisar Tasks detenidas:

```bash
aws ecs list-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service-name "${ECS_SERVICE}" \
  --desired-status STOPPED \
  --region "${AWS_REGION}"
```

Esto conecta directamente con M5.

---

## 65. Troubleshooting — CannotPullContainerError

Consultar:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "<FAILED_TASK_ARN>" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].[stopCode,stoppedReason,containers[0].reason]' \
  --output table
```

Revisar:

```text
ECR image exists?
Execution Role?
Networking?
Image architecture?
```

---

## 66. Troubleshooting — HTTP smoke test timeout

Puede ocurrir que todo el deployment ECS sea correcto pero:

```text
curl
```

desde GitHub falle.

Revisar:

```text
Security Group
```

En M4 permitimos de forma didáctica:

```text
TCP 80
0.0.0.0/0
```

Si modificamos el Security Group para aceptar únicamente nuestra IP personal:

```text
MY_IP/32
```

el GitHub-hosted runner probablemente no podrá acceder.

En ese caso:

```text
ECS deployment = PASS
External smoke test = FAIL
```

El problema pertenece al nivel:

```text
network access
```

no necesariamente al deployment.

---

## 67. Nota de seguridad sobre el smoke test

Permitir:

```text
0.0.0.0/0 → TCP 80
```

es aceptable únicamente para este laboratorio temporal.

No representa la arquitectura recomendada para producción.

Más adelante una arquitectura real utilizaría típicamente:

```text
Internet
   │
   ▼
Application Load Balancer
   │
   ▼
Private ECS Tasks
```

con Security Groups entre:

```text
ALB
 ↓
ECS
```

---

## 68. Troubleshooting — Digest mismatch

Si:

```text
ECR digest
   ≠
Running Task digest
```

no debemos considerar exitoso el deployment.

Posibles causas:

```text
old Task still running
wrong ECS Service
wrong Task selected
deployment not stable
wrong image rendered
```

Nuestro pipeline falla explícitamente en esta situación.

---

## 69. ¿Por qué verificar digest?

Un tag dice:

```text
which name we intended to deploy
```

El digest dice:

```text
exactly which artifact is running
```

Por eso:

```text
Tag
   │
   ▼
human-readable identity

Digest
   │
   ▼
content identity
```

La verificación fuerte es:

```text
ECR Digest
    =
Running ECS Digest
```

---

## 70. Pipeline como máquina de estados

Podemos modelar el pipeline:

```text
SOURCE
  │
  ▼
VALIDATED
  │
  ▼
AUTHENTICATED
  │
  ▼
IMAGE_BUILT
  │
  ▼
IMAGE_PUBLISHED
  │
  ▼
TASK_RENDERED
  │
  ▼
DEPLOYED
  │
  ▼
STABLE
  │
  ▼
VERIFIED
```

Si cualquier transición falla:

```text
Pipeline = FAIL
```

---

## 71. Relación con PDCA

M6 también puede interpretarse mediante nuestro ciclo:

```text
PLAN
Define workflow + IAM + deployment

DO
Run GitHub Actions

CHECK
Build result
ECR digest
ECS stability
HTTP smoke test

ACT
Accept deployment
or diagnose failure
```

La automatización no elimina PDCA.

La automatización ejecuta repetidamente parte del ciclo.

---

## 72. Separación CI y CD

El workflow mantiene una división conceptual:

```text
CI
│
└── validate
    ├── npm ci
    └── npm run build


CD
│
└── deploy
    ├── build container
    ├── publish ECR
    ├── ECS deployment
    └── verify
```

Esto evita que:

```text
invalid source
```

avance directamente al deployment.

---

## 73. Evidencia del milestone

Registrar:

```text
Milestone:
M6 — GitHub Actions + AWS OIDC + ECS

Status:
PASS / FAIL

GitHub:
- Repository:
- Branch:
- Environment:
- Workflow:
- Run number:
- Run attempt:
- Git SHA:

AWS Identity:
- OIDC Provider:
- Deployment Role:

ECR:
- Repository:
- Image tag:
- Image digest:

ECS:
- Cluster:
- Service:
- Task Definition family:
- Task Definition revision:
- Task ARN:

Networking:
- ENI:
- Public IP:

Validation:
- npm build:
- ECS stable:
- Digest match:
- HTTP smoke test:

Observability:
- CloudWatch logs:
- ECS events:

Issues:
- none / description

Root cause:
- N/A / description

Resolution:
- N/A / description
```

---

## 74. Checklist final

```text
M6 — GitHub Actions + AWS OIDC + ECS

IAM / OIDC

[ ] GitHub OIDC Provider verified
[ ] Audience sts.amazonaws.com
[ ] Repository identity identified
[ ] OIDC sub determined
[ ] Trust Policy restricted
[ ] GitHub deployment role created
[ ] ECR permissions configured
[ ] ECS permissions configured
[ ] iam:PassRole configured
[ ] EC2 describe permission configured

GitHub

[ ] development Environment created
[ ] AWS_ROLE_ARN variable configured
[ ] No AWS Access Keys stored
[ ] workflow created
[ ] id-token: write configured
[ ] concurrency configured

CI

[ ] checkout works
[ ] Node 22 configured
[ ] npm ci works
[ ] npm run build works

Container

[ ] ECR login works
[ ] Buildx works
[ ] linux/amd64 image generated
[ ] provenance disabled for current lab
[ ] SBOM disabled for current lab
[ ] unique tag generated
[ ] image pushed successfully
[ ] digest obtained

ECS

[ ] task-definition.json versioned
[ ] image rendered automatically
[ ] new Task Definition revision created
[ ] ECS Service updated
[ ] desiredCount = 1
[ ] runningCount = 1
[ ] pendingCount = 0
[ ] Service stable

Traceability

[ ] Running Task identified
[ ] running image identified
[ ] running digest identified
[ ] ECR digest = ECS digest

Smoke Test

[ ] ENI obtained
[ ] Public IP obtained
[ ] GET / returns HTTP success

Observability

[ ] CloudWatch logs continue working
[ ] ECS Events usable for diagnosis
[ ] GitHub Step Summary generated
```

Resultado:

```text
M6 STATUS: PASS
```

---

## 75. Qué logramos realmente

Antes de M6:

```text
Developer
   │
   ├── docker build
   ├── docker push
   ├── register task definition
   ├── update service
   └── verify
```

Después de M6:

```text
Developer
   │
   └── git push
          │
          ▼
     GitHub Actions
          │
          ├── Validate
          ├── Authenticate
          ├── Build
          ├── Publish
          ├── Deploy
          └── Verify
```

La complejidad no desapareció.

La convertimos en:

```text
repeatable automation
```

---

## 76. Resultado arquitectónico acumulado

Después de M1–M6 tenemos:

```text
Developer
    │
    │ git push
    ▼
GitHub Repository
    │
    ▼
GitHub Actions
    │
    │ OIDC
    ▼
AWS STS
    │
    ▼
IAM Deployment Role
    │
    ├──────────────┐
    │              │
    ▼              ▼
Amazon ECR      Amazon ECS
    │              │
    │              ▼
    │          Task Definition
    │              │
    └──────────────┤
                   ▼
               Fargate
                   │
                   ▼
                NGINX
                   │
                   ▼
              Docusaurus
                   │
                   ▼
             CloudWatch Logs
```

---

## 77. Qué eliminamos del proceso

Ya no necesitamos hacer manualmente:

```text
docker login ECR
docker build
docker push

aws ecs register-task-definition
aws ecs update-service
aws ecs wait services-stable
```

para cada cambio.

Tampoco necesitamos:

```text
AWS access keys in GitHub
```

---

## 78. Qué todavía permanece manual

Todavía tenemos algunos elementos deliberadamente manuales:

```text
IAM/OIDC bootstrap
Infrastructure creation
Security Group
ECS Cluster
ECS Service
ECR repository
CloudWatch Log Group
```

Eso es intencional.

En un laboratorio futuro podremos convertir esta infraestructura a:

```text
Terraform
```

o:

```text
AWS CloudFormation
```

obteniendo:

```text
Infrastructure as Code
+
CI/CD
```

---

## 79. Pausar después de M6

Si deseamos detener Fargate:

```bash
aws ecs update-service \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --desired-count 0 \
  --region "${AWS_REGION}"
```

Verificar:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].[desiredCount,runningCount,pendingCount]' \
  --output table
```

Esperamos:

```text
0
0
0
```

---

## 80. Importante al volver a hacer push

Nuestro workflow contiene:

```yaml
desired-count: 1
```

Por tanto un nuevo deployment desde:

```text
development
```

volverá a levantar el servicio.

Conceptualmente:

```text
Paused ECS
desiredCount = 0

        │
        │ git push
        ▼

GitHub Actions
        │
        ▼

desiredCount = 1
        │
        ▼

New Fargate Task
```

Esto debe ser considerado cuando queramos controlar costos.

---

## 81. Preparación para M7

M6 automatizó el happy path:

```text
Source
  ↓
Image
  ↓
Deploy
  ↓
Stable
```

Pero ahora surge una pregunta mucho más interesante:

> ¿Qué sucede cuando el deployment automatizado contiene una versión defectuosa?

Eso será:

```text
M7 — Controlled Failure + Rollback
```

Estudiaremos:

```text
Good Version
     │
     ▼
Bad Deployment
     │
     ▼
Failure Detection
     │
     ▼
Rollback
     │
     ▼
Known Good Version
```

---

## Criterio de salida

M6 puede considerarse completado cuando:

> Un push a `development` ejecuta un workflow de GitHub Actions que valida Docusaurus, obtiene credenciales temporales AWS mediante OIDC, construye una imagen container única, la publica en Amazon ECR, genera una nueva revisión de la ECS Task Definition, actualiza el ECS Service, espera estabilidad, comprueba que el digest ejecutado coincide exactamente con el digest publicado y realiza un smoke test HTTP exitoso sin utilizar Access Keys permanentes.

```text
M6 STATUS: PASS
```



# Notes