"""
Data Validation Lambda Function

This function implements comprehensive data validation for the serverless data lake.
It consumes EventBridge events from the ingestion stage, validates data structure
and quality, and routes data to appropriate storage based on validation results.

Features:
- Schema validation for JSON and CSV data
- Data quality scoring and assessment
- Business rule validation (email, phone, date formats)
- Intelligent routing to processed or quarantine storage
- Detailed validation error reporting
- Integration with shared utilities layer
"""

import json
import os
import boto3
from datetime import datetime
from typing import Dict, Any, List, Optional
from data_utils import DataProcessor, DataValidator, EventPublisher, MetricsCollector


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for data validation processing.
    
    Processes EventBridge events from the data ingestion stage, validates
    data structure and quality, and routes to appropriate storage tier.
    
    Args:
        event: EventBridge event payload
        context: Lambda context object
        
    Returns:
        Response dictionary with validation status
    """
    # Initialize processors and clients
    processor = DataProcessor()
    event_publisher = EventPublisher(os.environ['CUSTOM_EVENT_BUS'])
    metrics_collector = MetricsCollector()
    
    # Extract environment variables
    metadata_table = os.environ['METADATA_TABLE']
    processed_bucket = os.environ['PROCESSED_BUCKET']
    quarantine_bucket = os.environ['QUARANTINE_BUCKET']
    project_name = os.environ['PROJECT_NAME']
    
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        process_id = detail.get('processId')
        bucket = detail.get('bucket')
        key = detail.get('key')
        data_type = detail.get('dataType')
        file_size = detail.get('fileSize', 0)
        
        if not all([process_id, bucket, key, data_type]):
            raise ValueError("Missing required fields in event detail")
        
        print(f"Validating file: s3://{bucket}/{key} (Process ID: {process_id})")
        
        # Perform validation
        validation_result = validate_data_file(
            bucket, key, data_type, processor
        )
        
        # Determine destination based on validation results
        destination_info = determine_destination(
            validation_result, processed_bucket, quarantine_bucket
        )
        
        # Copy file to appropriate destination
        destination_key = f"{destination_info['prefix']}{key}"
        processor.copy_s3_object(
            source_bucket=bucket,
            source_key=key,
            dest_bucket=destination_info['bucket'],
            dest_key=destination_key
        )
        
        # Update metadata with validation results
        update_metadata(
            processor, metadata_table, process_id,
            validation_result, destination_info, destination_key
        )
        
        # Publish validation event for downstream processing
        event_publisher.publish_validation_event(
            process_id=process_id,
            validation_passed=validation_result['validation_passed'],
            quality_score=validation_result['quality_score'],
            validation_errors=validation_result['validation_errors']
        )
        
        # Publish quality metrics
        publish_quality_metrics(
            metrics_collector, project_name, validation_result
        )
        
        print(f"✅ Validation completed for {key}: "
              f"Passed={validation_result['validation_passed']}, "
              f"Score={validation_result['quality_score']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processId': process_id,
                'validationPassed': validation_result['validation_passed'],
                'qualityScore': validation_result['quality_score'],
                'destination': destination_info['bucket'],
                'destinationKey': destination_key
            })
        }
        
    except Exception as e:
        print(f"❌ Error in data validation: {str(e)}")
        
        # Store error metadata if possible
        if 'detail' in event and 'processId' in event['detail']:
            try:
                processor.store_metadata(
                    table_name=metadata_table,
                    process_id=event['detail']['processId'],
                    metadata={
                        'Status': 'validation_failed',
                        'ProcessingStage': 'validation',
                        'ErrorMessage': str(e),
                        'ErrorTimestamp': datetime.utcnow().isoformat()
                    }
                )
            except Exception as metadata_error:
                print(f"Failed to store error metadata: {str(metadata_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Data validation failed'
            })
        }


def validate_data_file(
    bucket: str,
    key: str,
    data_type: str,
    processor: DataProcessor
) -> Dict[str, Any]:
    """
    Validate data file based on its type and content.
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        data_type: Type of data file
        processor: DataProcessor instance
        
    Returns:
        Validation result dictionary
    """
    validation_result = {
        'validation_passed': True,
        'validation_errors': [],
        'quality_score': 0.0,
        'validation_details': {}
    }
    
    try:
        # Download file content
        s3_response = processor.s3_client.get_object(Bucket=bucket, Key=key)
        file_content = s3_response['Body'].read().decode('utf-8')
        
        # Validate based on data type
        if data_type.startswith('json'):
            validation_result = validate_json_data(file_content, validation_result)
        elif data_type == 'csv':
            validation_result = validate_csv_data(file_content, validation_result)
        elif data_type == 'text':
            validation_result = validate_text_data(file_content, validation_result)
        else:
            validation_result['validation_errors'].append(f"Unsupported data type: {data_type}")
            validation_result['validation_passed'] = False
        
        # Apply minimum quality score threshold
        min_quality_threshold = 70.0
        if validation_result['quality_score'] < min_quality_threshold:
            validation_result['validation_passed'] = False
            validation_result['validation_errors'].append(
                f"Quality score {validation_result['quality_score']} "
                f"below threshold {min_quality_threshold}"
            )
        
    except Exception as e:
        validation_result['validation_passed'] = False
        validation_result['validation_errors'].append(f"Validation error: {str(e)}")
        validation_result['quality_score'] = 0.0
    
    return validation_result


def validate_json_data(content: str, validation_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate JSON data structure and content.
    
    Args:
        content: JSON content as string
        validation_result: Existing validation result to update
        
    Returns:
        Updated validation result
    """
    try:
        data = json.loads(content)
        
        # Handle different JSON structures
        if isinstance(data, list):
            if not data:
                validation_result['validation_errors'].append("Empty JSON array")
                validation_result['validation_passed'] = False
                return validation_result
            
            # Validate each object in the array
            total_quality = 0
            valid_objects = 0
            
            for i, obj in enumerate(data):
                if isinstance(obj, dict):
                    obj_validation = validate_json_object(obj, i)
                    validation_result['validation_errors'].extend(obj_validation['errors'])
                    total_quality += obj_validation['quality_score']
                    valid_objects += 1
                else:
                    validation_result['validation_errors'].append(
                        f"Non-object item at index {i}: {type(obj)}"
                    )
            
            validation_result['quality_score'] = total_quality / max(valid_objects, 1)
            validation_result['validation_details']['record_count'] = len(data)
            validation_result['validation_details']['valid_objects'] = valid_objects
            
        elif isinstance(data, dict):
            obj_validation = validate_json_object(data, 0)
            validation_result['validation_errors'].extend(obj_validation['errors'])
            validation_result['quality_score'] = obj_validation['quality_score']
            validation_result['validation_details']['record_count'] = 1
        else:
            validation_result['validation_errors'].append(
                f"Invalid JSON structure: {type(data)}"
            )
            validation_result['validation_passed'] = False
        
        # Check for any validation errors
        if validation_result['validation_errors']:
            validation_result['validation_passed'] = False
            
    except json.JSONDecodeError as e:
        validation_result['validation_passed'] = False
        validation_result['validation_errors'].append(f"Invalid JSON format: {str(e)}")
        validation_result['quality_score'] = 0.0
    
    return validation_result


