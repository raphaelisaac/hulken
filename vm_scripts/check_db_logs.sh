#!/bin/bash
# Check Airbyte database for job attempt details and connector logs
set -e

CTRL="airbyte-abctl-control-plane"

echo "=== Job 112 (Facebook) attempt details from Airbyte DB ==="
sudo docker exec $CTRL kubectl exec -n airbyte-abctl airbyte-db-0 -- psql -U airbyte -d db-airbyte -t -c "
SELECT a.id, a.status, a.created_at, a.updated_at, a.attempt_number,
  LEFT(a.failure_summary::text, 500) as failure_summary,
  LEFT(a.output::text, 500) as output_summary
FROM attempts a
WHERE a.job_id = 112
ORDER BY a.attempt_number
" 2>/dev/null || echo "DB query failed"

echo ""
echo "=== Job 112 job record ==="
sudo docker exec $CTRL kubectl exec -n airbyte-abctl airbyte-db-0 -- psql -U airbyte -d db-airbyte -t -c "
SELECT id, status, created_at, updated_at,
  LEFT(config::text, 200) as config_preview
FROM jobs
WHERE id = 112
" 2>/dev/null || echo "DB query failed"

echo ""
echo "=== Last 5 Facebook jobs with output stats ==="
sudo docker exec $CTRL kubectl exec -n airbyte-abctl airbyte-db-0 -- psql -U airbyte -d db-airbyte -t -c "
SELECT j.id as job_id, j.status, j.created_at,
  a.output->'sync'->'standardSyncSummary'->>'recordsSynced' as records_synced,
  a.output->'sync'->'standardSyncSummary'->>'status' as sync_status,
  LEFT(a.failure_summary::text, 300) as failure
FROM jobs j
LEFT JOIN attempts a ON a.job_id = j.id
WHERE j.scope = '5558bb48-a4ec-49ba-9e48-b9ca92f3461f'
ORDER BY j.id DESC
LIMIT 5
" 2>/dev/null || echo "DB query failed"

echo ""
echo "=== Stream stats for job 112 ==="
sudo docker exec $CTRL kubectl exec -n airbyte-abctl airbyte-db-0 -- psql -U airbyte -d db-airbyte -t -c "
SELECT
  s.value->>'streamName' as stream_name,
  s.value->'stats'->>'recordsEmitted' as emitted,
  s.value->'stats'->>'recordsCommitted' as committed
FROM attempts a,
  json_array_elements(a.output->'sync'->'streamStats') s
WHERE a.job_id = 112
" 2>/dev/null || echo "Stream stats query failed (might need different JSON path)"

echo ""
echo "=== Check connection stream_stats table ==="
sudo docker exec $CTRL kubectl exec -n airbyte-abctl airbyte-db-0 -- psql -U airbyte -d db-airbyte -t -c "
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name LIKE '%stream%' OR table_name LIKE '%attempt%' OR table_name LIKE '%job%'
ORDER BY 1
" 2>/dev/null || echo "Schema query failed"

echo ""
echo "=== Facebook source connection config (check for token issues) ==="
sudo docker exec $CTRL kubectl exec -n airbyte-abctl airbyte-db-0 -- psql -U airbyte -d db-airbyte -t -c "
SELECT
  LEFT(configuration::text, 100) as config_start,
  LENGTH(configuration::text) as config_length
FROM actor
WHERE actor_definition_id IN (
  SELECT actor_definition_id FROM actor
  WHERE id = '47e47ea7-863f-43ba-9055-240a0b0a9a9f'
)
LIMIT 1
" 2>/dev/null || echo "Config query failed"

echo ""
echo "=== Done ==="
