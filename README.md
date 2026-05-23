# Sistema de Arquitectura Resiliente — UltraSeguros S.A.

> **Diplomado en Arquitectura de Software — Módulo 3**  
> Reto: Diseñando Arquitecturas Resilientes  
> Pontificia Universidad Javeriana Cali

---

## Contexto del negocio

Sistemas UltraSeguros S.A. es una empresa líder que ofrece servicios críticos a múltiples clientes alrededor del mundo, incluyendo gestión de transacciones financieras, análisis de datos en tiempo real y monitoreo de infraestructuras críticas. La continuidad operacional de estos servicios es no negociable: durante picos de tráfico o ante fallos en componentes individuales, la plataforma debe adaptarse, degradarse de forma progresiva y recuperarse automáticamente sin interrupciones significativas.

Esta solución responde a ese desafío diseñando una arquitectura que detecta fallos, transiciona inteligentemente entre niveles de servicio y se recupera de forma autónoma.

---

## Atributo de calidad principal

### Disponibilidad — ISO/IEC 25010:2011

Según la norma **ISO/IEC 25010:2011**, la disponibilidad se define como *"el grado en que un sistema o componente está operativo y accesible cuando se requiere su uso"*. Este atributo pertenece a la característica **Fiabilidad (Reliability)**, junto con la madurez, la tolerancia a fallos y la capacidad de recuperación.

Se priorizó la disponibilidad sobre otros atributos por las siguientes razones:

- Los servicios gestionados (transacciones financieras, monitoreo crítico) no pueden detenerse sin impacto económico directo.
- Los picos de tráfico identificados como problema raíz generan pérdidas millonarias cuando el sistema colapsa completamente.
- Un sistema que degrada progresivamente mantiene valor para el cliente incluso bajo condiciones adversas, mientras que un sistema que falla completamente no genera ningún valor.
- La recuperación automática elimina la dependencia de intervención humana, reduciendo el MTTR (Mean Time To Recovery).

---

## Arquitectura del sistema

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLIENTE (Script K6)                         │
│                   140 iteraciones · 1 VU · 20 req/min              │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ POST /prod/service-api
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      API GATEWAY REST (prod)                        │
│            Throttling: 50 RPS rate · 100 burst limit               │
│         POST /service-api            GET /health                    │
└──────────────┬───────────────────────────────┬──────────────────────┘
               │                               │
               ▼                               ▼
┌──────────────────────────────┐   ┌───────────────────────────────┐
│    LAMBDA ORQUESTADORA       │   │      LAMBDA HEALTH CHECK      │
│                              │   │                               │
│  · Actualización atómica     │   │  · Solo lectura del estado    │
│    de estado (DynamoDB)      │   │  · No afecta contadores       │
│  · Lógica de transición      │◄──┤  · Respuesta en tiempo real  │
│  · Métricas EMF              │   └───────────────────────────────┘
│  · Optimistic locking        │
│  · Graceful fallback         │
└──────┬───────────┬───────────┘
       │           │           │
       ▼           ▼           ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ LAMBDA   │ │ LAMBDA   │ │ LAMBDA   │
│ NIVEL 1  │ │ NIVEL 2  │ │ NIVEL 3  │
│          │ │          │ │          │
│   Full   │ │Degradado │ │  Mínimo  │
│ Servicio │ │ Esencial │ │Mantenim. │
└──────────┘ └──────────┘ └──────────┘
       │           │           │
       └───────────┴───────────┘
                   │ Atomic R/W
                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           DYNAMODB                                  │
│  ┌─────────────────────────┐  ┌─────────────────────────────────┐  │
│  │     service-state       │  │        transitions-log          │  │
│  │                         │  │                                 │  │
│  │  id · level             │  │  pk · timestamp                 │  │
│  │  error_count            │  │  from_level · to_level          │  │
│  │  success_streak         │  │  reason · error_count           │  │
│  └─────────────────────────┘  └─────────────────────────────────┘  │
│                    Encriptación SSE habilitada                      │
└─────────────────────────────────────────────────────────────────────┘
                   │
                   │ EMF Logs
                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         CLOUDWATCH                                  │
