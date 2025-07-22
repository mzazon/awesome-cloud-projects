"""
Database Maintenance Automation Cloud Function

This Cloud Function implements comprehensive database maintenance operations
including query analysis, table optimization, performance monitoring, and
automated reporting for Cloud SQL MySQL instances.

Key Features:
- Slow query analysis and optimization recommendations
- Automated table optimization and maintenance
- Performance metrics collection and reporting
- Cloud Storage integration for audit trails
- Error handling and comprehensive logging

Author: Database Maintenance Automation System
Version: 1.0
"""

import functions_framework
import pymysql
import json
import logging
import os
import traceback
from datetime import datetime, timedelta
from google.cloud import monitoring_v3
from google.cloud import storage
from google.cloud import sql_v1
from typing import Dict, List, Any, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration constants
MAX_SLOW_QUERIES = 10
SLOW_QUERY_THRESHOLD = 2.0  # seconds
CONNECTION_TIMEOUT = 30
QUERY_TIMEOUT = 300


class DatabaseMaintenanceError(Exception):
    """Custom exception for database maintenance operations"""
    pass


class DatabaseConnection:
    """Context manager for database connections with proper cleanup"""
    
    def __init__(self):
        self.connection = None
        
    def __enter__(self):
        """Establish database connection"""
        try:
            # Get connection parameters from environment variables
            connection_params = {
                'host': '127.0.0.1',  # Cloud SQL Proxy endpoint
                'user': os.environ.get('DB_USER'),
                'password': os.environ.get('DB_PASSWORD'),
                'database': os.environ.get('DB_NAME'),
                'unix_socket': f'/cloudsql/{os.environ.get("CONNECTION_NAME")}',
                'connect_timeout': CONNECTION_TIMEOUT,
                'read_timeout': QUERY_TIMEOUT,
                'write_timeout': QUERY_TIMEOUT,
                'charset': 'utf8mb4',
                'autocommit': True
            }
            
            logger.info("Establishing database connection...")
            self.connection = pymysql.connect(**connection_params)
            logger.info("Database connection established successfully")
            return self.connection
            
        except Exception as e:
            logger.error(f"Failed to establish database connection: {e}")
            raise DatabaseMaintenanceError(f"Database connection failed: {e}")
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Close database connection"""
        if self.connection:
            try:
                self.connection.close()
                logger.info("Database connection closed")
            except Exception as e:
                logger.warning(f"Error closing database connection: {e}")


def analyze_slow_queries(connection) -> List[Dict[str, Any]]:
    """
    Analyze slow queries from performance schema
    
    Args:
        connection: MySQL database connection
        
    Returns:
        List of slow query analysis results
    """
    logger.info("Starting slow query analysis...")
    
    try:
        cursor = connection.cursor()
        
        # Query to get slow queries from performance schema
        slow_query_sql = """
        SELECT 
            DIGEST_TEXT as sql_text,
            COUNT_STAR as exec_count,
            ROUND(AVG_TIMER_WAIT/1000000000, 3) as avg_time_seconds,
            ROUND(MAX_TIMER_WAIT/1000000000, 3) as max_time_seconds,
            ROUND(SUM_TIMER_WAIT/1000000000, 3) as total_time_seconds,
            ROUND(SUM_ROWS_EXAMINED/COUNT_STAR) as avg_rows_examined,
            ROUND(SUM_ROWS_SENT/COUNT_STAR) as avg_rows_sent
        FROM performance_schema.events_statements_summary_by_digest 
        WHERE AVG_TIMER_WAIT > %s * 1000000000
        AND DIGEST_TEXT IS NOT NULL
        ORDER BY AVG_TIMER_WAIT DESC 
        LIMIT %s
        """
        
        cursor.execute(slow_query_sql, (SLOW_QUERY_THRESHOLD, MAX_SLOW_QUERIES))
        slow_queries = cursor.fetchall()
        cursor.close()
        
        # Format results
        slow_query_analysis = []
        for query in slow_queries:
            analysis = {
                "query_digest": query[0][:200] + "..." if len(query[0]) > 200 else query[0],
                "execution_count": int(query[1]),
                "avg_time_seconds": float(query[2]),
                "max_time_seconds": float(query[3]),
                "total_time_seconds": float(query[4]),
                "avg_rows_examined": int(query[5]) if query[5] else 0,
                "avg_rows_sent": int(query[6]) if query[6] else 0,
                "optimization_priority": "HIGH" if query[2] > 10 else "MEDIUM" if query[2] > 5 else "LOW"
            }
            slow_query_analysis.append(analysis)
        
        logger.info(f"Found {len(slow_query_analysis)} slow queries requiring attention")
        return slow_query_analysis
        
    except Exception as e:
        logger.error(f"Error analyzing slow queries: {e}")
        raise DatabaseMaintenanceError(f"Slow query analysis failed: {e}")


def optimize_tables(connection) -> List[str]:
    """
    Perform table optimization and maintenance operations
    
    Args:
        connection: MySQL database connection
        
    Returns:
        List of successfully optimized table names
    """
    logger.info("Starting table optimization...")
    
    try:
        cursor = connection.cursor()
        
        # Get list of tables in the current database
        cursor.execute("SHOW TABLES")
        tables = cursor.fetchall()
        
        optimized_tables = []
        optimization_results = []
        
        for table_row in tables:
            table_name = table_row[0]
            
            try:
                logger.info(f"Optimizing table: {table_name}")
                
                # Analyze table for optimization opportunities
                cursor.execute(f"ANALYZE TABLE `{table_name}`")
                analyze_result = cursor.fetchall()
                
                # Optimize table
                cursor.execute(f"OPTIMIZE TABLE `{table_name}`")
                optimize_result = cursor.fetchall()
                
                # Check if optimization was successful
                if optimize_result and optimize_result[0][3] == 'OK':
                    optimized_tables.append(table_name)
                    optimization_results.append({
                        "table": table_name,
                        "status": "SUCCESS",
                        "message": optimize_result[0][3] if optimize_result else "Completed"
                    })
                    logger.info(f"Successfully optimized table: {table_name}")
                else:
                    optimization_results.append({
                        "table": table_name,
                        "status": "WARNING",
                        "message": optimize_result[0][3] if optimize_result else "Unknown result"
                    })
                    logger.warning(f"Table optimization completed with warnings: {table_name}")
                
            except Exception as e:
                error_msg = f"Failed to optimize table {table_name}: {e}"
                logger.warning(error_msg)
                optimization_results.append({
                    "table": table_name,
                    "status": "ERROR",
                    "message": str(e)
                })
        
        cursor.close()
        logger.info(f"Table optimization completed. Successfully optimized {len(optimized_tables)} tables")
        return optimized_tables
        
    except Exception as e:
        logger.error(f"Error during table optimization: {e}")
        raise DatabaseMaintenanceError(f"Table optimization failed: {e}")


def collect_performance_metrics(connection) -> Dict[str, Any]:
    """
    Collect comprehensive database performance metrics
    
    Args:
        connection: MySQL database connection
        
    Returns:
        Dictionary of performance metrics
    """
    logger.info("Collecting performance metrics...")
    
    try:
        cursor = connection.cursor()
        
        # Collect various performance metrics
        metrics = {}
        
        # Connection statistics
        cursor.execute("SHOW STATUS LIKE 'Threads_connected'")
        result = cursor.fetchone()
        metrics['active_connections'] = int(result[1]) if result else 0
        
        cursor.execute("SHOW STATUS LIKE 'Max_used_connections'")
        result = cursor.fetchone()
        metrics['max_used_connections'] = int(result[1]) if result else 0
        
        # Query cache statistics
        cursor.execute("SHOW STATUS LIKE 'Qcache_hits'")
        result = cursor.fetchone()
        metrics['query_cache_hits'] = int(result[1]) if result else 0
        
        cursor.execute("SHOW STATUS LIKE 'Qcache_inserts'")
        result = cursor.fetchone()
        metrics['query_cache_inserts'] = int(result[1]) if result else 0
        
        cursor.execute("SHOW STATUS LIKE 'Qcache_not_cached'")
        result = cursor.fetchone()
        metrics['query_cache_not_cached'] = int(result[1]) if result else 0
        
        # Query statistics
        cursor.execute("SHOW STATUS LIKE 'Questions'")
        result = cursor.fetchone()
        metrics['total_queries'] = int(result[1]) if result else 0
        
        cursor.execute("SHOW STATUS LIKE 'Slow_queries'")
        result = cursor.fetchone()
        metrics['slow_queries_count'] = int(result[1]) if result else 0
        
        # Table statistics
        cursor.execute("SHOW STATUS LIKE 'Table_locks_waited'")
        result = cursor.fetchone()
        metrics['table_locks_waited'] = int(result[1]) if result else 0
        
        cursor.execute("SHOW STATUS LIKE 'Table_locks_immediate'")
        result = cursor.fetchone()
        metrics['table_locks_immediate'] = int(result[1]) if result else 0
        
        # InnoDB statistics
        cursor.execute("SHOW STATUS LIKE 'Innodb_buffer_pool_reads'")
        result = cursor.fetchone()
        metrics['innodb_buffer_pool_reads'] = int(result[1]) if result else 0
        
        cursor.execute("SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests'")
        result = cursor.fetchone()
        metrics['innodb_buffer_pool_read_requests'] = int(result[1]) if result else 0
        
        # Calculate cache hit ratio
        if metrics['query_cache_hits'] + metrics['query_cache_inserts'] > 0:
            metrics['query_cache_hit_ratio'] = round(
                metrics['query_cache_hits'] / (metrics['query_cache_hits'] + metrics['query_cache_inserts']), 4
            )
        else:
            metrics['query_cache_hit_ratio'] = 0
        
        # Calculate InnoDB buffer pool hit ratio
        if metrics['innodb_buffer_pool_read_requests'] > 0:
            metrics['innodb_buffer_pool_hit_ratio'] = round(
                1 - (metrics['innodb_buffer_pool_reads'] / metrics['innodb_buffer_pool_read_requests']), 4
            )
        else:
            metrics['innodb_buffer_pool_hit_ratio'] = 0
        
        # Add timestamp
        metrics['timestamp'] = datetime.now().isoformat()
        metrics['collection_time_utc'] = datetime.utcnow().isoformat()
        
        cursor.close()
        logger.info("Performance metrics collected successfully")
        return metrics
        
    except Exception as e:
        logger.error(f"Error collecting performance metrics: {e}")
        raise DatabaseMaintenanceError(f"Performance metrics collection failed: {e}")


def save_maintenance_report(report_data: Dict[str, Any], bucket_name: str) -> str:
    """
    Save maintenance report to Cloud Storage
    
    Args:
        report_data: Dictionary containing maintenance report data
        bucket_name: Name of the Cloud Storage bucket
        
    Returns:
        Path to the saved report in Cloud Storage
    """
    logger.info("Saving maintenance report to Cloud Storage...")
    
    try:
        # Initialize Cloud Storage client
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        
        # Generate report filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_type = report_data.get('action', 'maintenance')
        blob_name = f"maintenance-reports/{report_type}_report_{timestamp}.json"
        
        # Create blob and upload report data
        blob = bucket.blob(blob_name)
        
        # Add metadata to the blob
        blob.metadata = {
            'report_type': report_type,
            'timestamp': timestamp,
            'source': 'database-maintenance-function',
            'version': '1.0'
        }
        
        # Upload the report as JSON
        blob.upload_from_string(
            json.dumps(report_data, indent=2, default=str),
            content_type='application/json'
        )
        
        logger.info(f"Maintenance report saved successfully: {blob_name}")
        return blob_name
        
    except Exception as e:
        logger.error(f"Error saving maintenance report: {e}")
        raise DatabaseMaintenanceError(f"Report saving failed: {e}")


def send_custom_metric(metric_name: str, value: float, labels: Dict[str, str] = None):
    """
    Send custom metric to Cloud Monitoring
    
    Args:
        metric_name: Name of the custom metric
        value: Metric value
        labels: Optional labels for the metric
    """
    try:
        monitoring_client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{os.environ.get('GOOGLE_CLOUD_PROJECT', 'unknown')}"
        
        # Create time series data
        now = datetime.utcnow()
        interval = monitoring_v3.TimeInterval({
            "end_time": {"seconds": int(now.timestamp())}
        })
        
        point = monitoring_v3.Point({
            "interval": interval,
            "value": {"double_value": value}
        })
        
        # Create time series
        series = monitoring_v3.TimeSeries()
        series.metric.type = f"custom.googleapis.com/database_maintenance/{metric_name}"
        series.resource.type = "global"
        
        # Add labels if provided
        if labels:
            for key, val in labels.items():
                series.metric.labels[key] = val
        
        series.points = [point]
        
        # Write time series
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logger.info(f"Custom metric sent: {metric_name} = {value}")
        
    except Exception as e:
        logger.warning(f"Failed to send custom metric {metric_name}: {e}")


@functions_framework.http
def database_maintenance(request):
    """
    Main Cloud Function entry point for database maintenance operations
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with maintenance results
    """
    start_time = datetime.now()
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        action = request_json.get('action', 'daily_maintenance') if request_json else 'daily_maintenance'
        
        logger.info(f"Starting database maintenance operation: {action}")
        
        # Validate environment variables
        required_env_vars = ['DB_USER', 'DB_NAME', 'DB_PASSWORD', 'BUCKET_NAME', 'CONNECTION_NAME']
        missing_vars = [var for var in required_env_vars if not os.environ.get(var)]
        
        if missing_vars:
            raise DatabaseMaintenanceError(f"Missing required environment variables: {missing_vars}")
        
        # Initialize results
        maintenance_results = {
            "action": action,
            "start_time": start_time.isoformat(),
            "status": "in_progress",
            "results": {}
        }
        
        # Perform maintenance operations based on action type
        with DatabaseConnection() as connection:
            
            if action in ['daily_maintenance', 'full_maintenance']:
                logger.info("Performing full maintenance operations...")
                
                # Analyze slow queries
                slow_queries = analyze_slow_queries(connection)
                maintenance_results["results"]["slow_queries"] = {
                    "count": len(slow_queries),
                    "queries": slow_queries
                }
                
                # Optimize tables
                optimized_tables = optimize_tables(connection)
                maintenance_results["results"]["table_optimization"] = {
                    "optimized_count": len(optimized_tables),
                    "optimized_tables": optimized_tables
                }
                
                # Collect performance metrics
                performance_metrics = collect_performance_metrics(connection)
                maintenance_results["results"]["performance_metrics"] = performance_metrics
                
                # Send custom metrics to Cloud Monitoring
                send_custom_metric("slow_queries_count", len(slow_queries))
                send_custom_metric("optimized_tables_count", len(optimized_tables))
                send_custom_metric("active_connections", performance_metrics.get('active_connections', 0))
                
            elif action == 'performance_monitoring':
                logger.info("Performing performance monitoring...")
                
                # Collect performance metrics only
                performance_metrics = collect_performance_metrics(connection)
                maintenance_results["results"]["performance_metrics"] = performance_metrics
                
                # Send custom metrics to Cloud Monitoring
                send_custom_metric("active_connections", performance_metrics.get('active_connections', 0))
                send_custom_metric("query_cache_hit_ratio", performance_metrics.get('query_cache_hit_ratio', 0))
                
            else:
                raise DatabaseMaintenanceError(f"Unknown action: {action}")
        
        # Calculate execution time
        end_time = datetime.now()
        execution_time = (end_time - start_time).total_seconds()
        
        # Update results
        maintenance_results.update({
            "end_time": end_time.isoformat(),
            "execution_time_seconds": execution_time,
            "status": "completed"
        })
        
        # Save maintenance report to Cloud Storage
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            try:
                report_path = save_maintenance_report(maintenance_results, bucket_name)
                maintenance_results["report_path"] = report_path
            except Exception as e:
                logger.warning(f"Failed to save report to storage: {e}")
                maintenance_results["report_save_error"] = str(e)
        
        logger.info(f"Database maintenance completed successfully in {execution_time:.2f} seconds")
        
        # Send execution time metric
        send_custom_metric("execution_time_seconds", execution_time)
        
        return {
            "status": "success",
            "message": f"Database maintenance completed successfully",
            "execution_time_seconds": execution_time,
            "action": action,
            "results": maintenance_results["results"],
            "report_path": maintenance_results.get("report_path")
        }
        
    except DatabaseMaintenanceError as e:
        logger.error(f"Database maintenance error: {e}")
        return {
            "status": "error",
            "message": str(e),
            "action": action if 'action' in locals() else "unknown",
            "execution_time_seconds": (datetime.now() - start_time).total_seconds()
        }, 500
        
    except Exception as e:
        logger.error(f"Unexpected error during maintenance: {e}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        return {
            "status": "error",
            "message": f"Unexpected error: {str(e)}",
            "action": action if 'action' in locals() else "unknown",
            "execution_time_seconds": (datetime.now() - start_time).total_seconds()
        }, 500