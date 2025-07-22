"""
Shared Data Processing Utilities for Serverless Data Lake

This module provides common utilities for data processing, validation, and 
quality assessment across Lambda functions in the data lake architecture.

Classes:
    DataProcessor: Core data processing and AWS service integration
    DataValidator: Data validation and quality checking utilities
    EventPublisher: EventBridge event publishing utilities
    MetricsCollector: CloudWatch metrics collection utilities
"""

import json
import boto3
import uuid
import hashlib
import re
from datetime import datetime
from typing import Dict, Any, List, Optional, Union
from decimal import Decimal


class DataProcessor:
    """
    Core data processing utilities for the serverless data lake.
    
    Provides methods for data manipulation, AWS service integration,
    and common processing tasks across Lambda functions.
    """

    def __init__(self):
        """Initialize AWS service clients."""
        self.s3_client = boto3.client('s3')
        self.dynamodb = boto3.resource('dynamodb')
        self.events_client = boto3.client('events')
        self.cloudwatch = boto3.client('cloudwatch')

    def generate_process_id(self, source: str, timestamp: str) -> str:
        """
        Generate unique process ID for data processing tracking.
        
        Args:
            source: Source identifier (bucket name, API endpoint, etc.)
            timestamp: Processing timestamp
            
        Returns:
            Unique MD5 hash-based process ID
        """
        data = f"{source}-{timestamp}-{uuid.uuid4()}"
        return hashlib.md5(data.encode()).hexdigest()

    def validate_json_structure(self, data: Dict[str, Any], required_fields: List[str]) -> bool:
        """
        Validate JSON data structure against required fields.
        
        Args:
            data: JSON data dictionary
            required_fields: List of required field names
            
        Returns:
            True if all required fields are present, False otherwise
        """
        return all(field in data for field in required_fields)

    def calculate_data_quality_score(self, data: Dict[str, Any]) -> float:
        """
        Calculate data quality score based on completeness and validity.
        
        Args:
            data: Data dictionary to evaluate
            
        Returns:
            Quality score between 0.0 and 100.0
        """
        if not data:
            return 0.0
            
        total_fields = len(data)
        non_null_fields = sum(1 for v in data.values() if v is not None and v != "")
        
        # Base completeness score
        completeness_score = (non_null_fields / total_fields) * 100 if total_fields > 0 else 0
        
        # Additional quality factors
        quality_adjustments = 0
        
        # Check for valid email formats
        for key, value in data.items():
            if 'email' in key.lower() and isinstance(value, str):
                if DataValidator.is_valid_email(value):
                    quality_adjustments += 5
                else:
                    quality_adjustments -= 10
                    
        # Check for valid phone formats
        for key, value in data.items():
            if 'phone' in key.lower() and isinstance(value, str):
                if DataValidator.is_valid_phone(value):
                    quality_adjustments += 5
                else:
                    quality_adjustments -= 10
        
        # Final score with adjustments, capped at 100
        final_score = min(100.0, max(0.0, completeness_score + quality_adjustments))
        return round(final_score, 2)

    def publish_custom_event(self, event_bus: str, source: str, 
                           detail_type: str, detail: Dict[str, Any]) -> None:
        """
        Publish custom event to EventBridge.
        
        Args:
            event_bus: EventBridge bus name
            source: Event source identifier
            detail_type: Event detail type
            detail: Event detail payload
        """
        try:
            self.events_client.put_events(
                Entries=[
                    {
                        'Source': source,
                        'DetailType': detail_type,
                        'Detail': json.dumps(detail, cls=DecimalEncoder),
                        'EventBusName': event_bus,
                        'Time': datetime.utcnow()
                    }
                ]
            )
        except Exception as e:
            print(f"Error publishing event: {str(e)}")
            raise

    def store_metadata(self, table_name: str, process_id: str, metadata: Dict[str, Any]) -> None:
        """
        Store processing metadata in DynamoDB.
        
        Args:
            table_name: DynamoDB table name
            process_id: Unique process identifier
            metadata: Metadata dictionary to store
        """
        try:
            table = self.dynamodb.Table(table_name)
            item = {
                'ProcessId': process_id,
                'Timestamp': datetime.utcnow().isoformat(),
                **metadata
            }
            table.put_item(Item=item)
        except Exception as e:
            print(f"Error storing metadata: {str(e)}")
            raise

    def copy_s3_object(self, source_bucket: str, source_key: str,
                      dest_bucket: str, dest_key: str) -> None:
        """
        Copy S3 object from source to destination.
        
        Args:
            source_bucket: Source S3 bucket name
            source_key: Source object key
            dest_bucket: Destination S3 bucket name
            dest_key: Destination object key
        """
        try:
            copy_source = {'Bucket': source_bucket, 'Key': source_key}
            self.s3_client.copy_object(
                CopySource=copy_source,
                Bucket=dest_bucket,
                Key=dest_key
            )
        except Exception as e:
            print(f"Error copying S3 object: {str(e)}")
            raise