│                                                                     │
│  Dashboard (5 widgets)          Alarmas (3)                         │
│  · Nivel actual del servicio    · Sistema en Nivel 3                │
│  · Contadores de error          · Tasa de errores alta              │
│  · Peticiones con error/min     · Errores de runtime               │
│  · Transiciones de nivel        en orquestadora                     │
│  · Invocaciones por Lambda                                          │
│                                                                     │
│  Métricas custom (EMF)                                              │
│  · CurrentLevel · ErrorCount · SuccessStreak                        │
│  · ErrorRequests · LevelTransition                                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Niveles de servicio

| Nivel | Nombre | Descripción | Respuesta exitosa | Respuesta con error |
|-------|--------|-------------|-------------------|---------------------|
| 1 | **Full** | Todas las capacidades activas | `200 — Nivel 1: OK` | `500 — Nivel 1: Operación Full con Error` |
| 2 | **Degradado** | Solo servicios esenciales priorizados | `200 — Nivel 2: Operación Limitada` | `500 — Nivel 2: Operación Limitada con Error` |
| 3 | **Mínimo** | Modo mantenimiento, respuesta informativa | `200 — Nivel 3: Operación al mínimo` | `500 — Nivel 3: Sistema bajo mantenimiento, intente más tarde` |

### Reglas de transición

```
DEGRADACIÓN
  error_count ≥ 5   →  Nivel 1 pasa a Nivel 2
  error_count ≥ 10  →  Nivel 2 pasa a Nivel 3

RECUPERACIÓN
  success_streak ≥ 10  →  sube un nivel + reset de contadores

INICIO
  Nivel 1 (Full) con error_count = 0 y success_streak = 0
```

---

## Tácticas de arquitectura — ISO/IEC 25010:2011

Las tácticas aplicadas se organizan según las características de calidad definidas en la norma ISO/IEC 25010:2011.

### 1. Fiabilidad (Reliability)

#### 1.1 Tolerancia a fallos (Fault Tolerance)

**Degradación progresiva (Graceful Degradation)**
Ante la acumulación de errores, el sistema no colapsa sino que transiciona ordenadamente entre niveles de servicio. El Nivel 3 mantiene al sistema respondiendo con mensajes informativos, preservando la disponibilidad básica incluso en las peores condiciones.

**Aislamiento de componentes (Bulkhead Pattern)**
Cada nivel de servicio se implementa como una Lambda independiente. Un fallo en la Lambda de Nivel 1 no afecta la capacidad de respuesta de las Lambdas de Nivel 2 o Nivel 3. El orquestador actúa como mediador, eligiendo el componente activo según el estado del sistema.

**Fallback graceful**
Si la invocación de una Lambda de nivel falla inesperadamente, el orquestador captura la excepción y devuelve una respuesta HTTP 503 controlada en lugar de propagar el error al cliente. El sistema nunca expone trazas de error internas.

#### 1.2 Capacidad de recuperación (Recoverability)

**Recuperación automática por racha de éxitos**
Cuando los indicadores de salud regresan a niveles aceptables (10 éxitos consecutivos), el sistema asciende un nivel de forma autónoma. La recuperación es gradual: de Nivel 3 a Nivel 2 primero, y de Nivel 2 a Nivel 1 después, evitando oscilaciones bruscas.

**Reset de contadores en transición**
Al recuperarse, los contadores de error y de racha se reinician a cero, garantizando que el nuevo nivel parta de un estado limpio sin arrastrar el historial de la degradación anterior.

#### 1.3 Detección de fallos (Fault Detection)

**Heartbeat — Health Check endpoint**
El endpoint `GET /health` implementa el patrón de heartbeat: permite que sistemas externos (monitores, balanceadores, dashboards) verifiquen el estado del sistema en tiempo real sin alterar su comportamiento. La Lambda de health es de solo lectura e independiente del flujo principal.