def validate_json_object(obj: Dict[str, Any], index: int) -> Dict[str, Any]:
    """
    Validate individual JSON object.
    
    Args:
        obj: JSON object to validate
        index: Object index for error reporting
        
    Returns:
        Object validation result
    """
    validation = {
        'errors': [],
        'quality_score': 0.0
    }
    
    # Define expected schema (configurable in production)
    required_fields = ['id', 'timestamp']  # Minimum required fields
    optional_fields = ['data', 'metadata', 'email', 'phone']
    
    # Check required fields
    missing_fields = DataValidator.validate_required_fields(obj, required_fields)
    if missing_fields:
        validation['errors'].append(
            f"Object {index}: Missing required fields: {', '.join(missing_fields)}"
        )
    
    # Calculate base quality score
    validation['quality_score'] = DataProcessor().calculate_data_quality_score(obj)
    
    # Validate specific field formats
    for field, value in obj.items():
        if field == 'email' and value:
            if not DataValidator.is_valid_email(str(value)):
                validation['errors'].append(
                    f"Object {index}: Invalid email format: {value}"
                )
        
        elif field == 'phone' and value:
            if not DataValidator.is_valid_phone(str(value)):
                validation['errors'].append(
                    f"Object {index}: Invalid phone format: {value}"
                )
        
        elif field == 'timestamp' and value:
            # Try multiple timestamp formats
            timestamp_formats = [
                '%Y-%m-%dT%H:%M:%SZ',
                '%Y-%m-%d %H:%M:%S',
                '%Y-%m-%d'
            ]
            valid_timestamp = False
            for fmt in timestamp_formats:
                if DataValidator.is_valid_date_format(str(value), fmt):
                    valid_timestamp = True
                    break
            
            if not valid_timestamp:
                validation['errors'].append(
                    f"Object {index}: Invalid timestamp format: {value}"
                )
    
    return validation