class DataValidator:
    """
    Data validation utilities for quality checking and format validation.
    
    Provides static methods for validating common data formats and patterns.
    """

    @staticmethod
    def is_valid_email(email: str) -> bool:
        """
        Validate email address format.
        
        Args:
            email: Email address string
            
        Returns:
            True if valid email format, False otherwise
        """
        if not email or not isinstance(email, str):
            return False
            
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None

    @staticmethod
    def is_valid_phone(phone: str) -> bool:
        """
        Validate phone number format (US format).
        
        Args:
            phone: Phone number string
            
        Returns:
            True if valid phone format, False otherwise
        """
        if not phone or not isinstance(phone, str):
            return False
            
        # Remove common separators
        cleaned_phone = re.sub(r'[\s\-\(\)]', '', phone)
        
        # US phone number pattern
        pattern = r'^\+?1?[2-9]\d{2}[2-9]\d{2}\d{4}$'
        return re.match(pattern, cleaned_phone) is not None

    @staticmethod
    def is_valid_date_format(date_str: str, format_pattern: str = '%Y-%m-%d') -> bool:
        """
        Validate date string against specified format.
        
        Args:
            date_str: Date string to validate
            format_pattern: Expected date format pattern
            
        Returns:
            True if valid date format, False otherwise
        """
        if not date_str or not isinstance(date_str, str):
            return False
            
        try:
            datetime.strptime(date_str, format_pattern)
            return True
        except ValueError:
            return False

    @staticmethod
    def is_valid_numeric_range(value: Union[int, float], min_val: float = None,
                              max_val: float = None) -> bool:
        """
        Validate numeric value within specified range.
        
        Args:
            value: Numeric value to validate
            min_val: Minimum allowed value (optional)
            max_val: Maximum allowed value (optional)
            
        Returns:
            True if value is within range, False otherwise
        """
        try:
            num_value = float(value)
            
            if min_val is not None and num_value < min_val:
                return False
                
            if max_val is not None and num_value > max_val:
                return False
                
            return True
        except (ValueError, TypeError):
            return False

    @staticmethod
    def validate_required_fields(data: Dict[str, Any], required_fields: List[str]) -> List[str]:
        """
        Validate presence of required fields and return missing fields.
        
        Args:
            data: Data dictionary to validate
            required_fields: List of required field names
            
        Returns:
            List of missing field names
        """
        missing_fields = []
        for field in required_fields:
            if field not in data or data[field] is None or data[field] == "":
                missing_fields.append(field)
        return missing_fields


