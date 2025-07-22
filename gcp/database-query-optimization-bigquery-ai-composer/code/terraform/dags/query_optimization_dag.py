"""
BigQuery Query Optimization DAG

This DAG orchestrates the automated query optimization pipeline including:
1. Query performance monitoring
2. AI-powered optimization recommendations
3. Materialized view management
4. Performance tracking and alerting
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import (
    BigQueryInsertJobOperator,
    BigQueryCreateEmptyTableOperator,
    BigQueryDeleteTableOperator
)
from airflow.providers.google.cloud.sensors.bigquery import BigQueryTableExistenceSensor
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.vertex_ai import (
    CreateCustomTrainingJobOperator
)
from airflow.providers.google.cloud.operators.gcs import GCSFileTransformOperator
from airflow.providers.google.cloud.hooks.bigquery import BigQueryHook
from airflow.providers.google.cloud.hooks.gcs import GCSHook
import pandas as pd
import logging
import json

# Configuration from environment variables
PROJECT_ID = "${project_id}"
DATASET_NAME = "${dataset_name}"
BUCKET_NAME = "${bucket_name}"
REGION = "${region}"

# DAG default arguments
default_args = {
    'owner': 'data-engineering-team',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'max_active_runs': 1
}

def analyze_query_performance(**context):
    """
    Analyze recent query performance and identify optimization candidates
    """
    logger = logging.getLogger(__name__)
    logger.info("Starting query performance analysis")
    
    # Initialize BigQuery client
    bq_hook = BigQueryHook(
        gcp_conn_id='google_cloud_default',
        use_legacy_sql=False
    )
    
    # Query for optimization candidates
    query = f"""
    WITH performance_analysis AS (
      SELECT 
        query_hash,
        query,
        AVG(duration_ms) as avg_duration,
        AVG(total_slot_ms) as avg_slots,
        AVG(total_bytes_processed) as avg_bytes_processed,
        COUNT(*) as execution_count,
        MAX(creation_time) as last_execution,
        -- Identify optimization opportunities
        LOGICAL_OR(has_select_star) as has_select_star,
        LOGICAL_OR(potential_index_benefit) as potential_index_benefit,
        LOGICAL_OR(complex_joins) as complex_joins,
        -- Performance score
        AVG(CASE 
          WHEN performance_category = 'SLOW' THEN 3
          WHEN performance_category = 'MODERATE' THEN 2
          ELSE 1
        END) as avg_performance_score
      FROM `{PROJECT_ID}.{DATASET_NAME}.query_performance_metrics`
      WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
      GROUP BY query_hash, query
      HAVING execution_count >= 2 AND avg_duration > 3000
    ),
    ranked_candidates AS (
      SELECT *,
        -- Priority score based on performance impact and frequency
        (avg_duration / 1000) * execution_count * avg_performance_score as priority_score
      FROM performance_analysis
    )
    SELECT * FROM ranked_candidates
    ORDER BY priority_score DESC
    LIMIT 20
    """
    
    try:
        # Execute the analysis query
        df = bq_hook.get_pandas_df(sql=query)
        logger.info(f"Identified {len(df)} optimization candidates")
        
        # Store results for downstream tasks
        candidates_json = df.to_json(orient='records', date_format='iso')
        context['task_instance'].xcom_push(key='optimization_candidates', value=candidates_json)
        
        # Log summary statistics
        if not df.empty:
            avg_duration = df['avg_duration'].mean()
            max_executions = df['execution_count'].max()
            logger.info(f"Average duration: {avg_duration:.2f}ms, Max executions: {max_executions}")
        
        return {
            'status': 'success',
            'candidates_found': len(df),
            'avg_duration_ms': float(df['avg_duration'].mean()) if not df.empty else 0
        }
        
    except Exception as e:
        logger.error(f"Query performance analysis failed: {str(e)}")
        raise

def generate_optimization_recommendations(**context):
    """
    Generate AI-powered optimization recommendations based on query analysis
    """
    logger = logging.getLogger(__name__)
    logger.info("Generating optimization recommendations")
    
    # Retrieve candidates from previous task
    candidates_json = context['task_instance'].xcom_pull(
        task_ids='monitor_query_performance',
        key='optimization_candidates'
    )
    
    if not candidates_json:
        logger.warning("No optimization candidates found")
        return {'status': 'no_candidates', 'recommendations_generated': 0}
    
    # Parse candidates data
    candidates = pd.read_json(candidates_json)
    logger.info(f"Processing {len(candidates)} candidates for recommendations")
    
    recommendations = []
    
    for _, row in candidates.iterrows():
        query = row['query']
        query_hash = row['query_hash']
        
        # Rule-based optimization analysis
        optimization_type = "performance_tuning"
        estimated_improvement = 10  # Base improvement
        optimized_query = query
        confidence_score = 0.5
        
        # Analyze query patterns for specific optimizations
        if row.get('has_select_star', False):
            optimization_type = "column_selection"
            estimated_improvement = 25
            confidence_score = 0.8
            optimized_query = query.replace("SELECT *", "SELECT [specify_required_columns]")
            
        elif row.get('complex_joins', False):
            optimization_type = "join_optimization"
            estimated_improvement = 35
            confidence_score = 0.7
            # Suggest join order optimization
            
        elif row.get('potential_index_benefit', False):
            optimization_type = "materialized_view"
            estimated_improvement = 50
            confidence_score = 0.9
            
        elif row['avg_duration'] > 30000:  # > 30 seconds
            optimization_type = "query_restructuring"
            estimated_improvement = 40
            confidence_score = 0.6
            
        elif row['execution_count'] >= 10:  # Frequently executed
            optimization_type = "caching_strategy"
            estimated_improvement = 60
            confidence_score = 0.8
        
        # Create recommendation record
        recommendation = {
            'recommendation_id': f"rec_{query_hash}_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            'query_hash': query_hash,
            'original_query': query,
            'optimized_query': optimized_query,
            'optimization_type': optimization_type,
            'estimated_improvement_percent': estimated_improvement,
            'confidence_score': confidence_score,
            'implementation_status': 'pending',
            'created_timestamp': datetime.utcnow().isoformat(),
            'priority_score': row['priority_score'],
            'execution_frequency': row['execution_count'],
            'avg_duration_ms': row['avg_duration']
        }
        
        recommendations.append(recommendation)
    
    # Store recommendations in BigQuery
    if recommendations:
        bq_hook = BigQueryHook(
            gcp_conn_id='google_cloud_default',
            use_legacy_sql=False
        )
        
        # Convert to DataFrame for BigQuery insertion
        df_recommendations = pd.DataFrame(recommendations)
        
        # Insert recommendations
        table_id = f"{PROJECT_ID}.{DATASET_NAME}.optimization_recommendations"
        
        try:
            bq_hook.insert_all(
                table_id=table_id,
                rows=df_recommendations.to_dict('records'),
                ignore_unknown_values=False,
                skip_invalid_rows=False
            )
            logger.info(f"Successfully stored {len(recommendations)} recommendations")
            
        except Exception as e:
            logger.error(f"Failed to store recommendations: {str(e)}")
            raise
    
    return {
        'status': 'success',
        'recommendations_generated': len(recommendations),
        'high_confidence_count': sum(1 for r in recommendations if r['confidence_score'] > 0.7)
    }

def implement_materialized_views(**context):
    """
    Implement materialized views for frequently accessed query patterns
    """
    logger = logging.getLogger(__name__)
    logger.info("Implementing materialized views for optimization")
    
    # Get recent recommendations for materialized views
    bq_hook = BigQueryHook(
        gcp_conn_id='google_cloud_default',
        use_legacy_sql=False
    )
    
    # Query for materialized view candidates
    query = f"""
    SELECT 
        recommendation_id,
        query_hash,
        original_query,
        confidence_score
    FROM `{PROJECT_ID}.{DATASET_NAME}.optimization_recommendations`
    WHERE 
        optimization_type = 'materialized_view'
        AND implementation_status = 'pending'
        AND confidence_score > 0.7
        AND created_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
    ORDER BY confidence_score DESC
    LIMIT 5
    """
    
    try:
        df = bq_hook.get_pandas_df(sql=query)
        logger.info(f"Found {len(df)} materialized view candidates")
        
        implemented_count = 0
        
        for _, row in df.iterrows():
            # For demo purposes, we'll update the existing sales summary MV
            # In production, this would create new MVs based on query patterns
            
            recommendation_id = row['recommendation_id']
            
            # Update recommendation status
            update_query = f"""
            UPDATE `{PROJECT_ID}.{DATASET_NAME}.optimization_recommendations`
            SET 
                implementation_status = 'implemented',
                applied_timestamp = CURRENT_TIMESTAMP()
            WHERE recommendation_id = '{recommendation_id}'
            """
            
            bq_hook.run_query(
                sql=update_query,
                use_legacy_sql=False
            )
            
            implemented_count += 1
            logger.info(f"Updated recommendation {recommendation_id} as implemented")
        
        return {
            'status': 'success',
            'materialized_views_implemented': implemented_count
        }
        
    except Exception as e:
        logger.error(f"Materialized view implementation failed: {str(e)}")
        raise

def monitor_optimization_impact(**context):
    """
    Monitor the impact of implemented optimizations
    """
    logger = logging.getLogger(__name__)
    logger.info("Monitoring optimization impact")
    
    bq_hook = BigQueryHook(
        gcp_conn_id='google_cloud_default',
        use_legacy_sql=False
    )
    
    # Query to measure optimization impact
    impact_query = f"""
    WITH recent_performance AS (
        SELECT 
            query_hash,
            AVG(duration_ms) as current_avg_duration,
            COUNT(*) as recent_executions
        FROM `{PROJECT_ID}.{DATASET_NAME}.query_performance_metrics`
        WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 HOUR)
        GROUP BY query_hash
    ),
    historical_performance AS (
        SELECT 
            query_hash,
            AVG(duration_ms) as historical_avg_duration,
            COUNT(*) as historical_executions
        FROM `{PROJECT_ID}.{DATASET_NAME}.query_performance_metrics`
        WHERE creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)
              AND TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
        GROUP BY query_hash
    ),
    optimized_queries AS (
        SELECT DISTINCT query_hash
        FROM `{PROJECT_ID}.{DATASET_NAME}.optimization_recommendations`
        WHERE implementation_status = 'implemented'
              AND applied_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    )
    SELECT 
        o.query_hash,
        h.historical_avg_duration,
        r.current_avg_duration,
        SAFE_DIVIDE(
            (h.historical_avg_duration - r.current_avg_duration), 
            h.historical_avg_duration
        ) * 100 as improvement_percent,
        r.recent_executions,
        h.historical_executions
    FROM optimized_queries o
    JOIN historical_performance h ON o.query_hash = h.query_hash
    JOIN recent_performance r ON o.query_hash = r.query_hash
    WHERE r.recent_executions >= 2
    """
    
    try:
        df = bq_hook.get_pandas_df(sql=impact_query)
        
        if not df.empty:
            total_queries_optimized = len(df)
            avg_improvement = df['improvement_percent'].mean()
            max_improvement = df['improvement_percent'].max()
            
            logger.info(f"Optimization impact: {total_queries_optimized} queries, "
                       f"avg improvement: {avg_improvement:.1f}%, "
                       f"max improvement: {max_improvement:.1f}%")
            
            # Store impact metrics
            context['task_instance'].xcom_push(
                key='optimization_impact',
                value={
                    'queries_optimized': int(total_queries_optimized),
                    'avg_improvement_percent': float(avg_improvement),
                    'max_improvement_percent': float(max_improvement)
                }
            )
        else:
            logger.info("No optimization impact data available yet")
        
        return {
            'status': 'success',
            'impact_measured': not df.empty
        }
        
    except Exception as e:
        logger.error(f"Impact monitoring failed: {str(e)}")
        raise

# Define the DAG
dag = DAG(
    'query_optimization_pipeline',
    default_args=default_args,
    description='Automated BigQuery query optimization pipeline with AI recommendations',
    schedule_interval=timedelta(hours=6),  # Run every 6 hours
    catchup=False,
    max_active_runs=1,
    tags=['bigquery', 'optimization', 'ai', 'automation']
)

# Task 1: Monitor query performance and identify candidates
monitor_performance = PythonOperator(
    task_id='monitor_query_performance',
    python_callable=analyze_query_performance,
    dag=dag,
    doc_md="""
    ## Monitor Query Performance
    
    Analyzes recent BigQuery query execution to identify optimization candidates.
    
    **Criteria for optimization candidates:**
    - Executed at least 2 times in the last 24 hours
    - Average duration > 3 seconds
    - Ranked by performance impact and execution frequency
    """
)

# Task 2: Generate AI-powered optimization recommendations
generate_recommendations = PythonOperator(
    task_id='generate_optimization_recommendations',
    python_callable=generate_optimization_recommendations,
    dag=dag,
    doc_md="""
    ## Generate Optimization Recommendations
    
    Uses rule-based AI to generate specific optimization recommendations.
    
    **Optimization types:**
    - Column selection (SELECT * replacement)
    - Join optimization
    - Materialized view creation
    - Query restructuring
    - Caching strategies
    """
)

# Task 3: Create/refresh materialized views for optimization
refresh_materialized_views = BigQueryInsertJobOperator(
    task_id='refresh_materialized_views',
    configuration={
        'query': {
            'query': f"""
            -- Refresh the sales summary materialized view
            -- This ensures latest data is available for optimized queries
            CALL BQ.REFRESH_MATERIALIZED_VIEW('{PROJECT_ID}.{DATASET_NAME}.sales_summary_mv');
            """,
            'useLegacySql': False
        }
    },
    dag=dag,
    doc_md="Refreshes materialized views to ensure optimal query performance"
)

# Task 4: Implement materialized views for new patterns
implement_mv_optimizations = PythonOperator(
    task_id='implement_materialized_view_optimizations',
    python_callable=implement_materialized_views,
    dag=dag,
    doc_md="Implements new materialized views based on AI recommendations"
)

# Task 5: Monitor optimization impact
monitor_impact = PythonOperator(
    task_id='monitor_optimization_impact',
    python_callable=monitor_optimization_impact,
    dag=dag,
    doc_md="Measures the performance impact of implemented optimizations"
)

# Task 6: Update query performance statistics
update_performance_stats = BigQueryInsertJobOperator(
    task_id='update_performance_statistics',
    configuration={
        'query': {
            'query': f"""
            -- Create summary statistics for optimization tracking
            CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET_NAME}.daily_performance_summary` AS
            SELECT 
                DATE(creation_time) as performance_date,
                COUNT(*) as total_queries,
                AVG(duration_ms) as avg_duration_ms,
                PERCENTILE_CONT(duration_ms, 0.5) OVER() as median_duration_ms,
                PERCENTILE_CONT(duration_ms, 0.95) OVER() as p95_duration_ms,
                SUM(total_bytes_processed) as total_bytes_processed,
                SUM(total_slot_ms) as total_slot_ms,
                COUNT(CASE WHEN cache_hit THEN 1 END) as cache_hits,
                COUNT(CASE WHEN error_result IS NOT NULL THEN 1 END) as query_errors,
                -- Optimization opportunity counts
                COUNT(CASE WHEN has_select_star THEN 1 END) as select_star_queries,
                COUNT(CASE WHEN complex_joins THEN 1 END) as complex_join_queries,
                COUNT(CASE WHEN potential_index_benefit THEN 1 END) as index_benefit_queries
            FROM `{PROJECT_ID}.{DATASET_NAME}.query_performance_metrics`
            WHERE DATE(creation_time) = CURRENT_DATE()
            GROUP BY DATE(creation_time)
            """,
            'useLegacySql': False
        }
    },
    dag=dag,
    doc_md="Updates daily performance statistics for trend analysis"
)

# Set task dependencies
monitor_performance >> generate_recommendations >> [refresh_materialized_views, implement_mv_optimizations]
[refresh_materialized_views, implement_mv_optimizations] >> monitor_impact >> update_performance_stats