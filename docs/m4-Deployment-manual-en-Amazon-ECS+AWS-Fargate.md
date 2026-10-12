---
sidebar_position: 4
title: "M4 — Deployment manual en Amazon ECS + AWS Fargate"
description: "Despliegue manual de la imagen Docusaurus almacenada en Amazon ECR utilizando Amazon ECS y AWS Fargate, incluyendo networking, IAM, Task Definition, ECS Service y validación HTTP."
tags:

- aws
- amazon-ecs
- fargate
- amazon-ecr
- docker
- containers
- networking
- iam
- docusaurus
- devops
- lab04
---



# M4 — Deployment manual en Amazon ECS + AWS Fargate

## Objetivo

Desplegar manualmente en AWS la imagen de Docusaurus publicada durante **M3** utilizando:

- Amazon ECR.
- Amazon ECS.
- AWS Fargate.
- IAM.
- VPC.
- Public Subnet.
- Security Group.

Por primera vez en el Lab 04 tendremos:

```
Application Running in AWS
```

El flujo será:

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
      │
      ▼
Public IP
      │
      ▼
HTTP Request
```

En este milestone todavía **no incorporaremos GitHub Actions, OIDC, Load Balancer ni CloudWatch Logs**.

El criterio principal de salida será:

> **PASS:** Amazon ECS mantiene una Fargate Task ejecutando `lab04-docusaurus:m3-v1`, la aplicación puede accederse mediante HTTP utilizando la public IP de la task y el digest de la imagen ejecutada puede relacionarse con el artefacto almacenado en Amazon ECR.

## Alcance

M4 introduce:

- Amazon ECS Cluster.
- ECS Task Definition.
- ECS Task.
- ECS Service.
- AWS Fargate.
- Task Execution Role.
- `awsvpc`.
- Elastic Network Interface.
- Public subnet.
- Public IP.
- Security Group.
- Container port mapping.
- CPU y memoria de Fargate.
- Verificación del image digest.
- ECS service stability.

Este milestone todavía no incluye:

```
Application Load Balancer
HTTPS
CloudWatch Logs
Container Insights
GitHub Actions
OIDC
Automated deployment
Rollback
```

Estos elementos aparecerán en milestones posteriores.

## 1. Estado inicial

M3 debe estar completado.

Disponemos en Amazon ECR de:

```
Repository:
lab04-docusaurus

Tag:
m3-v1

Platform:
linux/amd64

Media Type:
application/vnd.oci.image.manifest.v1+json

Digest:
sha256:...
```

Conceptualmente:

```
Amazon ECR
      │
      ▼
lab04-docusaurus:m3-v1
```

En M4 esa imagen pasará de:

```
Stored Artifact
```

a:

```
Running Application
```

## 2. Arquitectura de M4

La arquitectura intencionalmente simple será:

```
                    Internet
                        │
                        │ HTTP :80
                        ▼
                ┌───────────────┐
                │ Security Group│
                └───────┬───────┘
                        │
                        ▼
                Public IP / ENI
                        │
                        ▼
               ┌─────────────────┐
               │  Fargate Task   │
               │                 │
               │  NGINX :80      │
               │  Docusaurus     │
               └────────┬────────┘
                        │
                        │ image pull
                        ▼
                  Amazon ECR
```

Amazon ECS administrará:

```
Desired State
```

mientras AWS Fargate proporcionará la capacidad de ejecución.

## 3. Decisión arquitectónica del milestone

Durante M4 utilizaremos:

```
Public Subnet
+
Public IP
+
Security Group
```

para mantener el laboratorio simple.

Esto permite validar directamente:

```
Browser
   │
   ▼
Public IP
   │
   ▼
Fargate Task
```

sin introducir todavía:

```
Application Load Balancer
Target Group
HTTPS
Certificate
```

En un entorno productivo normalmente preferiríamos:

```
Internet
   │
   ▼
Load Balancer
   │
   ▼
Private Tasks
```

pero esa complejidad no es necesaria para demostrar los conceptos centrales de M4.

## 4. Prerrequisitos

Verificar sesión AWS:

```bash
aws sts get-caller-identity \
  --profile aws-lab
```

Definir región:

```bash
export AWS_REGION="us-east-1"
```

Definir variables:

```bash
export ECS_CLUSTER="lab04-cluster"
export ECS_SERVICE="lab04-service"
export TASK_FAMILY="lab04-docusaurus"
export CONTAINER_NAME="lab04-docusaurus"
export ECR_REPOSITORY="lab04-docusaurus"
export IMAGE_TAG="m3-v1"
```

Obtener Account ID:

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
  --profile aws-lab \
  --query Account \
  --output text)
```

Construir URI ECR:

```bash
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export ECR_REPOSITORY_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}"
```

Construir referencia de imagen:

```bash
export IMAGE_URI="${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
```

Verificar:

```bash
echo "${IMAGE_URI}"
```

## 5. Verificar la imagen de M3

Ejecutar:

```bash
aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query 'imageDetails[0].[imageTags,imageDigest,imageManifestMediaType]' \
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
+---------------------------------------------------------------------------+
```