**Monitoreo continuo con CloudWatch Alarms**
Tres alarmas detectan condiciones anómalas de forma proactiva:
- Entrada al Nivel 3 (sistema en mantenimiento).
- Tasa de errores superior a 10 por minuto.
- Errores de runtime en la Lambda orquestadora.

### 2. Eficiencia en el rendimiento (Performance Efficiency)

#### 2.1 Comportamiento temporal (Time Behaviour)

**Operaciones atómicas con DynamoDB UpdateItem**
El estado del sistema se actualiza mediante operaciones `ADD` atómicas de DynamoDB, eliminando el patrón read-modify-write que introduce condiciones de carrera bajo concurrencia. Dos invocaciones simultáneas nunca pueden perderse mutuamente sus incrementos de contador.

**Optimistic Locking en cambios de nivel**
Los cambios de nivel utilizan `ConditionExpression` en DynamoDB, implementando control de concurrencia optimista. Si dos invocaciones detectan simultáneamente una transición de nivel, solo una prevalece; la otra se descarta silenciosamente sin error para el cliente.

#### 2.2 Utilización de recursos (Resource Utilisation)

**Métricas EMF (Embedded Metric Format)**
Las métricas custom de CloudWatch se emiten mediante el formato EMF embebido en los logs de Lambda, sin requerir llamadas API adicionales a CloudWatch. Esto elimina latencia extra y reduce el consumo de recursos por invocación.

### 3. Seguridad (Security)

#### 3.1 Mínimo privilegio (Least Privilege)

Cada Lambda posee un rol IAM con permisos exclusivamente necesarios para su función:

| Componente | Permisos DynamoDB | Permisos Lambda | Permisos Logs |
|------------|-------------------|-----------------|---------------|
| Orquestador | GetItem, PutItem, UpdateItem | InvokeFunction | PutLogEvents |
| Lambdas de nivel | Ninguno | Ninguno | PutLogEvents |
| Health Check | GetItem (solo lectura) | Ninguno | PutLogEvents |

#### 3.2 Limitación de exposición (Throttling)

El método `POST /service-api` del API Gateway tiene throttling explícito configurado a 50 solicitudes por segundo con un burst de 100. Esto previene que picos de tráfico maliciosos o accidentales saturen el sistema.

#### 3.3 Confidencialidad de datos (Confidentiality)

La encriptación en reposo (SSE) está habilitada explícitamente en ambas tablas de DynamoDB, garantizando que los datos de estado e historial estén protegidos en el almacenamiento.

### 4. Mantenibilidad (Maintainability)

#### 4.1 Modularidad (Modularity)

La arquitectura separa claramente las responsabilidades: el orquestador maneja la lógica de estado y transición, mientras que cada Lambda de nivel encapsula exclusivamente el comportamiento de su nivel. Modificar el comportamiento de Nivel 2, por ejemplo, no requiere tocar la lógica de transición ni los otros niveles.

#### 4.2 Trazabilidad y auditoría

La tabla `transitions-log` registra cada cambio de nivel con timestamp, nivel origen, nivel destino, razón y métricas al momento de la transición. Esto permite auditar el comportamiento del sistema durante cualquier ejecución de pruebas o incidente en producción.

#### 4.3 Observabilidad activa

Un dashboard de CloudWatch con 5 widgets permite visualizar el comportamiento del sistema en tiempo real durante las pruebas. Todas las métricas clave (nivel actual, contadores, transiciones, invocaciones por Lambda) son observables sin acceder al código fuente.

---

## Decisiones de arquitectura

### ¿Por qué AWS Lambda en lugar de contenedores o servidores?

Lambda ofrece escalabilidad automática sin gestión de infraestructura, facturación por invocación (crítico para Free Tier) y aislamiento natural entre funciones. Para un sistema de 140 solicitudes de prueba, el overhead de un contenedor ECS o una instancia EC2 no se justifica.

### ¿Por qué DynamoDB en lugar de RDS o ElastiCache?

