-- Query Performance Metrics View
-- Creates a view to monitor BigQuery query performance and identify optimization candidates

SELECT 
  job_id,
  query,
  creation_time,
  start_time,
  end_time,
  TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) as duration_ms,
  total_bytes_processed,
  total_bytes_billed,
  total_slot_ms,
  ARRAY_LENGTH(referenced_tables) as table_count,
  statement_type,
  cache_hit,
  error_result,
  -- Calculate query hash for grouping similar queries
  TO_HEX(SHA256(query)) as query_hash,
  -- Performance score calculation
  CASE 
    WHEN TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) > 30000 THEN 'SLOW'
    WHEN TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) > 10000 THEN 'MODERATE'
    ELSE 'FAST'
  END as performance_category,
  -- Optimization opportunity indicators
  CASE 
    WHEN REGEXP_CONTAINS(UPPER(query), r'SELECT \*') THEN TRUE
    ELSE FALSE
  END as has_select_star,
  CASE 
    WHEN REGEXP_CONTAINS(UPPER(query), r'ORDER BY.*LIMIT') AND NOT cache_hit THEN TRUE
    ELSE FALSE
  END as potential_index_benefit,
  CASE 
    WHEN ARRAY_LENGTH(referenced_tables) > 3 THEN TRUE
    ELSE FALSE
  END as complex_joins
FROM `${project_id}.region-${region}.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE 
  creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
  AND statement_type IS NOT NULL
  AND state = 'DONE'
  AND error_result IS NULL