Guardar el digest:

```bash
export EXPECTED_IMAGE_DIGEST=$(aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query 'imageDetails[0].imageDigest' \
  --output text)
```

Verificar:

```bash
echo "${EXPECTED_IMAGE_DIGEST}"
```

## 6. Checkpoint 1 — Artefacto de entrada

```
[ ] aws-lab autenticado
[ ] Región correcta
[ ] lab04-docusaurus existe en ECR
[ ] m3-v1 existe
[ ] Media type es OCI Image Manifest
[ ] Digest sha256 registrado
[ ] IMAGE_URI definido
```

Resultado:

```
Checkpoint 1: PASS
```

## 7. Crear el ECS Cluster

Crear:

```bash
aws ecs create-cluster \
  --profile aws-lab \
  --cluster-name "${ECS_CLUSTER}" \
  --region "${AWS_REGION}"
```

Lo que resulta en,

```json
{
    "cluster": {
        "clusterArn": "arn:aws:ecs:us-east-1:565866186032:cluster/lab04-cluster",
        "clusterName": "lab04-cluster",
        "status": "ACTIVE",
        "registeredContainerInstancesCount": 0,
        "runningTasksCount": 0,
        "pendingTasksCount": 0,
        "activeServicesCount": 0,
        "statistics": [],
        "tags": [],
        "settings": [
            {
                "name": "containerInsights",
                "value": "disabled"
            }
        ],
        "capacityProviders": [],
        "defaultCapacityProviderStrategy": []
    }
}

```

Verificar:

```bash
aws ecs describe-clusters \
  --profile aws-lab \
  --clusters "${ECS_CLUSTER}" \
  --region "${AWS_REGION}" \
  --query 'clusters[0].[clusterName,status,runningTasksCount,pendingTasksCount]' \
  --output table
```

Esperamos inicialmente algo similar a:

```markdown
-------------------
|DescribeClusters |
+-----------------+
|  lab04-cluster  |
|  ACTIVE         |
|  0              |
|  0              |
+-----------------+

```

## 8. Entender el ECS Cluster

El cluster es un límite lógico donde ECS administra workloads.

En nuestro caso:

```
ECS Cluster
    │
    └── lab04-cluster
```

Todavía no significa que exista un container ejecutándose.

Conceptualmente:

```
Cluster exists
      ≠
Application running
```

## 9. Crear Task Execution Role

La Fargate Task debe poder realizar operaciones necesarias durante su arranque, incluyendo recuperar la imagen privada de Amazon ECR.

Crearemos:

```bash
ecsTaskExecutionRole
```

Primero crear:

```bash
ecs-tasks-trust-policy.json
```

Contenido:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Crear el role:

```bash
aws iam create-role \
  --profile aws-lab \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-tasks-trust-policy.json
```

respondiendo,

````json
{
    "Role": {
        "Path": "/",
        "RoleName": "ecsTaskExecutionRole",
        "RoleId": "AROAYHQCAYUYHWUALR7FR",
        "Arn": "arn:aws:iam::565866186032:role/ecsTaskExecutionRole",
        "CreateDate": "2026-10-11T00:09:59+00:00",
        "AssumeRolePolicyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ecs-tasks.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }
    }
}
````

Ahora, se necesita asociar la política administrada:

```bash
aws iam attach-role-policy \
  --profile aws-lab \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```



## 10. Obtener ARN del Execution Role

Ejecutar:

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

Resultado similar:

```
arn:aws:iam::565866186032:role/ecsTaskExecutionRole
```

## 11. Execution Role vs Task Role

Es importante distinguir:

```
Task Execution Role
```

de:

```
Task Role
```

El Execution Role es utilizado por la infraestructura ECS/Fargate para operaciones necesarias para iniciar la task.

Conceptualmente:

```
ECS / Fargate
      │
      ▼
Execution Role
      │
      ├── Pull from ECR
      └── Other runtime setup
```

Un Task Role, en cambio, sería utilizado por:

```
Application Code
      │
      ▼
AWS APIs
```

Nuestra aplicación Docusaurus no necesita acceder a APIs AWS.

Por tanto, en M4 no necesitamos un Task Role adicional.

## 12. Checkpoint 2 — IAM

```
[ ] ecsTaskExecutionRole creado
[ ] Trust policy utiliza ecs-tasks.amazonaws.com
[ ] AmazonECSTaskExecutionRolePolicy asociada
[ ] Execution Role ARN obtenido
```

Resultado:

```
Checkpoint 2: PASS
```

## 13. Seleccionar VPC

Para simplificar M4 utilizaremos la VPC por defecto de la cuenta si está disponible.

Obtener:

```bash
export VPC_ID=$(aws ec2 describe-vpcs \
  --profile aws-lab \
  --filters Name=isDefault,Values=true \
  --region "${AWS_REGION}" \
  --query 'Vpcs[0].VpcId' \
  --output text)
```

Verificar:

```bash
echo "${VPC_ID}"
```

Si el resultado es:

```
None
```

la cuenta no dispone de una default VPC y será necesario seleccionar o crear una VPC apropiada.

