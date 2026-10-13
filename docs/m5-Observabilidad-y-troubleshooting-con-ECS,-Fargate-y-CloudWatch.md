---
sidebar_position: 5
title: "M5 — Observabilidad y troubleshooting con ECS, Fargate y CloudWatch"
description: "Incorporación de observabilidad al servicio Docusaurus desplegado en Amazon ECS/Fargate mediante CloudWatch Logs, ECS Events, inspección de Tasks y fallos controlados."
tags:
  - aws
  - amazon-ecs
  - fargate
  - cloudwatch
  - amazon-ecr
  - observability
  - troubleshooting
  - nginx
  - docusaurus
  - devops
  - lab04
---

# M5 — Observabilidad y troubleshooting con ECS, Fargate y CloudWatch



## Objetivo

Incorporar observabilidad al servicio Docusaurus desplegado en **M4** y practicar el diagnóstico de comportamiento normal y fallos controlados utilizando:

- Amazon ECS Events.
- Estado de ECS Tasks.
- Amazon CloudWatch Logs.
- Logs de NGINX.
- `describe-services`.
- `describe-tasks`.
- `aws logs`.
- Un fallo controlado de `ImagePull`.

Hasta M4 demostramos:

```text
Amazon ECR
      │
      ▼
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

En M5 extenderemos este flujo:

```text
Fargate Task
     │
     ├───────────────┐
     │               │
     ▼               ▼
Container Logs    ECS State
     │               │
     ▼               ▼
CloudWatch       ECS Events
     │               │
     └───────┬───────┘
             ▼
        Troubleshooting
```

El criterio principal de salida será:

> **PASS:** los logs de NGINX pueden consultarse desde CloudWatch, los eventos y estados de ECS pueden utilizarse para explicar el comportamiento del servicio y un fallo controlado de image pull puede diagnosticarse correctamente sin afectar el servicio estable.

---

## Alcance

M5 introduce:

- CloudWatch Log Groups.
- Log retention.
- `awslogs` como log driver.
- CloudWatch Log Streams.
- `aws logs tail`.
- Logs de acceso HTTP de NGINX.
- ECS Service Events.
- ECS Task state.
- `stoppedReason`.
- Container failure reason.
- Distinción entre logs de aplicación y diagnósticos de plataforma.
- Fallo controlado mediante imagen inexistente.
- Inspección de una Task fallida.

M5 no incluye todavía:

```text
GitHub Actions
AWS OIDC
Automated CI/CD
Production Load Balancer
HTTPS
Formal rollback exercise
```

El rollback completo será estudiado durante **M7**.

---

## 1. Estado inicial

M4 debe estar completado.

El punto de partida esperado es:

```text
Amazon ECR
      │
      ▼
Versioned Image
      │
      ▼
ECS Task Definition
      │
      ▼
ECS Service
      │
      ▼
Fargate Task
      │
      ▼
RUNNING
      │
      ▼
HTTP 200
```

Verificar el servicio:

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
---------------------------------------------------------------------------
|                            DescribeServices                             |
+-------------------------------------------------------------------------+
|  ACTIVE                                                                 |
|  1                                                                      |
|  1                                                                      |
|  0                                                                      |
|  arn:aws:ecs:us-east-1:565866186032:task-definition/lab04-docusaurus:2  |
+-------------------------------------------------------------------------+
```

---

## 2. Variables del milestone

Si abrimos una nueva sesión de terminal, definir nuevamente las variables principales:

```bash
export AWS_REGION="us-east-1"
export ECS_CLUSTER="lab04-cluster"
export ECS_SERVICE="lab04-service"
export TASK_FAMILY="lab04-docusaurus"
export CONTAINER_NAME="lab04-docusaurus"
export ECR_REPOSITORY="lab04-docusaurus"
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
```

```bash
export ECR_REPOSITORY_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}"
```

Definir el Log Group:

```bash
export LOG_GROUP="/ecs/lab04-docusaurus"
```

Verificar:

```bash
echo "AWS_REGION=${AWS_REGION}"
echo "ECS_CLUSTER=${ECS_CLUSTER}"
echo "ECS_SERVICE=${ECS_SERVICE}"
echo "LOG_GROUP=${LOG_GROUP}"
```

---

## 3. Identificar la versión actualmente desplegada

Antes de modificar la Task Definition debemos conocer qué revisión utiliza actualmente el servicio.

Ejecutar:

```bash
export CURRENT_TASK_DEFINITION=$(aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].taskDefinition' \
  --output text)
```

Verificar:

```bash
echo "${CURRENT_TASK_DEFINITION}"
```

Ejemplo:

```text
arn:aws:ecs:us-east-1:565866186032:task-definition/lab04-docusaurus:2
```

Consultar la imagen actual:

```bash
export CURRENT_IMAGE_URI=$(aws ecs describe-task-definition \
  --profile aws-lab \
  --task-definition "${CURRENT_TASK_DEFINITION}" \
  --region "${AWS_REGION}" \
  --query 'taskDefinition.containerDefinitions[0].image' \
  --output text)
```

Verificar:

```bash
echo "${CURRENT_IMAGE_URI}"
```

De esta forma M5 no depende de que la imagen actual sea específicamente:

```text
m3-v1
```

o:

```text
m3-v2
```

Utilizaremos exactamente la versión que ya está ejecutando correctamente el servicio.

---

## 4. Checkpoint 1 — Servicio inicial

Verificar:

```text
[ ] ECS Service está ACTIVE
[ ] desiredCount = 1
[ ] runningCount = 1
[ ] pendingCount = 0
[ ] Task Definition actual identificada
[ ] Imagen actualmente desplegada identificada
```

Resultado esperado:

```text
Checkpoint 1: PASS
```

---

## 5. Dos niveles de observabilidad

Durante este milestone distinguiremos dos fuentes de información.

Application / Container Observability

Nos dice qué sucede **dentro del container**:

```text
NGINX
  │
  ├── HTTP requests
  ├── HTTP status
  ├── access logs
  └── runtime errors
       │
       ▼
CloudWatch Logs
```

### ECS / Platform Observability

Nos dice qué ocurre **alrededor del container**:

```text
Amazon ECS
    │
    ├── Task starting
    ├── Image pull
    ├── Task stopping
    ├── Deployment state
    ├── stoppedReason
    └── Service Events
```

Una distinción fundamental será:

```text
Container never started
        │
        ▼
No application logs
        │
        ▼
Inspect ECS state/events instead
```

---

## 6. Crear CloudWatch Log Group

Crear:

```bash
aws logs create-log-group \
  --profile aws-lab \
  --log-group-name "${LOG_GROUP}" \
  --region "${AWS_REGION}"
```

Si el Log Group ya existe, AWS puede responder:

```text
ResourceAlreadyExistsException
```

En ese caso no es necesario recrearlo.

Verificar:

```bash
aws logs describe-log-groups \
  --profile aws-lab \
  --log-group-name-prefix "${LOG_GROUP}" \
  --region "${AWS_REGION}" \
  --query 'logGroups[*].[logGroupName,retentionInDays,storedBytes]' \
  --output table
```

Con una respuesta similar a:

````markdown
----------------------------------------
|           DescribeLogGroups          |
+------------------------+-------+-----+
|  /ecs/lab04-docusaurus |  None |  0  |
+------------------------+-------+-----+
````



---

## 7. Configurar retención de logs

Para evitar conservar logs indefinidamente durante el laboratorio, configuraremos:

```text
7 days
```

Ejecutar:

```bash
aws logs put-retention-policy \
  --profile aws-lab \
  --log-group-name "${LOG_GROUP}" \
  --retention-in-days 7 \
  --region "${AWS_REGION}"
```

Verificar:

```bash
aws logs describe-log-groups \
  --profile aws-lab \
  --log-group-name-prefix "${LOG_GROUP}" \
  --region "${AWS_REGION}" \
  --query 'logGroups[0].[logGroupName,retentionInDays]' \
  --output table
```

Esperamos:

```markdown
---------------------------
|    DescribeLogGroups    |
+-------------------------+
|  /ecs/lab04-docusaurus  |
|  7                      |
+-------------------------+
```

---

## 8. Checkpoint 2 — CloudWatch Log Group

```text
[ ] Log Group creado
[ ] Nombre = /ecs/lab04-docusaurus
[ ] Retention = 7 days
```

Resultado:

```text
Checkpoint 2: PASS
```

---

## 9. Configurar logs en la Task Definition

Hasta ahora nuestra definición del container puede verse conceptualmente así:

```json
{
  "name": "lab04-docusaurus",
  "image": "...",
  "essential": true,
  "portMappings": [
    {
      "containerPort": 80,
      "protocol": "tcp"
    }
  ]
}
```

Agregaremos:

```json
"logConfiguration": {
  "logDriver": "awslogs",
  "options": {
    "awslogs-group": "/ecs/lab04-docusaurus",
    "awslogs-region": "us-east-1",
    "awslogs-stream-prefix": "ecs"
  }
}
```

La nueva definición conceptual será:

```text
Container stdout/stderr
         │
         ▼
awslogs driver
         │
         ▼
CloudWatch Logs
```

---

## 10. Actualizar `task-definition.json`

Abrir:

