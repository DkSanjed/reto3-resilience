# Reset del estado en DynamoDB entre pruebas de K6
# Ejecutar antes de cada `k6 run reto3.js`

$REGION = "us-east-2"
$TABLE  = "ultraseguros-service-state"

Write-Host "Reseteando estado en DynamoDB..." -ForegroundColor Yellow

aws dynamodb put-item `
  --table-name $TABLE `
  --item '{\"id\":{\"S\":\"state\"},\"level\":{\"N\":\"1\"},\"error_count\":{\"N\":\"0\"},\"success_streak\":{\"N\":\"0\"}}' `
  --region $REGION

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Estado reseteado: Nivel 1, contadores en 0" -ForegroundColor Green
} else {
    Write-Host "✗ Error al resetear estado" -ForegroundColor Red
}
