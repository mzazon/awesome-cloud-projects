"""
Data Ingestion Lambda Function

This function serves as the entry point for data into the serverless data lake.
It processes S3 events triggered by new file uploads, extracts metadata,
and publishes ingestion events to EventBridge for downstream processing.

Features:
- Handles multiple file formats (JSON, CSV, text)
- Extracts file metadata and content type detection
- Publishes structured events for validation pipeline
- Comprehensive error handling and logging
- Integration with shared utilities layer
"""

import json
import os
import boto3
from datetime import datetime
from typing import Dict, Any, List
from data_utils import DataProcessor, EventPublisher, MetricsCollector


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for data ingestion processing.
    
    Processes S3 events when new files are uploaded to the raw data bucket.
    Extracts file metadata, determines data type, and publishes ingestion events.
    
    Args:
        event: S3 event notification payload
        context: Lambda context object
        
    Returns:
        Response dictionary with processing status
    """
    # Initialize processors and clients
    processor = DataProcessor()
    event_publisher = EventPublisher(os.environ['CUSTOM_EVENT_BUS'])
    metrics_collector = MetricsCollector()
    
    # Extract environment variables
    metadata_table = os.environ['METADATA_TABLE']
    processed_bucket = os.environ['PROCESSED_BUCKET']
    project_name = os.environ['PROJECT_NAME']
    
    try:
        # Process each S3 record in the event
        results = []
        for record in event.get('Records', []):
            try:
                result = process_s3_record(
                    record, processor, event_publisher, 
                    metadata_table, project_name
                )
                results.append(result)
            except Exception as record_error:
                print(f"Error processing record: {str(record_error)}")
                results.append({
                    'status': 'error',
                    'error': str(record_error)
                })
        
        # Publish overall metrics
        success_count = sum(1 for r in results if r.get('status') == 'success')
        total_count = len(results)
        success_rate = (success_count / total_count * 100) if total_count > 0 else 0
        
        metrics_collector.publish_validation_metrics(
            pipeline_name=project_name,
            success_rate=success_rate,
            avg_quality_score=0,  # Will be calculated in validation stage
            total_records=total_count
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data ingestion completed',
                'processed_records': total_count,
                'successful_records': success_count,
                'results': results
            })
        }
        
    except Exception as e:
        print(f"Critical error in data ingestion: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Data ingestion failed'
            })
        }


def process_s3_record(
    record: Dict[str, Any],
    processor: DataProcessor,
    event_publisher: EventPublisher,
    metadata_table: str,
    project_name: str
) -> Dict[str, Any]:
    """
    Process individual S3 record from the event.
    
    Args:
        record: S3 record from the event
        processor: DataProcessor instance
        event_publisher: EventPublisher instance
        metadata_table: DynamoDB metadata table name
        project_name: Project name for tracking
        
    Returns:
        Processing result dictionary
    """
    # Extract S3 event information
    bucket = record['s3']['bucket']['name']
    key = record['s3']['object']['key']
    size = record['s3']['object']['size']
    event_time = record['eventTime']
    
    print(f"Processing file: s3://{bucket}/{key} (size: {size} bytes)")
    
    # Generate unique process ID
    process_id = processor.generate_process_id(bucket, event_time)
    
    try:
        # Download and analyze the file
        s3_response = processor.s3_client.get_object(Bucket=bucket, Key=key)
        file_content = s3_response['Body'].read().decode('utf-8')
        content_type = s3_response.get('ContentType', 'application/octet-stream')
        
        # Determine data type and validate basic structure
        data_analysis = analyze_file_content(key, file_content, content_type)
        
        # Store ingestion metadata
        metadata = {
            'SourceBucket': bucket,
            'SourceKey': key,
            'FileSize': size,
            'ContentType': content_type,
            'DataType': data_analysis['data_type'],
            'RecordCount': data_analysis.get('record_count', 0),
            'Status': 'ingested',
            'ProcessingStage': 'ingestion',
            'EventTime': event_time,
            'ContentPreview': data_analysis.get('preview', '')[:500]  # First 500 chars
        }
        
        processor.store_metadata(
            table_name=metadata_table,
            process_id=process_id,
            metadata=metadata
        )
        
        # Publish ingestion event for downstream processing
        event_publisher.publish_ingestion_event(
            process_id=process_id,
            bucket=bucket,
            key=key,
            data_type=data_analysis['data_type'],
            file_size=size
        )
        
        print(f"✅ Successfully processed file {key} with process ID {process_id}")
        
        return {
            'status': 'success',
            'processId': process_id,
            'dataType': data_analysis['data_type'],
            'fileSize': size,
            'recordCount': data_analysis.get('record_count', 0)
        }
        
    except Exception as e:
        print(f"❌ Error processing file {key}: {str(e)}")
        
        # Store error metadata
        error_metadata = {
            'SourceBucket': bucket,
            'SourceKey': key,
            'FileSize': size,
            'Status': 'failed',
            'ProcessingStage': 'ingestion',
            'ErrorMessage': str(e),
            'EventTime': event_time
        }
        
        try:
            processor.store_metadata(
                table_name=metadata_table,
                process_id=process_id,
                metadata=error_metadata
            )
        except Exception as metadata_error:
            print(f"Failed to store error metadata: {str(metadata_error)}")
        
        raise e


def analyze_file_content(key: str, content: str, content_type: str) -> Dict[str, Any]:
    """
    Analyze file content to determine data type and extract basic metrics.
    
    Args:
        key: S3 object key
        content: File content as string
        content_type: HTTP content type
        
    Returns:
        Dictionary with analysis results
    """
    analysis = {
        'data_type': 'unknown',
        'record_count': 0,
        'preview': content[:200] if content else '',
        'format_valid': False
    }
    
    try:
        # Determine data type based on file extension and content
        if key.lower().endswith('.json'):
            analysis.update(analyze_json_content(content))
        elif key.lower().endswith('.csv'):
            analysis.update(analyze_csv_content(content))
        elif key.lower().endswith(('.txt', '.log')):
            analysis.update(analyze_text_content(content))
        elif content_type.startswith('application/json'):
            analysis.update(analyze_json_content(content))
        else:
            # Default text analysis
            analysis.update(analyze_text_content(content))
            
    except Exception as e:
        print(f"Error analyzing file content: {str(e)}")
        analysis['error'] = str(e)
    
    return analysis


def analyze_json_content(content: str) -> Dict[str, Any]:
    """
    Analyze JSON file content.
    
    Args:
        content: JSON content as string
        
    Returns:
        Analysis results for JSON content
    """
    try:
        data = json.loads(content)
        
        if isinstance(data, list):
            record_count = len(data)
            data_type = 'json_array'
        elif isinstance(data, dict):
            record_count = 1
            data_type = 'json_object'
        else:
            record_count = 1
            data_type = 'json_primitive'
        
        return {
            'data_type': data_type,
            'record_count': record_count,
            'format_valid': True,
            'schema_keys': list(data.keys()) if isinstance(data, dict) else []
        }
        
    except json.JSONDecodeError as e:
        return {
            'data_type': 'json_invalid',
            'record_count': 0,
            'format_valid': False,
            'parse_error': str(e)
        }


def analyze_csv_content(content: str) -> Dict[str, Any]:
    """
    Analyze CSV file content.
    
    Args:
        content: CSV content as string
        
    Returns:
        Analysis results for CSV content
    """
    try:
        lines = content.strip().split('\n')
        
        if len(lines) < 1:
            return {
                'data_type': 'csv_empty',
                'record_count': 0,
                'format_valid': False
            }
        
        header_line = lines[0]
        data_lines = lines[1:] if len(lines) > 1 else []
        
        # Simple CSV validation - check for consistent column count
        header_cols = len(header_line.split(','))
        valid_rows = 0
        
        for line in data_lines:
            if line.strip() and len(line.split(',')) == header_cols:
                valid_rows += 1
        
        return {
            'data_type': 'csv',
            'record_count': len(data_lines),
            'format_valid': len(data_lines) == valid_rows if data_lines else True,
            'column_count': header_cols,
            'headers': [col.strip() for col in header_line.split(',')]
        }
        
    except Exception as e:
        return {
            'data_type': 'csv_invalid',
            'record_count': 0,
            'format_valid': False,
            'parse_error': str(e)
        }


def analyze_text_content(content: str) -> Dict[str, Any]:
    """
    Analyze plain text file content.
    
    Args:
        content: Text content as string
        
    Returns:
        Analysis results for text content
    """
    try:
        lines = content.strip().split('\n')
        non_empty_lines = [line for line in lines if line.strip()]
        
        return {
            'data_type': 'text',
            'record_count': len(non_empty_lines),
            'format_valid': True,
            'total_lines': len(lines),
            'character_count': len(content)
        }
        
    except Exception as e:
        return {
            'data_type': 'text_invalid',
            'record_count': 0,
            'format_valid': False,
            'parse_error': str(e)
        }