```text
task-definition.json
```

Asegurarse de conservar la imagen actualmente desplegada.

Podemos consultarla nuevamente:

```bash
echo "${CURRENT_IMAGE_URI}"
```



El parametro `executionRoleArn` es el mismo **ECS Task Execution Role** que creamos en M4, normalmente llamado:  `ecsTaskExecutionRole`. Puedes obtener su ARN directamente con,

````bash
export ECS_EXECUTION_ROLE_ARN=$(aws iam get-role \
  --profile aws-lab \
  --role-name ecsTaskExecutionRole \
  --query 'Role.Arn' \
  --output text)
  
 echo "${ECS_EXECUTION_ROLE_ARN}"
````

se deberia obtener algo parecido a `arn:aws:iam::123456789012:role/ecsTaskExecutionRole`

Tambien,  puedes comprobar que el role tiene asociada la política correcta con,

````bash
aws iam list-attached-role-policies \
  --profile aws-lab \
  --role-name ecsTaskExecutionRole \
  --output table
````

con un resultado similar a,

````markdown
-------------------------------------------------------------------------------------------
|                                ListAttachedRolePolicies                                 |
+-----------------------------------------------------------------------------------------+
||                                   AttachedPolicies                                    ||
|+------------+--------------------------------------------------------------------------+|
||  PolicyArn |  arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy   ||
||  PolicyName|  AmazonECSTaskExecutionRolePolicy                                        ||
|+------------+--------------------------------------------------------------------------+|

````

Para M5 este role es especialmente importante porque ahora, además de permitir que ECS/Fargate haga pull desde ECR, también permite al runtime enviar los logs del container a CloudWatch mediante `awslogs`. Finalmente, no necesitas crear otro role para M5 y se puede reutilizar el role creado en M4.

La definición debe quedar conceptualmente:

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
      "image": "CURRENT_IMAGE_URI",
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

Reemplazar:

```text
EXECUTION_ROLE_ARN
```

y:

```text
CURRENT_IMAGE_URI
```

por sus valores reales.

---

## 11. Por qué no usamos `awslogs-create-group`

El Log Group ya fue creado explícitamente durante este milestone.

Esto permite separar:

```text
Infrastructure creation
```

de:

```text
Container logging
```

y mantiene claro qué recurso existe antes de arrancar la Task.

El Execution Role únicamente necesitará publicar streams y eventos en el grupo existente.

---

## 12. Registrar nueva revisión

Ejecutar:

```bash
aws ecs register-task-definition \
  --profile aws-lab \
  --cli-input-json file://task-definition.json \
  --region "${AWS_REGION}"
```

Consultar la revisión nueva:

```bash
export LOGGING_TASK_REVISION=$(aws ecs describe-task-definition \
  --profile aws-lab \
  --task-definition "${TASK_FAMILY}" \
  --region "${AWS_REGION}" \
  --query 'taskDefinition.revision' \
  --output text)
 
 # Verificar con,
 echo "${LOGGING_TASK_REVISION}"
```



---

## 13. Verificar la configuración de logging

Ejecutar:

```bash
aws ecs describe-task-definition \
  --profile aws-lab \
  --task-definition "${TASK_FAMILY}:${LOGGING_TASK_REVISION}" \
  --region "${AWS_REGION}" \
  --query 'taskDefinition.containerDefinitions[0].logConfiguration' \
  --output json
```

Esperamos:

```json
{
  "logDriver": "awslogs",
  "options": {
    "awslogs-group": "/ecs/lab04-docusaurus",
    "awslogs-region": "us-east-1",
    "awslogs-stream-prefix": "ecs"
  }
}
```

---

## 14. Checkpoint 3 — Task Definition con observabilidad

```text
[ ] Nueva revisión registrada
[ ] Imagen actual conservada
[ ] logDriver = awslogs
[ ] awslogs-group correcto
[ ] awslogs-region correcto
[ ] awslogs-stream-prefix configurado
```

Resultado:

```text
Checkpoint 3: PASS
```

---

## 15. Actualizar ECS Service

Actualizar:

```bash
aws ecs update-service \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --task-definition "${TASK_FAMILY}:${LOGGING_TASK_REVISION}" \
  --region "${AWS_REGION}"
```

ECS comenzará un nuevo deployment:

```text
Old Task
   │
   ▼
Deployment
   │
   ▼
New Task
   │
   └── awslogs enabled
```

---

## 16. Esperar estabilidad

Ejecutar:

```bash
aws ecs wait services-stable \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}"
```

Verificar:

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