## 14. Seleccionar una subnet pública

Listar subnets:

```bash
aws ec2 describe-subnets \
  --profile aws-lab \
  --filters Name=vpc-id,Values="${VPC_ID}" \
  --region "${AWS_REGION}" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table
```

En este caso resulta, 

````markdown
----------------------------------------------------
|                  DescribeSubnets                 |
+---------------------------+--------------+-------+
|  subnet-019b14238ca1cdd90 |  us-east-1f  |  True |
|  subnet-0f7eb8f3bc2efdb6a |  us-east-1a  |  True |
|  subnet-08be8c13c9e1d8fb7 |  us-east-1e  |  True |
|  subnet-0a9eb77bbb3a533d9 |  us-east-1b  |  True |
|  subnet-0f3d68ca8a80fb911 |  us-east-1d  |  True |
|  subnet-051b9e19e874862de |  us-east-1c  |  True |
+---------------------------+--------------+-------+
````

Seleccionar una subnet apropiada.

Por ejemplo:

```bash
export SUBNET_ID="subnet-0f7eb8f3bc2efdb6a" 
```

Verificar:

```bash
echo "${SUBNET_ID}"
```



## 15. Verificar acceso público de la subnet

Una subnet pública necesita una ruta hacia un Internet Gateway.

Podemos inspeccionar las route tables asociadas:

```bash
# Lista todas las routes asociadas
aws ec2 describe-route-tables \
  --profile aws-lab \
  --filters Name=vpc-id,Values="${VPC_ID}" \
  --region "${AWS_REGION}" \
  --query 'RouteTables[*].[RouteTableId,Associations,Routes]' \
  --output json

# Para identificar la main route table
aws ec2 describe-route-tables \
  --profile aws-lab \
  --filters \
    Name=vpc-id,Values="${VPC_ID}" \
    Name=association.main,Values=true \
  --region "${AWS_REGION}" \
  --query 'RouteTables[0].[RouteTableId,Associations]' \
  --output json  
  
# Despues consultamos sus rutas
export ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --profile aws-lab \
  --filters \
    Name=vpc-id,Values="${VPC_ID}" \
    Name=association.main,Values=true \
  --region "${AWS_REGION}" \
  --query 'RouteTables[0].RouteTableId' \
  --output text)
  
echo "${ROUTE_TABLE_ID}"

# Despues
aws ec2 describe-route-tables \
  --profile aws-lab \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --region "${AWS_REGION}" \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,State]' \
  --output table
```

Buscamos conceptualmente:

```markdown
Public Subnet
      │
      │ implicit association
      ▼
Main Route Table
      │
      │ 0.0.0.0/0
      ▼
Internet Gateway
      │
      ▼
Internet
```

así la respuesta,

```markdown
------------------------------------------------------
|                 DescribeRouteTables                |
+----------------+-------------------------+---------+
|  172.31.0.0/16 |  local                  |  active |
|  0.0.0.0/0     |  igw-063bc2c7e042dce7d  |  active |
+----------------+-------------------------+---------+
```

Finalmente, una segunda comprobación importante antes de continuar con ECS/Fargate: verificar si la subnet permite asignación automática de public IP.

````bash
aws ec2 describe-subnets \
  --profile aws-lab \
  --subnet-ids "${SUBNET_ID}" \
  --region "${AWS_REGION}" \
  --query 'Subnets[0].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table
````

Lo importante es buscar true como asignación  automática de direccion IP publica,

````markdown
------------------------------
|       DescribeSubnets      |
+----------------------------+
|  subnet-0f7eb8f3bc2efdb6a  |
|  us-east-1a                |
|  True                      |
+----------------------------+
````



## 16. Crear Security Group

Crear:

```bash
export SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --profile aws-lab \
  --group-name lab04-fargate-sg \
  --description "Lab04 Fargate HTTP access" \
  --vpc-id "${VPC_ID}" \
  --region "${AWS_REGION}" \
  --query 'GroupId' \
  --output text)
```

Verificar:

```bash
echo "${SECURITY_GROUP_ID}"

# Response example,
sg-0a40eaa04f6626846
```

## 17. Permitir HTTP

La opción más simple para un laboratorio temporal es:

```bash
aws ec2 authorize-security-group-ingress \
  --profile aws-lab \
  --group-id "${SECURITY_GROUP_ID}" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region "${AWS_REGION}"
```

y su respuesta,

````json
{
    "Return": true,
    "SecurityGroupRules": [
        {
            "SecurityGroupRuleId": "sgr-0a9611c193a040da2",
            "GroupId": "sg-0a40eaa04f6626846",
            "GroupOwnerId": "565866186032",
            "IsEgress": false,
            "IpProtocol": "tcp",
            "FromPort": 80,
            "ToPort": 80,
            "CidrIpv4": "0.0.0.0/0",
            "SecurityGroupRuleArn": "arn:aws:ec2:us-east-1:565866186032:security-group-rule/sgr-0a9611c193a040da2"
        }
    ]
}

````



Esto expone temporalmente el puerto:

```
80/tcp
```

a Internet.

Para una práctica más restrictiva puede utilizarse:

```
YOUR_PUBLIC_IP/32
```

en lugar de:

```
0.0.0.0/0
```



## 18. Nota de seguridad

> [!warning]
>
> La apertura:
>
> ```
> 0.0.0.0/0 → TCP 80
> ```
>
> se utiliza únicamente para simplificar este laboratorio. No debe interpretarse como una recomendación general para workloads productivos. El Security Group será eliminado durante el teardown.



## 19. Verificar Security Group

Ejecutar:

```bash
aws ec2 describe-security-groups \
  --profile aws-lab \
  --group-ids "${SECURITY_GROUP_ID}" \
  --region "${AWS_REGION}" \
  --query 'SecurityGroups[0].[GroupId,GroupName,IpPermissions]' \
  --output json
```

Con la respuesta de,

````json
[
    "sg-0a40eaa04f6626846",
    "lab04-fargate-sg",
    [
        {
            "IpProtocol": "tcp",
            "FromPort": 80,
            "ToPort": 80,
            "UserIdGroupPairs": [],
            "IpRanges": [
                {
                    "CidrIp": "0.0.0.0/0"
                }
            ],
            "Ipv6Ranges": [],
            "PrefixListIds": []
        }
    ]
]
````



## 20. Checkpoint 3 — Networking

```
[ ] VPC identificada
[ ] Public subnet identificada
[ ] Internet Gateway route verificada
[ ] Security Group creado
[ ] TCP 80 permitido
[ ] SUBNET_ID registrado
[ ] SECURITY_GROUP_ID registrado
```

Resultado:

```
Checkpoint 3: PASS
```

## 21. Crear Task Definition

Crear:

```bash
task-definition.json
```

Contenido:

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
  "executionRoleArn": "EXECUTION_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "lab04-docusaurus",
      "image": "IMAGE_URI",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ]
    }
  ]
}
```

Reemplazar:

```
EXECUTION_ROLE_ARN
```

por:

```
echo "${ECS_EXECUTION_ROLE_ARN}"
```

y:

```
IMAGE_URI
```

por:

```
echo "${IMAGE_URI}"
```



## 22. Recursos utilizados

Utilizaremos:

```
CPU:
256 units
=
0.25 vCPU

Memory:
512 MiB
```

Para nuestra aplicación:

```
NGINX
+
Static Docusaurus
```

esta configuración es suficiente para el objetivo del laboratorio.

## 23. Arquitectura del runtime

Durante M3 construimos:

```
linux/amd64
```

Por tanto configuramos:

```
"runtimePlatform": {
  "cpuArchitecture": "X86_64",
  "operatingSystemFamily": "LINUX"
}
```

La relación debe ser coherente:

```
ECR Image
linux/amd64
     │
     =
     ▼
Fargate Runtime
LINUX / X86_64
```

## 24. Registrar Task Definition

Ejecutar:

```bash
aws ecs register-task-definition \
  --profile aws-lab \
  --cli-input-json file://task-definition.json \
  --region "${AWS_REGION}"
```

Consultar:

```bash
aws ecs describe-task-definition \
  --profile aws-lab \
  --task-definition "${TASK_FAMILY}" \
  --region "${AWS_REGION}" \
  --query 'taskDefinition.[family,revision,cpu,memory,networkMode,requiresCompatibilities]' \
  --output table
```

Esperamos:

```markdown
------------------------
|DescribeTaskDefinition|
+----------------------+
|  lab04-docusaurus    |
|  1                   |
|  256                 |
|  512                 |
|  awsvpc              |
|  FARGATE             |
+----------------------+
```



## 25. Entender Task Definition

Una Task Definition es un blueprint.

Define:

```
Image
CPU
Memory
Network Mode
Architecture
Ports
IAM Execution Role
```

pero todavía:

```
Task Definition
      ≠
Running Container
```

Conceptualmente:

```
Task Definition
      │
      ▼
Blueprint
```

## 26. Checkpoint 4 — Task Definition

```
[ ] Task family lab04-docusaurus creada
[ ] Revision 1 registrada
[ ] requiresCompatibilities contiene FARGATE
[ ] networkMode es awsvpc
[ ] CPU = 256
[ ] Memory = 512
[ ] Architecture = X86_64
[ ] OS = LINUX
[ ] Container usa m3-v1
[ ] containerPort = 80
[ ] Execution Role configurado
```

Resultado:

```
Checkpoint 4: PASS
```

## 27. Crear ECS Service

Ahora pediremos a ECS mantener:

```
desired-count = 1
```

Ejecutar:

```bash
aws ecs create-service \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service-name "${ECS_SERVICE}" \
  --task-definition "${TASK_FAMILY}" \
  --desired-count 1 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SECURITY_GROUP_ID}],assignPublicIp=ENABLED}" \
  --region "${AWS_REGION}"
```



## 28. Qué hará ECS

Conceptualmente:

```
ECS Service
    │
    │ desiredCount = 1
    ▼
Task Scheduler
    │
    ▼
Fargate Task
    │
    ▼
Container
```

Si la task falla:

```
Running Task
    │
    X
