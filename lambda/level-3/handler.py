import json


def lambda_handler(event, context):
    has_error = event.get("has_error", False)

    if has_error:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "message": "Nivel 3: Sistema bajo mantenimiento, intente más tarde"
            }),
        }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Nivel 3: Operación al mínimo"}),
    }
