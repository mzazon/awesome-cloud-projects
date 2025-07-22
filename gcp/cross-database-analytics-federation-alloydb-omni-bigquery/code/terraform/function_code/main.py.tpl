import functions_framework
import json
from google.cloud import bigquery
from google.cloud import dataplex_v1
from google.cloud import storage
import logging
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def sync_metadata(request):
    """
    Synchronize metadata between AlloyDB Omni and Dataplex catalog.
    
    This function discovers data sources via federated queries and updates
    the Dataplex catalog with current metadata information.
    """
    try:
        # Get configuration from environment variables or request
        project_id = os.environ.get('PROJECT_ID', '${project_id}')
        region = os.environ.get('REGION', '${region}')
        connection_id = os.environ.get('CONNECTION_ID', '${connection_id}')
        
        # Parse request for additional parameters
        request_json = request.get_json(silent=True)
        if request_json:
            project_id = request_json.get('project_id', project_id)
            connection_id = request_json.get('connection_id', connection_id)
        
        logger.info(f"Starting metadata sync for project: {project_id}, connection: {connection_id}")
        
        # Initialize Google Cloud clients
        bq_client = bigquery.Client(project=project_id)
        storage_client = storage.Client(project=project_id)
        
        # Discover AlloyDB Omni tables via federated query
        logger.info("Discovering tables via federated query...")
        discover_query = f"""
        SELECT 
            table_name,
            column_name,
            data_type,
            is_nullable,
            column_default
        FROM EXTERNAL_QUERY(
            '{project_id}.{region}.{connection_id}',
            '''SELECT 
                table_name,
                column_name,
                data_type,
                is_nullable,
                column_default
            FROM information_schema.columns 
            WHERE table_schema = 'public'
            ORDER BY table_name, ordinal_position'''
        )
        """
        
        # Execute discovery query
        query_job = bq_client.query(discover_query)
        results = query_job.result()
        
        # Process discovery results
        tables_metadata = {}
        for row in results:
            table_name = row.table_name
            if table_name not in tables_metadata:
                tables_metadata[table_name] = {
                    'columns': [],
                    'row_count': 0,
                    'last_updated': None
                }
            
            tables_metadata[table_name]['columns'].append({
                'name': row.column_name,
                'type': row.data_type,
                'nullable': row.is_nullable == 'YES',
                'default': row.column_default
            })
        
        # Get row counts for each discovered table
        logger.info("Getting row counts for discovered tables...")
        for table_name in tables_metadata.keys():
            try:
                count_query = f"""
                SELECT COUNT(*) as row_count
                FROM EXTERNAL_QUERY(
                    '{project_id}.{region}.{connection_id}',
                    'SELECT COUNT(*) FROM {table_name}'
                )
                """
                count_job = bq_client.query(count_query)
                count_result = count_job.result()
                for count_row in count_result:
                    tables_metadata[table_name]['row_count'] = count_row.row_count
                    break
            except Exception as e:
                logger.warning(f"Could not get row count for table {table_name}: {str(e)}")
                tables_metadata[table_name]['row_count'] = -1
        
        # Test federation connectivity
        logger.info("Testing federation connectivity...")
        connectivity_query = f"""
        SELECT 
            'connection_active' as status,
            CURRENT_TIMESTAMP() as test_time
        FROM EXTERNAL_QUERY(
            '{project_id}.{region}.{connection_id}',
            'SELECT 1 as test_value'
        )
        """
        
        connectivity_job = bq_client.query(connectivity_query)
        connectivity_result = connectivity_job.result()
        connection_status = 'active'
        test_time = None
        
        for conn_row in connectivity_result:
            connection_status = conn_row.status
            test_time = conn_row.test_time.isoformat() if conn_row.test_time else None
            break
        
        # Build comprehensive metadata response
        metadata_summary = {
            'federation_status': connection_status,
            'last_sync': test_time,
            'project_id': project_id,
            'connection_id': connection_id,
            'region': region,
            'discovered_tables': tables_metadata,
            'total_tables': len(tables_metadata),
            'total_columns': sum(len(table['columns']) for table in tables_metadata.values()),
            'sync_statistics': {
                'query_execution_time_ms': query_job.ended.timestamp() - query_job.started.timestamp() if query_job.ended and query_job.started else None,
                'bytes_processed': query_job.total_bytes_processed,
                'slot_ms': query_job.slot_millis
            }
        }
        
        # Log success metrics
        logger.info(f"Metadata sync completed successfully:")
        logger.info(f"- Discovered {len(tables_metadata)} tables")
        logger.info(f"- Total columns: {metadata_summary['total_columns']}")
        logger.info(f"- Federation status: {connection_status}")
        
        # Return success response
        return {
            'status': 'success',
            'message': 'Metadata synchronization completed successfully',
            'metadata': metadata_summary,
            'timestamp': test_time
        }, 200
        
    except Exception as e:
        error_message = f"Metadata sync failed: {str(e)}"
        logger.error(error_message)
        
        # Return error response with details
        return {
            'status': 'error',
            'message': error_message,
            'error_type': type(e).__name__,
            'project_id': project_id if 'project_id' in locals() else 'unknown',
            'connection_id': connection_id if 'connection_id' in locals() else 'unknown',
            'timestamp': None
        }, 500

@functions_framework.http
def health_check(request):
    """Simple health check endpoint for monitoring."""
    return {
        'status': 'healthy',
        'service': 'federation-metadata-sync',
        'timestamp': json.dumps(str(bigquery.Client().query('SELECT CURRENT_TIMESTAMP()').result().to_dataframe().iloc[0, 0]))
    }, 200