```

ECS intentará mantener nuevamente:

```
desiredCount = 1
```

Esta es una diferencia importante respecto a ejecutar manualmente un único container.



## 29. Esperar estabilidad

Ejecutar:

```bash
aws ecs wait services-stable \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}"
```

Cuando termine, consultar:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].[status,desiredCount,runningCount,pendingCount]' \
  --output table
```

Esperamos:

```
ACTIVE
1
1
0
```

También puede consultarse los eventos para verificar el estado.

````bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].events[0:5].[createdAt,message]' \
  --output table
````



## 30. Checkpoint 5 — ECS Service

```
[ ] ECS Service creado
[ ] Launch type FARGATE
[ ] Desired count = 1
[ ] Public IP habilitada
[ ] Service alcanza estado stable
[ ] runningCount = 1
[ ] pendingCount = 0
```

Resultado:

```
Checkpoint 5: PASS
```

## 31. Obtener Task ARN

Ejecutar:

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

Verificar:

```bash
echo "${TASK_ARN}"
```

## 32. Inspeccionar la Task

Ejecutar:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}"
```

Podemos obtener información compacta:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].[lastStatus,desiredStatus,launchType,platformVersion,cpu,memory]' \
  --output table
```

Esperamos:

```markdown
---------------
|DescribeTasks|
+-------------+
|  RUNNING    |
|  RUNNING    |
|  FARGATE    |
|  1.4.0      |
|  256        |
|  512        |
+-------------+
```

## 33. Obtener la ENI de la Task

Con `awsvpc`, cada Fargate Task dispone de una Elastic Network Interface.

Obtener:

```bash
export ENI_ID=$(aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" \
  --output text)
```

Verificar:

```bash
echo "${ENI_ID}"
```

## 34. Obtener Public IP

Ejecutar:

```bash
export PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --profile aws-lab \
  --network-interface-ids "${ENI_ID}" \
  --region "${AWS_REGION}" \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text)
```

Verificar:

```bash
echo "${PUBLIC_IP}"
```

El flujo de networking ahora es:

```
Internet
   │
   ▼
Public IP
   │
   ▼
Task ENI
   │
   ▼
Container :80
```

## 35. Primer acceso remoto

Ejecutar:

```bash
curl -I "http://${PUBLIC_IP}"
```

Esperamos:

```markdown
HTTP/1.1 200 OK
Server: nginx/1.30.5
Date: Sun, 11 Oct 2026 00:44:59 GMT
Content-Type: text/html
Content-Length: 69806
Last-Modified: Sat, 10 Oct 2026 23:32:23 GMT
Connection: keep-alive
ETag: "6acacb07-110ae"
Accept-Ranges: bytes
```

También podemos abrir:

```bash
http://<PUBLIC_IP>

# Es decir y abrir en el browser,
echo "http://${PUBLIC_IP}"
```

en el navegador.

Debemos observar:

```
Cloud & DevOps Hands-on Labs
Lab 04
```

## 36. Verificar ruta Docusaurus

Reutilizando el aprendizaje de M2:

```bash
curl -I -L \
  "http://${PUBLIC_IP}/docs/m1-docusaurus-bootstrap"
```

Puede observarse:

```
301
 ↓
200
```

Esto sigue siendo válido.

## 37. Checkpoint 6 — Aplicación remota

```
[ ] Task está RUNNING
[ ] ENI identificada
[ ] Public IP identificada
[ ] HTTP :80 accesible
[ ] GET / responde 200
[ ] NGINX responde
[ ] Docusaurus carga correctamente
[ ] Página de documentación funciona
```

Resultado:

```
Checkpoint 6: PASS
```

## 38. Verificar qué imagen está ejecutando Fargate

Queremos relacionar:

```
ECR artifact
```

con:

```
Running Task
```

Ejecutar:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].containers[0].[name,image,imageDigest,lastStatus]' \
  --output table
```

Esperamos encontrar:

```markdown
-----------------------------------------------------------------------------
|                               DescribeTasks                               |
+---------------------------------------------------------------------------+
|  lab04-docusaurus                                                         |
|  565866186032.dkr.ecr.us-east-1.amazonaws.com/lab04-docusaurus:m3-v1      |
|  sha256:2cf6092a4d4bacb046667a418511119752a904523c1c4e404ef1e1b6e1c40fa0  |
|  RUNNING                                                                  |
+---------------------------------------------------------------------------+
```



## 39. Comparar digests

Mostrar digest esperado:

```bash
echo "${EXPECTED_IMAGE_DIGEST}"
```

Obtener digest ejecutado:

```bash
export RUNNING_IMAGE_DIGEST=$(aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].containers[0].imageDigest' \
  --output text)
```

Mostrar:

```bash
echo "${RUNNING_IMAGE_DIGEST}"
```

Comparar:

```bash
if [ "${EXPECTED_IMAGE_DIGEST}" = "${RUNNING_IMAGE_DIGEST}" ]; then
  echo "PASS: Running task matches ECR image digest"
else
  echo "FAIL: Image digest mismatch"
