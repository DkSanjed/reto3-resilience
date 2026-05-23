"""
Lambda Nivel 1 — Servicio Full
──────────────────────────────
Responde con todas las capacidades activas.
En producción aquí se ejecutarían: validaciones completas, analytics,
recomendaciones, logging detallado, etc.
"""
import json


def lambda_handler(event, context):
    has_error = event.get("has_error", False)

    if has_error:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Nivel 1: Operación Full con Error"}),
        }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Nivel 1: OK"}),
    }
