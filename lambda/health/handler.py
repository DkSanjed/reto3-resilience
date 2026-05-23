"""
Lambda Health Check — GET /health
─────────────────────────────────
Endpoint de observabilidad para consultar el estado del sistema
sin afectar contadores. Útil para dashboards y monitoreo externo.
"""
import json
import os
import boto3

dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table(os.environ["STATE_TABLE"])


def lambda_handler(event, context):
    response = table.get_item(Key={"id": "state"})
    item     = response.get("Item", {})

    current_level = int(item.get("level", 1))
    status        = "healthy" if current_level == 1 else (
        "degraded" if current_level == 2 else "maintenance"
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "status":           status,
            "current_level":    current_level,
            "error_count":      int(item.get("error_count", 0)),
            "success_streak":   int(item.get("success_streak", 0)),
        }),
    }