El estado del sistema es un único ítem con operaciones de lectura/escritura atómica. DynamoDB ofrece atomicidad a nivel de ítem mediante `UpdateItem`, latencia de un dígito en milisegundos, y no requiere gestión de conexiones como sí lo haría RDS. Redis/ElastiCache sería más rápido, pero no está en el Free Tier y añade complejidad operacional innecesaria.

### ¿Por qué API Gateway REST en lugar de HTTP API?

La API REST permite configurar throttling a nivel de método, métricas por recurso y stages con configuraciones independientes. Aunque la HTTP API es más económica, la REST API ofrece las capacidades de control necesarias para demostrar tácticas de seguridad (limitación de exposición) en el contexto del reto.

### ¿Por qué el patrón Orquestador + 3 Lambdas de nivel?

Esta separación implementa el patrón Bulkhead: un fallo en un nivel no contamina a los otros. Además, cumple explícitamente el requerimiento del reto de tener *"3 servicios diferentes por nivel de servicio"* con enrutamiento dinámico desde el API Gateway. Una Lambda monolítica habría sido más simple pero arquitectónicamente incorrecta para este escenario.

---

## Componentes de infraestructura

| Componente | Recurso AWS | Propósito |
|------------|-------------|-----------|
| Punto de entrada | API Gateway REST | Recibe todas las solicitudes, aplica throttling |
| Enrutamiento dinámico | Lambda Orquestador | Decide nivel y delega a la Lambda correspondiente |
| Servicio Nivel 1 | Lambda `ultraseguros-level-1` | Responde con capacidades completas |
| Servicio Nivel 2 | Lambda `ultraseguros-level-2` | Responde con capacidades esenciales |
| Servicio Nivel 3 | Lambda `ultraseguros-level-3` | Responde con mensaje de mantenimiento |
| Observabilidad pasiva | Lambda `ultraseguros-health` | Endpoint de salud sin efecto en estado |
| Estado del sistema | DynamoDB `service-state` | Persiste nivel, contadores en tiempo real |
| Historial de eventos | DynamoDB `transitions-log` | Auditoría de cada cambio de nivel |
| Métricas y alertas | CloudWatch Dashboard + Alarms | Visibilidad operacional en tiempo real |
| Infraestructura como código | Terraform | Reproducibilidad y versionado de infraestructura |

---

## Flujo de una solicitud

```
1. El script K6 envía POST /prod/service-api con payload { error: true/false }

2. API Gateway valida el throttling y enruta al Orquestador

3. El Orquestador:
   a. Parsea el campo "error" del body
   b. Ejecuta UpdateItem atómico en DynamoDB (ADD en contadores)
   c. Lee el estado resultante (ReturnValues: ALL_NEW)
   d. Evalúa si hay transición de nivel:
      - Con error: ¿error_count cruzó umbral 5 o 10?
      - Sin error: ¿success_streak alcanzó 10 y nivel > 1?
   e. Si hay transición: aplica ConditionExpression y registra en transitions-log
   f. Emite métricas EMF al log de CloudWatch
   g. Invoca (InvocationType: RequestResponse) la Lambda del nivel actual

4. La Lambda de nivel genera la respuesta HTTP apropiada según el nivel y el flag de error

5. El Orquestador retorna esa respuesta al API Gateway

6. API Gateway entrega la respuesta al cliente (K6)
```

---

## Observabilidad

### Dashboard de CloudWatch

Accesible en: `terraform output dashboard_url`

| Widget | Métrica | Utilidad |
|--------|---------|----------|
| Nivel actual | `CurrentLevel` (Maximum/60s) | Ver en qué nivel está el sistema en cada momento |
| Contadores | `ErrorCount`, `SuccessStreak` (Maximum/60s) | Ver la acumulación de errores y la racha de recuperación |
| Errores por minuto | `ErrorRequests` (Sum/60s) | Correlacionar minutos del script con picos de error |
| Transiciones | `LevelTransition` (Sum/60s) | Confirmar que el sistema cambia de nivel correctamente |
| Invocaciones | `AWS/Lambda Invocations` | Ver qué Lambdas de nivel están siendo más invocadas |

