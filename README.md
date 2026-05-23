# Reto 3 v2 — Arquitectura Resiliente (UltraSeguros S.A.)

## Arquitectura

```
                          ┌─────────────────────┐
                          │   API Gateway REST  │
                          │  + throttling 50RPS │
                          └──────────┬──────────┘
                                     │
                ┌────────────────────┼─────────────────────┐
                │                                          │
        POST /service-api                          GET /health
                │                                          │
                ▼                                          ▼
   ┌─────────────────────────┐               ┌──────────────────┐
   │   Lambda Orquestador    │               │  Lambda Health   │
   │  ┌──────────────────┐   │               │   (read-only)    │
   │  │ Atomic Updates   │───┼──┐            └──────────────────┘
   │  │ Level Decision   │   │  │
   │  │ EMF Metrics      │   │  │
   │  └──────────────────┘   │  │
   └────────┬────────────────┘  │
            │ invoke             │
            │                    ▼
   ┌────────┼─────────┐    ┌──────────────────────┐
   │        │         │    │      DynamoDB        │
   ▼        ▼         ▼    │ ┌──────────────────┐ │
┌─────┐ ┌─────┐  ┌─────┐   │ │  service-state   │ │
│ N1  │ │ N2  │  │ N3  │   │ │ (estado actual)  │ │
│Full │ │Degr.│  │Mín. │   │ ├──────────────────┤ │
└─────┘ └─────┘  └─────┘   │ │transitions-log   │ │
                           │ │  (historial)     │ │
                           │ └──────────────────┘ │
                           └──────────────────────┘
                                     ▲
                                     │
                           ┌─────────┴──────────┐
                           │   CloudWatch       │
                           │ • Dashboard        │
                           │ • 3 Alarms         │
                           │ • Custom Metrics   │
                           │ • Logs             │
                           └────────────────────┘
```

## Atributo de calidad principal: **Disponibilidad / Resiliencia**

El sistema debe seguir respondiendo incluso bajo fallas. Todas las decisiones
arquitectónicas se justifican contra este atributo.

## Tácticas de arquitectura aplicadas

| Táctica                       | Implementación                                                  |
|-------------------------------|-----------------------------------------------------------------|
| **Degradación progresiva**    | 3 niveles de servicio con transiciones automáticas              |
| **Recuperación automática**   | Subida de nivel tras N éxitos consecutivos                      |
| **Aislamiento (Bulkhead)**    | 3 Lambdas separadas por nivel; un fallo no propaga              |
| **Circuit breaker (lógico)**  | Contadores con thresholds + estados Closed/Open                 |
| **Operaciones atómicas**      | DynamoDB `UpdateItem` con `ADD` — sin race conditions           |
| **Optimistic locking**        | `ConditionExpression` en cambios de nivel                       |
| **Graceful fallback**         | Si la Lambda de nivel falla, orquestador devuelve mensaje 503   |
| **Least privilege (IAM)**     | Cada Lambda tiene SOLO los permisos que necesita                |
| **Throttling**                | API Gateway limita 50 RPS para prevenir abuso                   |
| **Encriptación en reposo**    | DynamoDB SSE habilitado explícitamente                          |
| **Observabilidad activa**     | Dashboard + 3 alarmas + métricas custom + historial             |
| **Auditoría**                 | Tabla `transitions-log` con timestamp y razón de cada cambio    |

## Lógica de transición

| Condición                              | Acción                  |
|----------------------------------------|-------------------------|
| `error_count >= 5`                     | → Nivel 2 (Degradado)   |
| `error_count >= 10`                    | → Nivel 3 (Mínimo)      |
| `success_streak >= 10` y nivel ≥ 2     | → Sube un nivel + reset |

## Despliegue

### Prerequisitos
- AWS CLI configurado (`aws configure`)
- Terraform >= 1.0
- Permisos de IAM, Lambda, API Gateway, DynamoDB, CloudWatch

### Pasos

```bash
cd reto3-v2
terraform init
terraform apply
```

Al final verás los outputs:
- `api_service_url` → pégalo en el script K6
- `api_health_url` → para chequeos manuales con curl
- `dashboard_url` → abrir en navegador para ver métricas en vivo

### Antes de cada ejecución del test

**Windows:**
```powershell
.\reset-state.ps1
```

**Linux/Mac:**
```bash
aws dynamodb put-item \
  --table-name ultraseguros-service-state \
  --item '{"id":{"S":"state"},"level":{"N":"1"},"error_count":{"N":"0"},"success_streak":{"N":"0"}}' \
  --region us-east-2
```

### Ejecutar pruebas

```bash
k6 run reto3.js
```

### Ver logs en vivo

```bash
aws logs tail /aws/lambda/ultraseguros-orchestrator --follow --region us-east-2
```

### Ver historial de transiciones

```bash
aws dynamodb scan --table-name ultraseguros-transitions-log --region us-east-2
```

### Destruir todo

```bash
terraform destroy
```

## Análisis de Free Tier

| Servicio              | Uso esperado     | Free Tier              | Costo  |
|-----------------------|------------------|------------------------|--------|
| Lambda invocaciones   | ~560 (140 × 4)   | 1M/mes                 | $0     |
| API Gateway requests  | ~140             | 1M/mes (primer año)    | $0     |
| DynamoDB on-demand    | ~280 ops         | 25 WCU/RCU provisioned | < $0.01|
| CloudWatch métricas   | 5 custom         | 10 gratis              | $0     |
| CloudWatch dashboards | 1                | 3 gratis               | $0     |
| CloudWatch alarms     | 3                | 10 gratis              | $0     |
| CloudWatch logs       | < 100 MB         | 5 GB/mes               | $0     |

**Costo total estimado: < $0.05 USD**

## Diferencias vs v1

| Aspecto              | v1                            | v2                                  |
|----------------------|-------------------------------|-------------------------------------|
| Lambdas              | 1 (monolítica)                | 5 (orquestador + 3 niveles + health)|
| DynamoDB             | Read-modify-write (race cond.)| Atomic `UpdateItem`                 |
| Historial            | Sin auditoría                 | Tabla `transitions-log`             |
| Métricas             | Solo logs                     | EMF + Dashboard + 3 Alarms          |
| IAM                  | Un solo rol                   | 3 roles con least privilege         |
| Throttling           | Por defecto                   | Explícito 50 RPS, 100 burst         |
| Encriptación         | Por defecto                   | SSE habilitado explícitamente       |
| Health check         | Ausente                       | Endpoint `/health` dedicado         |
| Fallback             | Sin manejo                    | Graceful degradation a 503          |

## Trabajo futuro (producción real)

Estas mejoras quedarían para una versión productiva, fuera del alcance del reto:

- **Multi-región** con Route 53 failover (RTO < 1 min)
- **API Key + Usage Plans** para autenticación de clientes
- **WAF** con reglas anti-DDoS
- **DynamoDB Streams + Lambda** para eventos en tiempo real (notificar a SNS)
- **X-Ray** para tracing distribuido
- **Provisioned Concurrency** para eliminar cold starts
- **Step Functions** para orquestaciones más complejas
- **CI/CD** con CodePipeline + tests automáticos
- **Backend de estado de Terraform** en S3 con bloqueo en DynamoDB
- **DLQ** (SQS) para invocaciones asíncronas
