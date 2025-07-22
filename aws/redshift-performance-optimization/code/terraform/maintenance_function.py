"""
AWS Lambda function for automated Redshift maintenance tasks.
This function performs VACUUM and ANALYZE operations on tables that meet specific criteria.
"""

import json
import boto3
import psycopg2
import os
import logging
from typing import Dict, List, Tuple, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_redshift_credentials() -> Dict[str, str]:
    """
    Retrieve Redshift credentials from AWS Secrets Manager.
    
    Returns:
        Dict containing database connection parameters
    """
    secret_arn = os.environ['SECRET_ARN']
    region = os.environ['AWS_REGION']
    
    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region
    )
    
    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_arn)
        secret = json.loads(get_secret_value_response['SecretString'])
        return secret
    except Exception as e:
        logger.error(f"Error retrieving secret: {str(e)}")
        raise

def get_database_connection(credentials: Dict[str, str]) -> psycopg2.extensions.connection:
    """
    Establish connection to Redshift database.
    
    Args:
        credentials: Database connection parameters
        
    Returns:
        psycopg2 connection object
    """
    try:
        conn = psycopg2.connect(
            host=credentials['endpoint'],
            database=credentials['database'],
            user=credentials['username'],
            password=credentials['password'],
            port=int(credentials['port'])
        )
        conn.autocommit = True  # Enable autocommit for DDL operations
        return conn
    except Exception as e:
        logger.error(f"Error connecting to database: {str(e)}")
        raise

def get_tables_needing_vacuum(cursor: psycopg2.extensions.cursor) -> List[Tuple[str, float]]:
    """
    Identify tables that need VACUUM operations based on unsorted data percentage.
    
    Args:
        cursor: Database cursor
        
    Returns:
        List of tuples containing (table_name, pct_unsorted)
    """
    vacuum_query = """
        SELECT TRIM(name) as table_name,
               unsorted/DECODE(rows,0,1,rows)::FLOAT * 100 as pct_unsorted
        FROM stv_tbl_perm
        WHERE unsorted > 0 
          AND rows > 1000  -- Only consider tables with significant data
          AND TRIM(name) NOT LIKE 'temp_%'  -- Exclude temporary tables
        ORDER BY pct_unsorted DESC
        LIMIT 10;  -- Limit to top 10 tables to avoid long maintenance windows
    """
    
    try:
        cursor.execute(vacuum_query)
        return cursor.fetchall()
    except Exception as e:
        logger.error(f"Error querying tables for VACUUM: {str(e)}")
        raise

def get_table_statistics(cursor: psycopg2.extensions.cursor) -> List[Tuple[str, int]]:
    """
    Get tables that might need ANALYZE based on modification patterns.
    
    Args:
        cursor: Database cursor
        
    Returns:
        List of tuples containing (table_name, estimated_rows)
    """
    analyze_query = """
        SELECT TRIM(name) as table_name,
               tbl_rows
        FROM stv_tbl_perm
        WHERE tbl_rows > 100  -- Only analyze tables with data
          AND TRIM(name) NOT LIKE 'temp_%'  -- Exclude temporary tables
          AND TRIM(name) NOT LIKE 'pg_%'    -- Exclude system tables
        ORDER BY tbl_rows DESC
        LIMIT 15;  -- Analyze top 15 tables by row count
    """
    
    try:
        cursor.execute(analyze_query)
        return cursor.fetchall()
    except Exception as e:
        logger.error(f"Error querying tables for ANALYZE: {str(e)}")
        raise

def perform_vacuum_operation(cursor: psycopg2.extensions.cursor, table_name: str, pct_unsorted: float) -> bool:
    """
    Perform VACUUM operation on a specific table.
    
    Args:
        cursor: Database cursor
        table_name: Name of the table to vacuum
        pct_unsorted: Percentage of unsorted data
        
    Returns:
        True if successful, False otherwise
    """
    try:
        # Only VACUUM if more than 10% unsorted to avoid unnecessary operations
        if pct_unsorted > 10:
            logger.info(f"Starting VACUUM on table: {table_name} ({pct_unsorted:.1f}% unsorted)")
            
            # Use VACUUM REINDEX for heavily unsorted tables, regular VACUUM for others
            if pct_unsorted > 50:
                vacuum_command = f"VACUUM REINDEX {table_name};"
                operation_type = "VACUUM REINDEX"
            else:
                vacuum_command = f"VACUUM {table_name};"
                operation_type = "VACUUM"
            
            cursor.execute(vacuum_command)
            logger.info(f"Completed {operation_type} on table: {table_name}")
            return True
        else:
            logger.info(f"Skipping VACUUM on table: {table_name} (only {pct_unsorted:.1f}% unsorted)")
            return False
    except Exception as e:
        logger.error(f"Error performing VACUUM on table {table_name}: {str(e)}")
        return False

def perform_analyze_operation(cursor: psycopg2.extensions.cursor, table_name: str) -> bool:
    """
    Perform ANALYZE operation on a specific table.
    
    Args:
        cursor: Database cursor
        table_name: Name of the table to analyze
        
    Returns:
        True if successful, False otherwise
    """
    try:
        logger.info(f"Starting ANALYZE on table: {table_name}")
        analyze_command = f"ANALYZE {table_name};"
        cursor.execute(analyze_command)
        logger.info(f"Completed ANALYZE on table: {table_name}")
        return True
    except Exception as e:
        logger.error(f"Error performing ANALYZE on table {table_name}: {str(e)}")
        return False

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for Redshift maintenance tasks.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with status and results
    """
    logger.info("Starting Redshift maintenance tasks")
    
    try:
        # Get database credentials
        credentials = get_redshift_credentials()
        
        # Establish database connection
        conn = get_database_connection(credentials)
        cursor = conn.cursor()
        
        # Track maintenance operations
        vacuum_operations = 0
        analyze_operations = 0
        failed_operations = 0
        
        # Get tables needing VACUUM
        tables_to_vacuum = get_tables_needing_vacuum(cursor)
        logger.info(f"Found {len(tables_to_vacuum)} tables to evaluate for VACUUM")
        
        # Perform VACUUM operations
        for table_name, pct_unsorted in tables_to_vacuum:
            if perform_vacuum_operation(cursor, table_name, pct_unsorted):
                vacuum_operations += 1
            else:
                failed_operations += 1
        
        # Get tables for ANALYZE (subset of all tables to manage execution time)
        tables_to_analyze = get_table_statistics(cursor)
        logger.info(f"Found {len(tables_to_analyze)} tables to evaluate for ANALYZE")
        
        # Perform ANALYZE operations on a subset to manage execution time
        analyze_limit = min(10, len(tables_to_analyze))  # Limit to 10 tables per run
        for table_name, _ in tables_to_analyze[:analyze_limit]:
            if perform_analyze_operation(cursor, table_name):
                analyze_operations += 1
            else:
                failed_operations += 1
        
        # Close database connection
        cursor.close()
        conn.close()
        
        # Prepare response
        result_message = (
            f"Maintenance completed successfully. "
            f"VACUUM operations: {vacuum_operations}, "
            f"ANALYZE operations: {analyze_operations}, "
            f"Failed operations: {failed_operations}"
        )
        
        logger.info(result_message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': result_message,
                'vacuum_operations': vacuum_operations,
                'analyze_operations': analyze_operations,
                'failed_operations': failed_operations,
                'total_tables_evaluated': len(tables_to_vacuum) + len(tables_to_analyze)
            })
        }
        
    except Exception as e:
        error_message = f"Error during maintenance: {str(e)}"
        logger.error(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message
            })
        }