def validate_csv_data(content: str, validation_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate CSV data structure and content.
    
    Args:
        content: CSV content as string
        validation_result: Existing validation result to update
        
    Returns:
        Updated validation result
    """
    try:
        lines = content.strip().split('\n')
        
        if len(lines) < 2:
            validation_result['validation_errors'].append(
                "CSV must have header and at least one data row"
            )
            validation_result['validation_passed'] = False
            validation_result['quality_score'] = 0.0
            return validation_result
        
        header_line = lines[0]
        data_lines = lines[1:]
        
        # Parse header
        headers = [col.strip().strip('"') for col in header_line.split(',')]
        column_count = len(headers)
        
        # Validate data rows
        valid_rows = 0
        total_quality = 0
        
        for i, line in enumerate(data_lines, 1):
            if not line.strip():
                continue
                
            columns = [col.strip().strip('"') for col in line.split(',')]
            
            if len(columns) != column_count:
                validation_result['validation_errors'].append(
                    f"Row {i}: Expected {column_count} columns, got {len(columns)}"
                )
            else:
                valid_rows += 1
                
                # Create row dictionary for quality assessment
                row_dict = dict(zip(headers, columns))
                row_quality = DataProcessor().calculate_data_quality_score(row_dict)
                total_quality += row_quality
        
        # Calculate overall metrics
        data_row_count = len([line for line in data_lines if line.strip()])
        validation_result['quality_score'] = total_quality / max(valid_rows, 1)
        validation_result['validation_details'] = {
            'header_count': column_count,
            'data_row_count': data_row_count,
            'valid_rows': valid_rows,
            'headers': headers
        }
        
        # Set minimum validation thresholds
        if valid_rows < data_row_count * 0.8:  # At least 80% valid rows
            validation_result['validation_errors'].append(
                f"Too many invalid rows: {valid_rows}/{data_row_count} valid"
            )
            validation_result['validation_passed'] = False
        
    except Exception as e:
        validation_result['validation_passed'] = False
        validation_result['validation_errors'].append(f"CSV validation error: {str(e)}")
        validation_result['quality_score'] = 0.0
    
    return validation_result


def validate_text_data(content: str, validation_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate plain text data content.
    
    Args:
        content: Text content as string
        validation_result: Existing validation result to update
        
    Returns:
        Updated validation result
    """
    try:
        lines = content.strip().split('\n')
        non_empty_lines = [line for line in lines if line.strip()]
        
        # Basic text validation
        if not non_empty_lines:
            validation_result['validation_errors'].append("Empty text file")
            validation_result['validation_passed'] = False
            validation_result['quality_score'] = 0.0
        else:
            # Simple quality assessment for text
            avg_line_length = sum(len(line) for line in non_empty_lines) / len(non_empty_lines)
            
            # Quality based on content characteristics
            if avg_line_length < 5:
                validation_result['quality_score'] = 60.0  # Low quality for very short lines
            elif avg_line_length > 1000:
                validation_result['quality_score'] = 70.0  # Medium quality for very long lines
            else:
                validation_result['quality_score'] = 85.0  # Good quality for normal text
        
        validation_result['validation_details'] = {
            'total_lines': len(lines),
            'non_empty_lines': len(non_empty_lines),
            'average_line_length': avg_line_length if non_empty_lines else 0
        }
        
    except Exception as e:
        validation_result['validation_passed'] = False
        validation_result['validation_errors'].append(f"Text validation error: {str(e)}")
        validation_result['quality_score'] = 0.0
    
    return validation_result


def determine_destination(
    validation_result: Dict[str, Any],
    processed_bucket: str,
    quarantine_bucket: str
) -> Dict[str, str]:
    """
    Determine destination bucket and prefix based on validation results.
    
    Args:
        validation_result: Validation result dictionary
        processed_bucket: Processed data bucket name
        quarantine_bucket: Quarantine bucket name
        
    Returns:
        Destination information dictionary
    """
    if validation_result['validation_passed'] and validation_result['quality_score'] >= 70:
        return {
            'bucket': processed_bucket,
            'prefix': 'validated/',
            'status': 'validated'
        }
    else:
        return {
            'bucket': quarantine_bucket,
            'prefix': 'quarantine/',
            'status': 'quarantined'
        }


def update_metadata(
    processor: DataProcessor,
    metadata_table: str,
    process_id: str,
    validation_result: Dict[str, Any],
    destination_info: Dict[str, str],
    destination_key: str
) -> None:
    """
    Update metadata table with validation results.
    
    Args:
        processor: DataProcessor instance
        metadata_table: DynamoDB metadata table name
        process_id: Process ID
        validation_result: Validation result dictionary
        destination_info: Destination information
        destination_key: Destination S3 key
    """
    metadata = {
        'Status': destination_info['status'],
        'ProcessingStage': 'validation',
        'ValidationPassed': validation_result['validation_passed'],
        'QualityScore': validation_result['quality_score'],
        'ValidationErrors': validation_result['validation_errors'],
        'ValidationDetails': validation_result.get('validation_details', {}),
        'DestinationBucket': destination_info['bucket'],
        'DestinationKey': destination_key,
        'ValidationTimestamp': datetime.utcnow().isoformat()
    }
    
    processor.store_metadata(
        table_name=metadata_table,
        process_id=process_id,
        metadata=metadata
    )


def publish_quality_metrics(
    metrics_collector: MetricsCollector,
    project_name: str,
    validation_result: Dict[str, Any]
) -> None:
    """
    Publish validation quality metrics to CloudWatch.
    
    Args:
        metrics_collector: MetricsCollector instance
        project_name: Project name for metrics dimension
        validation_result: Validation result dictionary
    """
    try:
        success_rate = 100.0 if validation_result['validation_passed'] else 0.0
        
        metrics_collector.publish_validation_metrics(
            pipeline_name=project_name,
            success_rate=success_rate,
            avg_quality_score=validation_result['quality_score'],
            total_records=1
        )
    except Exception as e:
        print(f"Error publishing quality metrics: {str(e)}")