```markdown
---------------------------------------------------------------------------
|                            DescribeServices                             |
+-------------------------------------------------------------------------+
|  ACTIVE                                                                 |
|  1                                                                      |
|  2                                                                      |
|  0                                                                      |
|  arn:aws:ecs:us-east-1:565866186032:task-definition/lab04-docusaurus:3  |
+-------------------------------------------------------------------------+
```

---

## 17. Recuperar Task ARN

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
  
  # Verificar con,
  echo "${TASK_ARN}"
```



---

## 18. Recuperar ENI

Ejecutar:

```bash
export ENI_ID=$(aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" \
  --output text)
 
 # Verificar con
 echo "${ENI_ID}"
```



---

## 19. Recuperar Public IP

Ejecutar:

```bash
export PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --profile aws-lab \
  --network-interface-ids "${ENI_ID}" \
  --region "${AWS_REGION}" \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text)
 
 echo "${PUBLIC_IP}"
```



---

## 20. Validar la aplicación después del deployment

Ejecutar:

```bash
curl -I "http://${PUBLIC_IP}"
```

Esperamos:

```text
HTTP/1.1 200 OK
Server: nginx
```

Probar también una ruta Docusaurus:

```bash
curl -I -L \
  "http://${PUBLIC_IP}/docs/m1-docusaurus-bootstrap"
```

Puede observarse nuevamente:

```text
301
 ↓
200
```

---

## 21. Verificar Log Streams

Después de realizar requests HTTP, consultar:

```bash
aws logs describe-log-streams \
  --profile aws-lab \
  --log-group-name "${LOG_GROUP}" \
  --order-by LastEventTime \
  --descending \
  --region "${AWS_REGION}" \
  --query 'logStreams[*].[logStreamName,lastEventTimestamp]' \
  --output table
```

Deberá existir un stream similar a:

```text
ecs/lab04-docusaurus/<task-id>
```

Conceptualmente:

```text
Log Group
/ecs/lab04-docusaurus
        │
        └── Log Stream
              │
              └── Task
```

Por ejemplo, 

````mark
----------------------------------------------------------------------------
|                            DescribeLogStreams                            |
+---------------------------------------------------------+----------------+
|  ecs/lab04-docusaurus/375d1f447cc84d37b9f36d80a144e1fa  |  1791767071295 |
+---------------------------------------------------------+----------------+
````





## 22. Consultar logs recientes

Ejecutar:

```bash
aws logs tail "${LOG_GROUP}" \
  --profile aws-lab \
  --since 10m \
  --region "${AWS_REGION}"
```

Deberán aparecer solicitudes HTTP de NGINX.

Ejemplo conceptual:

```text
GET / HTTP/1.1 200
GET /docs/m1-docusaurus-bootstrap HTTP/1.1 301
GET /docs/m1-docusaurus-bootstrap/ HTTP/1.1 200
```



## 23. Seguir logs en tiempo real

Abrir una terminal y ejecutar:

```bash
aws logs tail "${LOG_GROUP}" \
  --profile aws-lab \
  --follow \
  --since 1m \
  --region "${AWS_REGION}"
```

En otra terminal:

```bash
curl -I "http://${PUBLIC_IP}"
```

La solicitud debería aparecer casi inmediatamente en CloudWatch Logs.

Detener el seguimiento mediante:

```text
Ctrl+C
```

---

## 24. Checkpoint 4 — Application Logs

```text
[ ] Log Stream existe
[ ] aws logs tail funciona
[ ] GET / aparece en los logs
[ ] Status 200 puede observarse
[ ] Ruta Docusaurus aparece en los logs
[ ] Logs pueden seguirse en tiempo real
```

Resultado:

```text
Checkpoint 4: PASS
```

---

## 25. Generar tráfico para observar diferentes respuestas

Ejecutaremos tres requests.

### Respuesta 200

```bash
curl -I "http://${PUBLIC_IP}"
```

### Redirect 301 → 200

```bash
curl -I -L \
  "http://${PUBLIC_IP}/docs/m1-docusaurus-bootstrap"
```

### Error 404

```bash
curl -I \
  "http://${PUBLIC_IP}/this-page-does-not-exist"
```



## 26. Consultar nuevamente los logs

Ejecutar:

```bash
aws logs tail "${LOG_GROUP}" \
  --profile aws-lab \
  --since 5m \
  --region "${AWS_REGION}"
```

Ahora deberíamos poder relacionar:

```text
HTTP request
    │
    ▼
NGINX
    │
    ▼
HTTP status
    │
    ▼
CloudWatch Log
```

Esto demuestra observabilidad desde el punto de vista de la aplicación.

---

## 27. Consultar ECS Service Events

Ejecutar:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].events[0:10].[createdAt,message]' \
  --output table
```

