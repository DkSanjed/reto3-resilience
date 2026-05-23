"""
Lambda Nivel 2 — Servicio Degradado
───────────────────────────────────
Funciona con un subconjunto de capacidades, priorizando servicios esenciales.
En producción aquí se ejecutarían SOLO: validaciones críticas, operación core.
Se omiten: analytics, recomendaciones, logs verbosos.
"""
import json


def lambda_handler(event, context):
    has_error = event.get("has_error", False)

    if has_error:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Nivel 2: Operación Limitada con Error"}),
        }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Nivel 2: Operación Limitada"}),
    }
