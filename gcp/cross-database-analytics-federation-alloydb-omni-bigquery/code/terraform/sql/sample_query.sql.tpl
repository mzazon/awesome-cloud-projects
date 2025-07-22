-- Sample federated query to test the analytics federation setup
-- This query demonstrates real-time cross-database analytics capabilities

-- Test basic federation connectivity
SELECT 'Federation connectivity test' as test_name, COUNT(*) as result
FROM EXTERNAL_QUERY(
    '${project_id}.${region}.${connection_id}',
    'SELECT 1 as test_value'
)

UNION ALL

-- Get table information from AlloyDB Omni
SELECT 'AlloyDB table discovery' as test_name, COUNT(DISTINCT table_name) as result
FROM EXTERNAL_QUERY(
    '${project_id}.${region}.${connection_id}',
    'SELECT table_name FROM information_schema.tables WHERE table_schema = ''public'''
)

UNION ALL

-- Test federated analytics view
SELECT 'Customer lifetime value analysis' as test_name, COUNT(*) as result
FROM `${project_id}.analytics_federation.customer_lifetime_value`

ORDER BY test_name;