Los eventos pueden mostrar información como:

```text
Task started
Task stopped
Deployment completed
Service reached steady state
```

Los ECS Service Events complementan los logs del container.

---

## 28. Consultar deployments

Ejecutar:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].deployments[*].[status,taskDefinition,desiredCount,runningCount,pendingCount,rolloutState]' \
  --output table
```

Esperamos encontrar el deployment principal:

```markdown
------------------------------------------------------------------------------------------------------------------
|                                                DescribeServices                                                |
+---------+-------------------------------------------------------------------------+----+----+----+-------------+
|  PRIMARY|  arn:aws:ecs:us-east-1:565866186032:task-definition/lab04-docusaurus:3  |  1 |  1 |  0 |  COMPLETED  |
+---------+-------------------------------------------------------------------------+----+----+----+-------------+

```

---

## 29. Consultar estado de la Task

Ejecutar:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].[lastStatus,desiredStatus,healthStatus,launchType,platformVersion]' \
  --output table
```

El resultado normal debe incluir:

```markdown
---------------
|DescribeTasks|
+-------------+
|  RUNNING    |
|  RUNNING    |
|  UNKNOWN    |
|  FARGATE    |
|  1.4.0      |
+-------------+
```

---

## 30. Tres fuentes de diagnóstico

Hasta ahora tenemos:

```text
CloudWatch Logs
       │
       └── What happened inside the container?

ECS Service Events
       │
       └── What happened to the service?

ECS Task State
       │
       └── What happened to this specific task?
```

La fuente correcta depende del problema.

---

## 31. Fallo controlado

Ahora provocaremos un fallo sin modificar el servicio estable.

El escenario será:

```text
One-off Fargate Task
        │
        ▼
Invalid ECR Tag
        │
        ▼
Image Pull
        │
        X
        │
        ▼
STOPPED
```

El ECS Service principal continuará ejecutándose normalmente.

---

## 32. Por qué utilizamos una Task independiente

No queremos convertir todavía este ejercicio en un rollback del servicio.

Por ello:

```text
ECS Service
    │
    └── stable application
```

permanecerá sin cambios.

El experimento utilizará:

```text
Standalone Task
```

que podremos observar y eliminar independientemente.

Esto mantiene el fallo:

```text
controlled
isolated
reproducible
```

---

## 33. Crear Task Definition defectuosa

Crear:

```text
task-definition-m5-bad-image.json
```

Contenido:

```json
{
  "family": "lab04-diagnostic-bad-image",
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
      "name": "lab04-diagnostic",
      "image": "ECR_REPOSITORY_URI:does-not-exist",
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
          "awslogs-stream-prefix": "diagnostic"
        }
      }
    }
  ]
}
```

Reemplazar:

```text
EXECUTION_ROLE_ARN
```

por el ARN utilizado en M4.

También reemplazar:

```text
ECR_REPOSITORY_URI
```

por:

```bash
echo "${ECR_REPOSITORY_URI}"
```

El tag:

```text
does-not-exist
```

debe permanecer intencionalmente inválido.

---

## 34. Registrar definición defectuosa

Ejecutar:

```bash
aws ecs register-task-definition \
  --profile aws-lab \
  --cli-input-json file://task-definition-m5-bad-image.json \
  --region "${AWS_REGION}"
```

Verificar:

```bash
aws ecs describe-task-definition \
  --profile aws-lab \
  --task-definition lab04-diagnostic-bad-image \
  --region "${AWS_REGION}" \
  --query 'taskDefinition.[family,revision,containerDefinitions[0].image]' \
  --output table
```

---

## 35. Recuperar networking existente

Podemos reutilizar:

```text
SUBNET_ID
SECURITY_GROUP_ID
```

del M4. Esto es,

````bash
# Para obtener VPC ID
export VPC_ID=$(aws ec2 describe-vpcs \
  --profile aws-lab \
  --filters Name=isDefault,Values=true \
  --region "${AWS_REGION}" \
  --query 'Vpcs[0].VpcId' \
  --output text)

# Luego se verifica con,
echo "${VPC_ID}"

# Despues se puede obtener las subnets asociadas,
aws ec2 describe-subnets \
  --profile aws-lab \
  --filters Name=vpc-id,Values="${VPC_ID}" \
  --region "${AWS_REGION}" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table
````

Donde resulta que,

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

y despues, La subnet puede volver a seleccionarse mediante el procedimiento utilizado durante M4.

````bash
export SUBNET_ID="subnet-0f7eb8f3bc2efdb6a" 
````

Tambien para ecuperar el Security Group:

