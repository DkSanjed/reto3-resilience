import json
import os
import time
import logging
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Clientes AWS ──────────────────────────────────────────
dynamodb      = boto3.resource("dynamodb")
lambda_client = boto3.client("lambda")

state_table       = dynamodb.Table(os.environ["STATE_TABLE"])
transitions_table = dynamodb.Table(os.environ["TRANSITIONS_TABLE"])

LEVEL_LAMBDAS = {
    1: os.environ["LEVEL_1_FUNCTION"],
    2: os.environ["LEVEL_2_FUNCTION"],
    3: os.environ["LEVEL_3_FUNCTION"],
}

ERROR_L2         = 5
ERROR_L3         = 10
RECOVERY_STREAK  = 10
METRIC_NAMESPACE = "UltraSeguros/Resilience"

def emit_metrics(level, error_count, success_streak, has_error, transition=False):
    metrics_defs = [
        {"Name": "CurrentLevel",   "Unit": "None"},
        {"Name": "ErrorCount",     "Unit": "Count"},
        {"Name": "SuccessStreak",  "Unit": "Count"},
        {"Name": "ErrorRequests",  "Unit": "Count"},
    ]
    if transition:
        metrics_defs.append({"Name": "LevelTransition", "Unit": "Count"})

    metric_log = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": METRIC_NAMESPACE,
                "Dimensions": [[]],
                "Metrics": metrics_defs,
            }],
        },
        "CurrentLevel":  level,
        "ErrorCount":    error_count,
        "SuccessStreak": success_streak,
        "ErrorRequests": 1 if has_error else 0,
    }
    if transition:
        metric_log["LevelTransition"] = 1

    print(json.dumps(metric_log))

def update_counters_atomic(has_error):

    if has_error:
        update_expr = "ADD error_count :inc SET success_streak = :zero"
        expr_vals   = {":inc": 1, ":zero": 0}
    else:
        update_expr = "ADD success_streak :inc"
        expr_vals   = {":inc": 1}

    response = state_table.update_item(
        Key={"id": "state"},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_vals,
        ReturnValues="ALL_NEW",
    )
    attrs = response["Attributes"]
    return {
        "level":          int(attrs.get("level", 1)),
        "error_count":    int(attrs.get("error_count", 0)),
        "success_streak": int(attrs.get("success_streak", 0)),
    }


def apply_level_transition(state, new_level, reason):
    old_level = state["level"]

    try:
        if new_level < old_level:
            update_expr = "SET #lvl = :new, error_count = :zero, success_streak = :zero"
            expr_vals   = {":new": new_level, ":old": old_level, ":zero": 0}
        else:
            update_expr = "SET #lvl = :new"
            expr_vals   = {":new": new_level, ":old": old_level}

        state_table.update_item(
            Key={"id": "state"},
            UpdateExpression=update_expr,
            ConditionExpression="#lvl = :old",
            ExpressionAttributeNames={"#lvl": "level"},
            ExpressionAttributeValues=expr_vals,
        )

        transitions_table.put_item(Item={
            "pk":          "TRANSITION",
            "timestamp":   datetime.now(timezone.utc).isoformat(),
            "from_level":  old_level,
            "to_level":    new_level,
            "error_count": state["error_count"],
            "reason":      reason,
        })

        logger.info(
            "TRANSICION | Nivel %d → Nivel %d | razón=%s | errores_previos=%d",
            old_level, new_level, reason, state["error_count"]
        )
        return new_level

    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            logger.warning("Transición ignorada: otro request cambió el nivel primero")
            return state["level"]
        raise


def invoke_level_lambda(level, payload):
    function_name = LEVEL_LAMBDAS[level]

    try:
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType="RequestResponse",
            Payload=json.dumps(payload),
        )
        return json.loads(response["Payload"].read())
    except Exception as e:
        logger.error("Fallo invocando Lambda Nivel %d: %s", level, e)
        return {
            "statusCode": 503,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "message": f"Nivel {level}: Servicio temporalmente no disponible (fallback)"
            }),
        }


def lambda_handler(event, context):
    try:
        body      = json.loads(event.get("body") or "{}")
        has_error = bool(body.get("error", False))
    except Exception:
        has_error = False

    state = update_counters_atomic(has_error)

    current_level = state["level"]
    new_level     = current_level

    if has_error:
        if state["error_count"] >= ERROR_L3 and current_level < 3:
            new_level = 3
        elif state["error_count"] >= ERROR_L2 and current_level < 2:
            new_level = 2
    else:
        if state["success_streak"] >= RECOVERY_STREAK and current_level > 1:
            new_level = current_level - 1

    transition_happened = new_level != current_level

    if transition_happened:
        reason        = "degradacion" if new_level > current_level else "recuperacion"
        current_level = apply_level_transition(state, new_level, reason)
        state["level"] = current_level
        if reason == "recuperacion":
            state["error_count"]    = 0
            state["success_streak"] = 0

    emit_metrics(
        level=current_level,
        error_count=state["error_count"],
        success_streak=state["success_streak"],
        has_error=has_error,
        transition=transition_happened,
    )

    return invoke_level_lambda(current_level, {
        "has_error": has_error,
        "level":     current_level,
    })