fi
```

Resultado esperado:

```bash
PASS: Running task matches ECR image digest
```

## 40. Trazabilidad lograda

Ahora podemos demostrar:

```
Amazon ECR
      │
      │ m3-v1
      ▼
sha256:ABC
      │
      ▼
Task Definition
      │
      ▼
ECS Service
      │
      ▼
Fargate Task
      │
      ▼
sha256:ABC
```

Este será uno de los aprendizajes centrales del Lab 04.

## 41. Checkpoint 7 — Trazabilidad

```
[ ] ECR digest registrado
[ ] Running Task image URI consultada
[ ] Running Task imageDigest consultado
[ ] Digest ECR = Digest Fargate
[ ] La Task ejecuta m3-v1
```

Resultado:

```
Checkpoint 7: PASS
```

## 42. Observar ECS Events

Aunque CloudWatch llegará en M5, ECS ya proporciona eventos operativos.

Consultar:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].events[0:10].[createdAt,message]' \
  --output table
```

Podemos encontrar eventos relacionados con:

```
--------------------------------------------------------------------------------------------------------------------------------
|                                                       DescribeServices                                                       |
+-----------------------------------+------------------------------------------------------------------------------------------+
|  2026-10-10T17:37:30.185000-07:00 |  (service lab04-service) has reached a steady state.                                     |
|  2026-10-10T17:37:30.184000-07:00 |  (service lab04-service) (deployment ecs-svc/2343205646774159021) deployment completed.  |
|  2026-10-10T17:37:11.848000-07:00 |  (service lab04-service) has started 1 tasks: (task 98f30749333a467cb3034e0360bfe0fb).   |
+-----------------------------------+------------------------------------------------------------------------------------------+

```

Estos mensajes serán muy útiles durante M5.

## 43. Diferencia entre Cluster, Service, Task y Task Definition

Después de ejecutar M4 debemos poder distinguir claramente:

```
Cluster
```

Agrupación lógica donde ECS administra workloads.

```
Task Definition
```

Blueprint que describe cómo ejecutar containers.

```
Task
```

Instancia concreta de una Task Definition.

```
Service
```

Controlador que mantiene un número deseado de Tasks.

```
Fargate
```

Capacidad administrada donde las Tasks son ejecutadas.

Conceptualmente:

```
Cluster
   │
   └── Service
         │
         │ desiredCount = 1
         ▼
       Task
         │
         │ based on
         ▼
   Task Definition
         │
         ▼
     Container
```

## 44. Troubleshooting — Task queda en PENDING

Consultar:

```
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].events[0:10].[createdAt,message]' \
  --output table
```

También:

```
aws ecs list-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service-name "${ECS_SERVICE}" \
  --desired-status STOPPED \
  --region "${AWS_REGION}"
```

Posibles causas:

```
Networking
IAM
Image pull
Architecture
CPU / memory
```

## 45. Troubleshooting — CannotPullContainerError

Síntoma:

```
CannotPullContainerError
```

Verificar:

```
ECR repository
Image tag
Execution Role
Network access
```

Primero:

```bash
aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}"
```

Después comprobar:

```bash
aws iam list-attached-role-policies \
  --profile aws-lab \
  --role-name ecsTaskExecutionRole
```

Debe existir:

```
AmazonECSTaskExecutionRolePolicy
```

## 46. Troubleshooting — Exec format error

Un error similar a:

```
exec format error
```

puede indicar incompatibilidad de arquitectura.

En M3 utilizamos:

```
linux/amd64
```

y M4 utiliza:

```
LINUX
X86_64
```

Verificar ECR:

```bash
docker image inspect \
  "${ECR_REPOSITORY_URI}:${IMAGE_TAG}" \
  --format '{{.Os}}/{{.Architecture}}'
```

Esperamos:

```
linux/amd64
```

## 47. Troubleshooting — No responde la Public IP

Si:

```
curl "http://${PUBLIC_IP}"
```

no responde, revisar:

```
Task RUNNING
Public IP assigned
Security Group
TCP 80 inbound
Subnet route to IGW
Container port 80
NGINX running
```

Verificar Security Group:

```bash
aws ec2 describe-security-groups \
  --profile aws-lab \
  --group-ids "${SECURITY_GROUP_ID}" \
  --region "${AWS_REGION}"
```

## 48. Troubleshooting — Service no alcanza estabilidad

Consultar:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}"
```

Inspeccionar especialmente:

```
events
deployments
runningCount
pendingCount
```

Los eventos ECS suelen proporcionar la primera pista del problema.

## 49. Evidencia del milestone

Registrar:

```
Milestone:
M4 — Deployment manual en Amazon ECS + AWS Fargate

Status:
PASS / FAIL

AWS:
- Profile: aws-lab
- Region:
- Account ID:

ECR:
- Repository:
- Tag: m3-v1
- Expected digest:

ECS:
- Cluster:
- Service:
- Task Definition:
- Revision:
- Task ARN:
- Running image digest:

Fargate:
- Platform:
- Architecture:
- CPU:
- Memory:

Networking:
- VPC:
- Subnet:
- Security Group:
- ENI:
- Public IP:

Validation:
- Service stable:
- Running count:
- GET /:
- Docusaurus route:
- Digest comparison:

Evidence:
- describe-services:
- describe-tasks:
- curl:
- Browser screenshot:
- ECS events:

Issues found:
- Ninguno / descripción

Root cause:
- N/A / descripción

Resolution:
- N/A / descripción
```

50. Checklist final de M4

```
M4 — Deployment manual en ECS + Fargate

Prerequisites:

[ ] M3 completado
[ ] m3-v1 existe en ECR
[ ] OCI Image Manifest verificado
[ ] Digest ECR registrado

ECS:

[ ] ECS Cluster creado
[ ] Cluster ACTIVE
[ ] ecsTaskExecutionRole creado
[ ] AmazonECSTaskExecutionRolePolicy asociada
[ ] Task Definition registrada
[ ] networkMode = awsvpc
[ ] requiresCompatibilities = FARGATE
[ ] CPU = 256
[ ] Memory = 512
[ ] OS = LINUX
[ ] Architecture = X86_64
[ ] containerPort = 80

Networking:

[ ] VPC identificada
[ ] Public subnet identificada
[ ] Internet Gateway route verificada
[ ] Security Group creado
[ ] TCP 80 permitido
[ ] assignPublicIp = ENABLED

Service:

[ ] ECS Service creado
[ ] desiredCount = 1
[ ] runningCount = 1
[ ] pendingCount = 0
[ ] Service stable

Application:

[ ] Task RUNNING
[ ] ENI identificada
[ ] Public IP identificada
[ ] GET / devuelve HTTP 200
[ ] Docusaurus carga correctamente
[ ] Rutas funcionan

Traceability:

[ ] Running image URI verificada
[ ] Running image digest obtenido
[ ] ECR digest = Fargate digest
```

Si todas las validaciones son correctas:

```
M4 STATUS: PASS
```

## 51. Qué demostramos en M4

Hasta M3 teníamos:

```
Source
  │
  ▼
Docker
  │
  ▼
Amazon ECR
```

M4 agrega:

```
Amazon ECR
      │
      ▼
Task Definition
      │
      ▼
ECS Service
      │
      ▼
Fargate Task
      │
      ▼
Running Container
      │
      ▼
HTTP
```

Por primera vez hemos pasado de:

```
Artifact
```

a:

```
Workload
```

## 52. Separación conceptual importante

M3:

```
Image Published
```

M4:

```
Image Executed
```

Esto significa:

```
Amazon ECR
     │
     ▼
Stores Artifact
```

mientras:

```
Amazon ECS
     │
     ▼
Manages Desired State
```

y:

```
AWS Fargate
     │
     ▼
Runs the Task
```

## 53. Recursos que conservaremos

No eliminaremos todavía:

```
ECR Repository
m3-v1
ECS Cluster
Task Definition
ECS Service
Security Group
Execution Role
```

porque serán utilizados durante:

```
M5 — Observabilidad y troubleshooting
```

M5 partirá del servicio funcionando correctamente.

## 54. Costos y duración del laboratorio

A diferencia de ECR por sí solo, una Fargate Task ejecutándose consume recursos de cómputo.

Por ello, si se realiza una pausa prolongada antes de M5, podemos reducir temporalmente el servicio:

```bash
aws ecs update-service \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --desired-count 0 \
  --region "${AWS_REGION}"
```

Esto detendrá las Tasks administradas por el Service.

Cuando continuemos:

```bash
aws ecs update-service \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --desired-count 1 \
  --region "${AWS_REGION}"
```

Esperar:

```bash
aws ecs wait services-stable \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}"
```



Para comprobar el estado de nuestras tareas, ejecutamos,

````bash 
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].[status,desiredCount,runningCount,pendingCount]' \
  --output table
````

Si no hay nada corriendo, deberiamos ver algo asi,

````markdown
------------------
|DescribeServices|
+----------------+
|  ACTIVE        |
|  0             |
|  0             |
|  0             |
+----------------+

````





## 55. Commit del milestone

Registrar los archivos creados para M4, especialmente:

```
task-definition.json
ecs-tasks-trust-policy.json
M4 documentation
```

Revisar:

```bash
git status
```

Agregar:

```bash
git add .
```

Commit sugerido:

```
git commit -m "docs: add ECS Fargate deployment milestone"
```

Publicar:

```
git push
```



## 56. Preparación para M5

El siguiente milestone será:

```
M5 — Observabilidad y troubleshooting
```

Partiremos de:

```
ECS Service
     │
     ▼
Fargate Task
     │
     ▼
Docusaurus + NGINX
     │
     ▼
HTTP 200
```

y agregaremos:

```
Fargate Task
     │
     ├── ECS Events
     ├── Task State
     ├── Failure Reasons
     └── Container Logs
              │
              ▼
       Amazon CloudWatch
```



También introduciremos deliberadamente uno o más fallos para practicar:

```
Observe
   │
   ▼
Diagnose
   │
   ▼
Correct
   │
   ▼