```bash
export SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --profile aws-lab \
  --filters \
    Name=group-name,Values=lab04-fargate-sg \
  --region "${AWS_REGION}" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)
 
# Para verificar con,
echo $SECURITY_GROUP_ID 
```



## 36. Ejecutar la Task defectuosa

Ejecutar:

```bash
export FAILED_TASK_ARN=$(aws ecs run-task \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --task-definition lab04-diagnostic-bad-image \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SECURITY_GROUP_ID}],assignPublicIp=ENABLED}" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].taskArn' \
  --output text)
 
 # Verificar con
 echo "${FAILED_TASK_ARN}"
```

La task intentará:

```text
Start
  │
  ▼
Pull image
  │
  X
Image does not exist
```

---

## 37. Esperar a que la Task se detenga

Ejecutar:

```bash
aws ecs wait tasks-stopped \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${FAILED_TASK_ARN}" \
  --region "${AWS_REGION}"
```

Al igual que otros waiters, puede finalizar sin imprimir salida cuando la condición se cumple.

Verificar:

```bash
echo $?
```

Esperamos:

```text
0
```

---

## 38. Inspeccionar la Task fallida

Ejecutar:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${FAILED_TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].[lastStatus,stopCode,stoppedReason]' \
  --output table
```

Esperamos encontrar información relacionada con el fallo durante el arranque.

---

## 39. Consultar razón del container

Ejecutar:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "${FAILED_TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'tasks[0].containers[0].[name,lastStatus,reason,exitCode]' \
  --output table
```

La causa puede incluir información equivalente a:

```text
CannotPullContainerError
```

o una indicación de que el manifest/tag solicitado no pudo encontrarse.

El texto exacto puede variar.

---

## 40. Diagnóstico del fallo

Nuestro análisis será:

```text
Symptom
   │
   ▼
Task STOPPED
   │
   ▼
Inspect stoppedReason
   │
   ▼
Cannot pull image
   │
   ▼
Inspect requested image
   │
   ▼
Tag does not exist
   │
   ▼
Root Cause identified
```

---

## 41. Verificar que la imagen no existe

Ejecutar:

```bash
aws ecr describe-images \
  --profile aws-lab \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag=does-not-exist \
  --region "${AWS_REGION}"
```

Esperamos que ECR indique que esa imagen/tag no existe. 

````markdown
aws: [ERROR]: An error occurred (ImageNotFoundException) when calling the DescribeImages operation: The image with imageId {imageDigest:'null', imageTag:'does-not-exist'} does not exist within the repository with name 'lab04-docusaurus' in the registry with id '565866186032'
````

Esto confirma la causa raíz.

---

## 42. ¿Por qué CloudWatch puede no contener logs del fallo?

En este experimento el container nunca llegó a iniciar.

El flujo falló antes:

```text
Fargate
   │
   ▼
Pull Image
   │
   X
Container Start
```

Por ello podemos tener:

```text
No NGINX logs
```

aunque exista un fallo real.

Esto demuestra una lección fundamental:

> CloudWatch application logs no siempre son la primera fuente de diagnóstico.

Cuando el container no llega a ejecutarse debemos revisar:

```text
ECS Task state
stoppedReason
container reason
ECS Events
```

---

## 43. Checkpoint 5 — Fallo controlado

```text
[ ] Task independiente creada
[ ] Imagen inexistente utilizada deliberadamente
[ ] Task termina STOPPED
[ ] stoppedReason consultado
[ ] Container reason consultado
[ ] Fallo de image pull identificado
[ ] ECR confirma que el tag no existe
[ ] ECS Service principal sigue estable
```

Resultado:

```text
Checkpoint 5: PASS
```

---

## 44. Confirmar que el servicio principal no fue afectado

Ejecutar:

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

```text
ACTIVE
1
1
0
```

Validar nuevamente:

```bash
curl -I "http://${PUBLIC_IP}"
```

Esperamos:

```text
HTTP/1.1 200 OK
```

El fallo estuvo completamente aislado.

---

## 45. Matriz de diagnóstico

| Síntoma                 | Primera fuente a revisar                     |
| ----------------------- | -------------------------------------------- |
| HTTP 404                | CloudWatch / NGINX access logs               |
| HTTP 500                | Application/container logs                   |
| Task no inicia          | `describe-tasks`                             |
| Image pull falla        | `stoppedReason` / container `reason`         |
| Service reemplaza Tasks | ECS Service Events                           |
| Deployment no termina   | ECS deployments + events                     |
| No existe Public IP     | ENI / networking                             |
| HTTP timeout            | Security Group / subnet / route / Task state |
| Container nunca arrancó | ECS state antes que application logs         |

---

## 46. Modelo mental de observabilidad

Podemos organizar el diagnóstico por capas:

```text
Layer 1
CLIENT
curl / browser
     │
     ▼
HTTP behavior

Layer 2
APPLICATION
NGINX / Docusaurus
     │
     ▼
CloudWatch Logs

Layer 3
CONTAINER
ECS container state
     │
     ▼
reason / exitCode

Layer 4
ORCHESTRATOR
ECS Service
     │
     ▼
events / deployments

Layer 5
INFRASTRUCTURE
Fargate / ENI / VPC / IAM / ECR
```

Un buen diagnóstico comienza identificando:

> ¿En qué capa está ocurriendo el fallo?

---

## 47. Evidencia del milestone

Registrar:

```text
Milestone:
M5 — Observabilidad y troubleshooting

Status:
PASS / FAIL

AWS:
- Profile: aws-lab
- Region:

ECS:
- Cluster:
- Service:
- Task Definition:
- Task Revision:
- Running Task ARN:

CloudWatch:
- Log Group:
- Retention:
- Log Stream:

Networking:
- ENI:
- Public IP:

Application validation:
- GET /:
- Docusaurus route:
- 404 test:

Observability:
- aws logs tail:
- ECS Events:
- Deployment state:
- Task state:

Controlled failure:
- Diagnostic Task Definition:
- Failed Task ARN:
- stopCode:
- stoppedReason:
- container reason:
- Expected root cause:

Evidence:
- CloudWatch logs:
- ECS events:
- describe-tasks:
- HTTP requests:
- Failure diagnosis:

Issues found:
- Ninguno / descripción

Root cause:
- N/A / descripción

Resolution:
- N/A / descripción
```

---

## 48. Checklist final de M5

```text
M5 — Observabilidad y troubleshooting

Prerequisites:

[ ] M4 completado
[ ] ECS Service estable
[ ] Application HTTP 200

CloudWatch:

[ ] Log Group creado
[ ] Retention = 7 days
[ ] awslogs configurado
[ ] Nueva Task Definition registrada
[ ] Service actualizado
[ ] Log Stream creado
[ ] NGINX logs visibles

Application observability:

[ ] HTTP 200 observado
[ ] HTTP 301 → 200 observado
[ ] HTTP 404 observado
[ ] Requests identificables en CloudWatch

ECS observability:

[ ] Service Events consultados
[ ] Deployments consultados
[ ] Running Task inspeccionada
[ ] lastStatus comprendido
[ ] desiredStatus comprendido

Controlled failure:

[ ] Standalone Task utilizada
[ ] Invalid image tag configurado
[ ] Task termina STOPPED
[ ] stoppedReason consultado
[ ] container reason consultado
[ ] Image pull failure identificado
[ ] Root cause confirmada en ECR
[ ] Servicio principal no afectado

Understanding:

[ ] Diferencia entre application logs y platform diagnostics comprendida
[ ] Modelo por capas utilizado para troubleshooting
```

Si todo es correcto:

```text
M5 STATUS: PASS
```

## 49. Qué demostramos en M5

M4 terminó con:

```text
ECS Service
     │
     ▼
Fargate Task
     │
     ▼
HTTP 200
```

M5 agrega:

```text
ECS Service
     │
     ├──────────────┐
     │              │
     ▼              ▼
Fargate Task     ECS Events
     │
     ▼
Container
     │
     ▼
NGINX
     │
     ▼
stdout / stderr
     │
     ▼
CloudWatch Logs
```

También comprobamos:

```text
Failure
   │
   ▼
Observe
   │
   ▼
Locate Layer
   │
   ▼
Inspect Evidence
   │
   ▼
Root Cause
```

---

## 50. Diferencia entre monitoring y troubleshooting

Durante M5 utilizamos observabilidad tanto de forma pasiva como activa.

### Monitoring

```text
System working
      │
      ▼
Observe state
```

Ejemplos:

```text
runningCount = 1
HTTP 200
NGINX access logs
rolloutState = COMPLETED
```

### Troubleshooting

```text
Unexpected behavior
        │
        ▼
Collect evidence
        │
        ▼
Form hypothesis
        │
        ▼
Validate
        │
        ▼
Root cause
```

Ambas habilidades son complementarias.

---

## 51. Hallazgo fundamental de M5

Un error en un workload containerizado puede ocurrir antes de que exista un proceso de aplicación.

Por ejemplo:

```text
Image Pull
   │
   X
NGINX never starts
```

En ese escenario:

```text
CloudWatch Application Logs
          │
          ▼
      No evidence
```

pero:

```text
ECS Task State
      │
      ▼
stoppedReason
      │
      ▼
Root Cause
```

Por tanto:

> La ausencia de application logs también es información útil.