### Consultar historial de transiciones

```bash
aws dynamodb scan \
  --table-name ultraseguros-transitions-log \
  --region us-east-1
```

### Ver logs en vivo

```bash
aws logs tail /aws/lambda/ultraseguros-orchestrator --follow --region us-east-1
```

---

## Guía de despliegue

### Prerrequisitos

- AWS CLI configurado (`aws configure`)
- Terraform >= 1.0 instalado
- Región configurada: `us-east-1`
- K6 instalado (`winget install k6` en Windows)

### Despliegue inicial

```bash
cd reto3-resilience
terraform init
terraform apply
```

Al finalizar, Terraform muestra los outputs necesarios:

```
api_service_url     = "https://xxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/service-api"
api_health_url      = "https://xxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/health"
dashboard_url       = "https://us-east-1.console.aws.amazon.com/cloudwatch/..."
state_table         = "ultraseguros-service-state"
transitions_table   = "ultraseguros-transitions-log"
```

### Actualizar el script K6

Abre `reto3.js` y actualiza la URL del endpoint:

```javascript
const url = 'https://xxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/service-api';
```

### Ejecutar las pruebas

**Paso 1 — Resetear estado antes de cada prueba**

```powershell
.\reset-state.ps1
```

**Paso 2 — Verificar estado inicial**

```bash
curl https://xxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/health
# Esperado: { "status": "healthy", "current_level": 1, "error_count": 0, "success_streak": 0 }
```

**Paso 3 — Ejecutar el script**

```bash
k6 run reto3.js
```

**Paso 4 — Monitorear en tiempo real (terminal paralela)**

```bash
aws logs tail /aws/lambda/ultraseguros-orchestrator --follow --region us-east-1
```

### Destruir la infraestructura

```bash
terraform destroy
```

---

## Análisis de costos — AWS Free Tier

| Servicio | Uso durante prueba | Límite Free Tier | Costo estimado |
|----------|--------------------|------------------|----------------|
| Lambda invocaciones | ~560 (140 × 4 Lambdas) | 1.000.000 / mes | $0.00 |
| Lambda cómputo | < 1 GB-segundo | 400.000 GB-s / mes | $0.00 |
| API Gateway requests | ~140 | 1.000.000 / mes | $0.00 |
| DynamoDB operaciones | ~280 R/W | 25 WCU/RCU | $0.00 |
| CloudWatch métricas | 5 custom | 10 métricas gratis | $0.00 |
| CloudWatch dashboard | 1 | 3 dashboards gratis | $0.00 |
| CloudWatch alarmas | 3 | 10 alarmas gratis | $0.00 |
| CloudWatch logs | < 50 MB | 5 GB / mes | $0.00 |
| **Total estimado** | | | **$0.00** |

---

## Infraestructura como código

Toda la infraestructura está definida en Terraform, organizada por responsabilidad:

```
reto3-resilience/
├── main.tf            # Provider AWS y locals
├── variables.tf       # Parámetros configurables (región, nombres)
├── outputs.tf         # URLs y comandos útiles post-despliegue
├── dynamodb.tf        # Tablas de estado e historial
├── iam.tf             # Roles y políticas con mínimo privilegio
├── lambdas.tf         # 5 funciones Lambda + log groups
├── api-gateway.tf     # REST API, recursos, métodos y throttling
├── observability.tf   # Dashboard y alarmas de CloudWatch
├── reset-state.ps1    # Script de reset entre pruebas (Windows)
└── lambda/
    ├── orchestrator/  # Lógica de estado y transición
    ├── level-1/       # Servicio Full
    ├── level-2/       # Servicio Degradado
    ├── level-3/       # Servicio Mínimo
    └── health/        # Health check de solo lectura
```

---

*Sistemas UltraSeguros S.A. — Arquitectura Resiliente sobre AWS*  
*Módulo 3 · Diplomado en Arquitectura de Software · Pontificia Universidad Javeriana Cali*