Verify
```



## Criterio de salida

M4 puede considerarse cerrado cuando:

> Amazon ECS mantiene una Fargate Task ejecutando `lab04-docusaurus:m3-v1`, la aplicación Docusaurus es accesible remotamente mediante HTTP, la Task utiliza networking `awsvpc` con una ENI propia y el digest de la imagen ejecutada coincide con el digest registrado previamente en Amazon ECR.

```
M4 STATUS: PASS
```



# Notes



Para una pausa, **no necesitas destruir M4**. Lo más limpio es “apagar” el cómputo de Fargate dejando el ECS Service en `desiredCount = 0`.

Ejecuta:

```bash
aws ecs update-service \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --desired-count 0 \
  --region "${AWS_REGION}"
```

ECS reducirá el número deseado de tasks a cero; al no quedar Fargate Tasks ejecutándose, dejas de consumir el cómputo de esas tasks. AWS define `desiredCount` justamente como el número de instancias de la task que el servicio debe mantener, y permite reducirlo a cero. [AWS Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service_definition_parameters.html?utm_source=chatgpt.com)

Después puedes comprobarlo con:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].[status,desiredCount,runningCount,pendingCount]' \
  --output table
```

Quieres llegar a algo equivalente a:

```markdown
------------------
|DescribeServices|
+----------------+
|  ACTIVE        |
|  0             |
|  0             |
|  0             |
+----------------+

```

Yo **conservaría** estos recursos hasta la siguiente practica despues de la pausa:

```
ECS Cluster
ECS Service
Task Definitions
Amazon ECR repository
m3-v1 / imágenes posteriores
Security Group
IAM Execution Role
VPC / default subnet
```

El cluster, las definiciones y el service pueden permanecer como configuración. ECR sí puede seguir teniendo un pequeño costo por almacenamiento de imágenes, pero para un laboratorio con una o pocas imágenes suele ser mucho más razonable conservarlo que desmontar y reconstruir todo. El componente que más nos interesa detener durante la pausa es la **Fargate Task**.

Además, como no creamos todavía un ALB en M4, no tenemos que preocuparnos por un Load Balancer permaneciendo aprovisionado durante la noche. Eso es una ventaja de la arquitectura simple que usamos en este milestone.

Mañana reanudas simplemente con:

```bash
aws ecs update-service \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --desired-count 1 \
  --region "${AWS_REGION}"
```

Luego:

```bash
aws ecs wait services-stable \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}"
```

y compruebas:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].[status,desiredCount,runningCount,pendingCount]' \
  --output table
```

esperando:

```
ACTIVE
1
1
0
```

Hay un detalle importante: al arrancar una **nueva Fargate Task**, recibirá una nueva ENI y probablemente una nueva public IP. Por eso mañana tendrás que repetir la parte de M4 donde obtuvimos:

```
Task ARN
   ↓
ENI
   ↓
Public IP
```

No confíes en la IP que tenías hoy.

Así que **sí se puede “pausar” de forma práctica**: no pausamos el cluster como una VM, sino que escalamos el servicio a cero. Es exactamente lo que yo haría antes de dejar el laboratorio por hoy.

Después de volver a levantar el servicio con `desired-count 1`, puedes recuperar **Task ARN → ENI → Public IP** en ese orden.

Primero asegúrate de que el servicio esté estable:

```bash
aws ecs wait services-stable \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}"
```

Luego obtén la Task ARN activa:

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

Verifica:

```bash
echo "${TASK_ARN}"
```

Deberías obtener algo similar a:

```bash
arn:aws:ecs:us-east-1:123456789012:task/lab04-cluster/xxxxxxxx
```

Ahora, a partir de esa Task, obtén la ENI:

```bash
export ENI_ID=$(aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" \
  --output text)
```

Verifica:

```bash
echo "${ENI_ID}"
```

Esperas algo como:

```bash
eni-0123456789abcdef0
```

Después usa la ENI para recuperar la Public IP:

```bash
export PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --profile aws-lab \
  --network-interface-ids "${ENI_ID}" \
  --region "${AWS_REGION}" \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text)
```

Verifica:

```bash
echo "${PUBLIC_IP}"
```

Y finalmente prueba la aplicación:

```bash
curl -I "http://${PUBLIC_IP}"
```

Esperamos:

```bash
HTTP/1.1 200 OK
Server: nginx
```

El flujo completo queda así:

```bash
ECS Service
    ↓
Running Task
    ↓
Task ARN
    ↓
ENI
    ↓
Public IP
    ↓
HTTP
```

Si quieres hacerlo de forma compacta, puedes ejecutar todo junto:

```bash
export TASK_ARN=$(aws ecs list-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service-name "${ECS_SERVICE}" \
  --desired-status RUNNING \
  --region "${AWS_REGION}" \
  --query 'taskArns[0]' \
  --output text)

export ENI_ID=$(aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" \
  --output text)

export PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --profile aws-lab \
  --network-interface-ids "${ENI_ID}" \
  --region "${AWS_REGION}" \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text)

echo "TASK_ARN=${TASK_ARN}"
echo "ENI_ID=${ENI_ID}"
echo "PUBLIC_IP=${PUBLIC_IP}"
```

Eso te deja listo para continuar con M5.