---

## 52. Recursos que conservaremos

No eliminaremos todavía:

```text
Amazon ECR repository
ECS Cluster
ECS Service
Task Definitions
CloudWatch Log Group
Security Group
Execution Role
```

porque serán utilizados en:

```text
M6 — CI/CD con GitHub Actions + AWS OIDC
```

La Task Definition defectuosa:

```text
lab04-diagnostic-bad-image
```

puede conservarse como evidencia o eliminarse posteriormente durante M8.

---

## 53. Pausar el laboratorio

Si se realizará una pausa antes de M6, detener el cómputo Fargate:

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

CloudWatch Log Group y ECR seguirán existiendo, pero no habrá una Fargate Task del servicio consumiendo cómputo.

---

## 54. Reanudar el laboratorio

Para M6:

```bash
aws ecs update-service \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --desired-count 1 \
  --region "${AWS_REGION}"
```

Después:

```bash
aws ecs wait services-stable \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}"
```

Recordar que una nueva Fargate Task tendrá:

```text
New Task ARN
New ENI
New Public IP
```

---

## 55. Commit del milestone

Los nuevos archivos pueden incluir:

```text
task-definition.json
task-definition-m5-bad-image.json
M5 documentation
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

```bash
git commit -m "docs: add ECS observability and troubleshooting milestone"
```

Publicar:

```bash
git push
```

---

## 56. Preparación para M6

El siguiente milestone será:

```text
M6 — CI/CD con GitHub Actions + AWS OIDC
```

Hasta ahora realizamos manualmente:

```text
Source Change
     │
     ▼
Docker Build
     │
     ▼
ECR Push
     │
     ▼
Task Definition Revision
     │
     ▼
ECS Service Update
     │
     ▼
Wait for Stable
     │
     ▼
Verify
```

M6 automatizará precisamente este flujo:

```text
git push
    │
    ▼
GitHub Actions
    │
    ▼
OIDC
    │
    ▼
AWS
    │
    ├── Build
    ├── ECR Push
    ├── Task Definition
    ├── ECS Deploy
    └── Verification
```

La observabilidad construida en M5 será especialmente útil cuando el pipeline automatizado de M6 necesite ser diagnosticado.

---

## Criterio de salida

M5 puede considerarse cerrado cuando:

> El servicio ECS envía correctamente los logs de NGINX a Amazon CloudWatch Logs, el estado y los eventos de ECS pueden utilizarse para observar el workload y un fallo controlado causado por una imagen inexistente puede diagnosticarse mediante `stoppedReason` y la información del container sin afectar el servicio principal.

```text
M5 STATUS: PASS
```

## Troubleshooting

### Troubleshooting — No aparecen logs

Si:

```bash
aws logs tail "${LOG_GROUP}" ...
```

no devuelve información, verificar primero que la Task Definition activa tenga:

```text
logDriver = awslogs
```

Consultar:

```bash
aws ecs describe-task-definition \
  --profile aws-lab \
  --task-definition "${TASK_FAMILY}" \
  --region "${AWS_REGION}" \
  --query 'taskDefinition.containerDefinitions[0].logConfiguration' \
  --output json
```

Después generar tráfico:

```bash
curl -I "http://${PUBLIC_IP}"
```

Y consultar nuevamente:

```bash
aws logs tail "${LOG_GROUP}" \
  --profile aws-lab \
  --since 5m \
  --region "${AWS_REGION}"
```

---

### Troubleshooting — ResourceInitializationError

Si una Task falla con algo relacionado con:

```text
ResourceInitializationError
```

revisar:

```text
Execution Role
CloudWatch permissions
Network connectivity
Log Group existence
ECR connectivity
```

Consultar:

```bash
aws ecs describe-tasks \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --tasks "<TASK_ARN>" \
  --region "${AWS_REGION}"
```

y revisar:

```text
stoppedReason
containers[].reason
```

---

### Troubleshooting — Service no alcanza estabilidad

Consultar eventos:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].events[0:15].[createdAt,message]' \
  --output table
```

También revisar deployments:

```bash
aws ecs describe-services \
  --profile aws-lab \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}" \
  --query 'services[0].deployments' \
  --output json
```

---

### Troubleshooting — Aplicación responde 404

Un:

```text
HTTP 404
```

no significa necesariamente que ECS o Fargate estén fallando.

Si:

```text
Task = RUNNING
NGINX = responding
```

y una ruta concreta devuelve:

```text
404
```

el problema probablemente pertenece al nivel:

```text
Application / routing
```

y no al nivel:

```text
Infrastructure
```

Consultar los logs de NGINX permite verificar exactamente qué URI fue solicitada.

---


---