class EventPublisher:
    """
    EventBridge event publishing utilities.
    
    Provides methods for publishing structured events to custom EventBridge buses.
    """

    def __init__(self, event_bus_name: str):
        """
        Initialize EventPublisher with specific event bus.
        
        Args:
            event_bus_name: Name of the EventBridge bus
        """
        self.event_bus_name = event_bus_name
        self.events_client = boto3.client('events')

    def publish_ingestion_event(self, process_id: str, bucket: str, key: str,
                               data_type: str, file_size: int) -> None:
        """
        Publish data ingestion event.
        
        Args:
            process_id: Unique process identifier
            bucket: S3 bucket name
            key: S3 object key
            data_type: Type of data (json, csv, etc.)
            file_size: Size of the file in bytes
        """
        event_detail = {
            'processId': process_id,
            'bucket': bucket,
            'key': key,
            'dataType': data_type,
            'fileSize': file_size,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        self._publish_event(
            source='datalake.ingestion',
            detail_type='Data Received',
            detail=event_detail
        )

    def publish_validation_event(self, process_id: str, validation_passed: bool,
                                quality_score: float, validation_errors: List[str]) -> None:
        """
        Publish data validation event.
        
        Args:
            process_id: Unique process identifier
            validation_passed: Whether validation passed
            quality_score: Data quality score
            validation_errors: List of validation errors
        """
        event_detail = {
            'processId': process_id,
            'validationPassed': validation_passed,
            'qualityScore': quality_score,
            'validationErrors': validation_errors,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        self._publish_event(
            source='datalake.validation',
            detail_type='Data Validated',
            detail=event_detail
        )

    def publish_quality_event(self, process_id: str, metrics: Dict[str, Any]) -> None:
        """
        Publish quality monitoring event.
        
        Args:
            process_id: Unique process identifier
            metrics: Quality metrics dictionary
        """
        event_detail = {
            'processId': process_id,
            'metrics': metrics,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        self._publish_event(
            source='datalake.quality',
            detail_type='Quality Check Complete',
            detail=event_detail
        )

    def _publish_event(self, source: str, detail_type: str, detail: Dict[str, Any]) -> None:
        """
        Internal method to publish event to EventBridge.
        
        Args:
            source: Event source
            detail_type: Event detail type
            detail: Event detail payload
        """
        try:
            self.events_client.put_events(
                Entries=[
                    {
                        'Source': source,
                        'DetailType': detail_type,
                        'Detail': json.dumps(detail, cls=DecimalEncoder),
                        'EventBusName': self.event_bus_name,
                        'Time': datetime.utcnow()
                    }
                ]
            )
        except Exception as e:
            print(f"Error publishing {detail_type} event: {str(e)}")
            raise


class MetricsCollector:
    """
    CloudWatch metrics collection utilities.
    
    Provides methods for publishing custom metrics to CloudWatch.
    """

    def __init__(self, namespace: str = 'DataLake/Quality'):
        """
        Initialize MetricsCollector with CloudWatch namespace.
        
        Args:
            namespace: CloudWatch metrics namespace
        """
        self.namespace = namespace
        self.cloudwatch = boto3.client('cloudwatch')

    def publish_validation_metrics(self, pipeline_name: str, success_rate: float,
                                  avg_quality_score: float, total_records: int) -> None:
        """
        Publish validation metrics to CloudWatch.
        
        Args:
            pipeline_name: Name of the data pipeline
            success_rate: Validation success rate percentage
            avg_quality_score: Average quality score
            total_records: Total number of processed records
        """
        try:
            metric_data = [
                {
                    'MetricName': 'ValidationSuccessRate',
                    'Value': success_rate,
                    'Unit': 'Percent',
                    'Dimensions': [{'Name': 'Pipeline', 'Value': pipeline_name}],
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'AverageQualityScore',
                    'Value': avg_quality_score,
                    'Unit': 'None',
                    'Dimensions': [{'Name': 'Pipeline', 'Value': pipeline_name}],
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'ProcessedRecords',
                    'Value': total_records,
                    'Unit': 'Count',
                    'Dimensions': [{'Name': 'Pipeline', 'Value': pipeline_name}],
                    'Timestamp': datetime.utcnow()
                }
            ]
            
            self.cloudwatch.put_metric_data(
                Namespace=self.namespace,
                MetricData=metric_data
            )
        except Exception as e:
            print(f"Error publishing metrics: {str(e)}")
            raise


class DecimalEncoder(json.JSONEncoder):
    """
    JSON encoder for DynamoDB Decimal types.
    
    Handles conversion of Decimal objects to float for JSON serialization.
    """
    
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)


# Utility functions for common operations
def safe_get_nested_value(data: Dict[str, Any], key_path: str, default: Any = None) -> Any:
    """
    Safely get nested dictionary value using dot notation.
    
    Args:
        data: Dictionary to search
        key_path: Dot-separated key path (e.g., 'user.profile.email')
        default: Default value if key not found
        
    Returns:
        Value at key path or default value
    """
    try:
        keys = key_path.split('.')
        value = data
        for key in keys:
            value = value[key]
        return value
    except (KeyError, TypeError):
        return default


def flatten_dictionary(data: Dict[str, Any], parent_key: str = '', sep: str = '.') -> Dict[str, Any]:
    """
    Flatten nested dictionary structure.
    
    Args:
        data: Dictionary to flatten
        parent_key: Parent key for recursion
        sep: Separator for nested keys
        
    Returns:
        Flattened dictionary
    """
    items = []
    for key, value in data.items():
        new_key = f"{parent_key}{sep}{key}" if parent_key else key
        if isinstance(value, dict):
            items.extend(flatten_dictionary(value, new_key, sep=sep).items())
        else:
            items.append((new_key, value))
    return dict(items)