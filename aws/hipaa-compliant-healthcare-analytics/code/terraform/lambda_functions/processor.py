"""
AWS HealthLake Event Processor Lambda Function

This Lambda function processes EventBridge events from AWS HealthLake,
including import job status changes, export job status changes, and
data store state changes. It provides logging and monitoring for
healthcare data processing pipeline operations.

Environment Variables:
- DATASTORE_ENDPOINT: HealthLake FHIR endpoint URL
- DATASTORE_ID: HealthLake data store ID
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
healthlake = boto3.client('healthlake')
s3 = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

# Environment variables
DATASTORE_ENDPOINT = os.environ.get('DATASTORE_ENDPOINT', '')
DATASTORE_ID = os.environ.get('DATASTORE_ID', '')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for processing HealthLake events.
    
    Args:
        event: EventBridge event data
        context: Lambda context object
        
    Returns:
        Response dictionary with status code and message
    """
    try:
        logger.info(f"Processing HealthLake event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', '')
        event_type = event.get('detail-type', '')
        event_detail = event.get('detail', {})
        event_time = event.get('time', '')
        
        # Validate event source
        if event_source != 'aws.healthlake':
            logger.warning(f"Unexpected event source: {event_source}")
            return create_response(400, "Invalid event source")
        
        # Process different types of HealthLake events
        if 'Import Job' in event_type:
            result = process_import_job_event(event_detail, event_time)
        elif 'Export Job' in event_type:
            result = process_export_job_event(event_detail, event_time)
        elif 'Data Store' in event_type:
            result = process_datastore_event(event_detail, event_time)
        else:
            logger.warning(f"Unknown event type: {event_type}")
            result = {"status": "ignored", "reason": "unknown_event_type"}
        
        # Publish custom CloudWatch metrics
        publish_metrics(event_type, event_detail)
        
        logger.info(f"Event processing completed: {result}")
        return create_response(200, "Event processed successfully", result)
        
    except Exception as e:
        logger.error(f"Error processing HealthLake event: {str(e)}", exc_info=True)
        return create_response(500, f"Error processing event: {str(e)}")


def process_import_job_event(event_detail: Dict[str, Any], event_time: str) -> Dict[str, Any]:
    """
    Process HealthLake import job status change events.
    
    Args:
        event_detail: Event detail information
        event_time: Event timestamp
        
    Returns:
        Processing result dictionary
    """
    job_status = event_detail.get('jobStatus', 'UNKNOWN')
    job_id = event_detail.get('jobId', 'UNKNOWN')
    message = event_detail.get('message', '')
    
    logger.info(f"Processing import job event - ID: {job_id}, Status: {job_status}")
    
    if job_status == 'COMPLETED':
        logger.info(f"Import job {job_id} completed successfully")
        return handle_successful_import(job_id, event_detail)
    elif job_status == 'FAILED':
        logger.error(f"Import job {job_id} failed: {message}")
        return handle_failed_import(job_id, event_detail)
    elif job_status == 'IN_PROGRESS':
        logger.info(f"Import job {job_id} is in progress")
        return {"status": "monitoring", "job_id": job_id}
    else:
        logger.warning(f"Unknown import job status: {job_status}")
        return {"status": "unknown", "job_id": job_id, "job_status": job_status}


def process_export_job_event(event_detail: Dict[str, Any], event_time: str) -> Dict[str, Any]:
    """
    Process HealthLake export job status change events.
    
    Args:
        event_detail: Event detail information
        event_time: Event timestamp
        
    Returns:
        Processing result dictionary
    """
    job_status = event_detail.get('jobStatus', 'UNKNOWN')
    job_id = event_detail.get('jobId', 'UNKNOWN')
    message = event_detail.get('message', '')
    
    logger.info(f"Processing export job event - ID: {job_id}, Status: {job_status}")
    
    if job_status == 'COMPLETED':
        logger.info(f"Export job {job_id} completed successfully")
        return handle_successful_export(job_id, event_detail)
    elif job_status == 'FAILED':
        logger.error(f"Export job {job_id} failed: {message}")
        return handle_failed_export(job_id, event_detail)
    elif job_status == 'IN_PROGRESS':
        logger.info(f"Export job {job_id} is in progress")
        return {"status": "monitoring", "job_id": job_id}
    else:
        logger.warning(f"Unknown export job status: {job_status}")
        return {"status": "unknown", "job_id": job_id, "job_status": job_status}


def process_datastore_event(event_detail: Dict[str, Any], event_time: str) -> Dict[str, Any]:
    """
    Process HealthLake data store status change events.
    
    Args:
        event_detail: Event detail information
        event_time: Event timestamp
        
    Returns:
        Processing result dictionary
    """
    datastore_status = event_detail.get('datastoreStatus', 'UNKNOWN')
    datastore_id = event_detail.get('datastoreId', 'UNKNOWN')
    
    logger.info(f"Processing datastore event - ID: {datastore_id}, Status: {datastore_status}")
    
    if datastore_status == 'ACTIVE':
        logger.info(f"Datastore {datastore_id} is now active and ready for use")
    elif datastore_status == 'CREATING':
        logger.info(f"Datastore {datastore_id} is being created")
    elif datastore_status == 'DELETING':
        logger.info(f"Datastore {datastore_id} is being deleted")
    elif datastore_status == 'DELETED':
        logger.info(f"Datastore {datastore_id} has been deleted")
    else:
        logger.warning(f"Unknown datastore status: {datastore_status}")
    
    return {"status": "processed", "datastore_id": datastore_id, "datastore_status": datastore_status}


def handle_successful_import(job_id: str, event_detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle successful import job completion.
    
    Args:
        job_id: Import job ID
        event_detail: Event detail information
        
    Returns:
        Processing result dictionary
    """
    try:
        # Get detailed job information
        job_info = get_import_job_details(job_id)
        
        # Log import statistics
        if job_info:
            log_import_statistics(job_id, job_info)
        
        return {
            "status": "completed",
            "job_id": job_id,
            "action": "import_successful",
            "statistics": job_info.get('JobStatistics', {}) if job_info else {}
        }
        
    except Exception as e:
        logger.error(f"Error handling successful import for job {job_id}: {str(e)}")
        return {"status": "error", "job_id": job_id, "error": str(e)}


def handle_failed_import(job_id: str, event_detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle failed import job.
    
    Args:
        job_id: Import job ID
        event_detail: Event detail information
        
    Returns:
        Processing result dictionary
    """
    try:
        # Get detailed job information for troubleshooting
        job_info = get_import_job_details(job_id)
        
        # Log failure details
        if job_info:
            logger.error(f"Import job failure details: {json.dumps(job_info, indent=2)}")
        
        return {
            "status": "failed",
            "job_id": job_id,
            "action": "import_failed",
            "error_message": event_detail.get('message', 'Unknown error')
        }
        
    except Exception as e:
        logger.error(f"Error handling failed import for job {job_id}: {str(e)}")
        return {"status": "error", "job_id": job_id, "error": str(e)}


def handle_successful_export(job_id: str, event_detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle successful export job completion.
    
    Args:
        job_id: Export job ID
        event_detail: Event detail information
        
    Returns:
        Processing result dictionary
    """
    try:
        # Get detailed job information
        job_info = get_export_job_details(job_id)
        
        # Log export statistics
        if job_info:
            log_export_statistics(job_id, job_info)
        
        return {
            "status": "completed",
            "job_id": job_id,
            "action": "export_successful",
            "statistics": job_info.get('JobStatistics', {}) if job_info else {}
        }
        
    except Exception as e:
        logger.error(f"Error handling successful export for job {job_id}: {str(e)}")
        return {"status": "error", "job_id": job_id, "error": str(e)}


def handle_failed_export(job_id: str, event_detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle failed export job.
    
    Args:
        job_id: Export job ID
        event_detail: Event detail information
        
    Returns:
        Processing result dictionary
    """
    try:
        # Get detailed job information for troubleshooting
        job_info = get_export_job_details(job_id)
        
        # Log failure details
        if job_info:
            logger.error(f"Export job failure details: {json.dumps(job_info, indent=2)}")
        
        return {
            "status": "failed",
            "job_id": job_id,
            "action": "export_failed",
            "error_message": event_detail.get('message', 'Unknown error')
        }
        
    except Exception as e:
        logger.error(f"Error handling failed export for job {job_id}: {str(e)}")
        return {"status": "error", "job_id": job_id, "error": str(e)}


def get_import_job_details(job_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve detailed information about an import job.
    
    Args:
        job_id: Import job ID
        
    Returns:
        Job details dictionary or None if error
    """
    try:
        response = healthlake.describe_fhir_import_job(
            DatastoreId=DATASTORE_ID,
            JobId=job_id
        )
        return response.get('ImportJobProperties', {})
    except Exception as e:
        logger.error(f"Error getting import job details for {job_id}: {str(e)}")
        return None


def get_export_job_details(job_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve detailed information about an export job.
    
    Args:
        job_id: Export job ID
        
    Returns:
        Job details dictionary or None if error
    """
    try:
        response = healthlake.describe_fhir_export_job(
            DatastoreId=DATASTORE_ID,
            JobId=job_id
        )
        return response.get('ExportJobProperties', {})
    except Exception as e:
        logger.error(f"Error getting export job details for {job_id}: {str(e)}")
        return None


def log_import_statistics(job_id: str, job_info: Dict[str, Any]) -> None:
    """
    Log import job statistics for monitoring and analysis.
    
    Args:
        job_id: Import job ID
        job_info: Job information dictionary
    """
    try:
        stats = job_info.get('JobStatistics', {})
        
        # Log key statistics
        files_read = stats.get('FilesRead', 0)
        resources_scanned = stats.get('ResourcesScanned', 0)
        resources_imported = stats.get('ResourcesImported', 0)
        resources_failed = stats.get('ResourcesWithCustomerError', 0)
        
        logger.info(f"Import Job {job_id} Statistics:")
        logger.info(f"  - Files Read: {files_read}")
        logger.info(f"  - Resources Scanned: {resources_scanned}")
        logger.info(f"  - Resources Imported: {resources_imported}")
        logger.info(f"  - Resources Failed: {resources_failed}")
        
    except Exception as e:
        logger.error(f"Error logging import statistics: {str(e)}")


def log_export_statistics(job_id: str, job_info: Dict[str, Any]) -> None:
    """
    Log export job statistics for monitoring and analysis.
    
    Args:
        job_id: Export job ID
        job_info: Job information dictionary
    """
    try:
        stats = job_info.get('JobStatistics', {})
        
        # Log key statistics
        files_written = stats.get('FilesWritten', 0)
        resources_exported = stats.get('ResourcesExported', 0)
        
        logger.info(f"Export Job {job_id} Statistics:")
        logger.info(f"  - Files Written: {files_written}")
        logger.info(f"  - Resources Exported: {resources_exported}")
        
    except Exception as e:
        logger.error(f"Error logging export statistics: {str(e)}")


def publish_metrics(event_type: str, event_detail: Dict[str, Any]) -> None:
    """
    Publish custom CloudWatch metrics for monitoring.
    
    Args:
        event_type: Type of HealthLake event
        event_detail: Event detail information
    """
    try:
        namespace = "HealthLake/Pipeline"
        
        # Determine metric name based on event type
        if 'Import Job' in event_type:
            metric_name = "ImportJobEvents"
            job_status = event_detail.get('jobStatus', 'UNKNOWN')
            dimensions = [{'Name': 'JobStatus', 'Value': job_status}]
        elif 'Export Job' in event_type:
            metric_name = "ExportJobEvents"
            job_status = event_detail.get('jobStatus', 'UNKNOWN')
            dimensions = [{'Name': 'JobStatus', 'Value': job_status}]
        elif 'Data Store' in event_type:
            metric_name = "DataStoreEvents"
            datastore_status = event_detail.get('datastoreStatus', 'UNKNOWN')
            dimensions = [{'Name': 'DataStoreStatus', 'Value': datastore_status}]
        else:
            metric_name = "UnknownEvents"
            dimensions = []
        
        # Publish metric
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Dimensions': dimensions,
                    'Value': 1.0,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
    except Exception as e:
        logger.error(f"Error publishing metrics: {str(e)}")


def create_response(status_code: int, message: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Create a standardized Lambda response.
    
    Args:
        status_code: HTTP status code
        message: Response message
        data: Optional additional data
        
    Returns:
        Response dictionary
    """
    response = {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'timestamp': datetime.utcnow().isoformat(),
            'data': data or {}
        })
    }
    
    return response