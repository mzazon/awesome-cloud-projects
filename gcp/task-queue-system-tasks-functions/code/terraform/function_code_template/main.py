#!/usr/bin/env python3
"""
Cloud Function for processing background tasks from Cloud Tasks queue.

This function demonstrates professional task processing patterns including:
- Error handling and structured logging
- Multiple task type processing
- Cloud Storage integration
- Proper HTTP response handling
"""

import functions_framework
import json
import logging
import os
from datetime import datetime
from google.cloud import storage
from google.cloud import logging as cloud_logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Cloud Logging client
try:
    cloud_logging_client = cloud_logging.Client()
    cloud_logging_client.setup_logging()
except Exception as e:
    logger.warning(f"Cloud Logging setup failed: {e}")

@functions_framework.http
def task_processor(request):
    """
    Process background tasks from Cloud Tasks queue.
    
    This function handles various types of background tasks including:
    - File processing tasks
    - Email sending tasks (simulated)
    - Custom task types
    
    Args:
        request: HTTP request object from Cloud Tasks
        
    Returns:
        tuple: (response_data, status_code)
    """
    try:
        # Log the incoming request for debugging
        logger.info("Received task processing request")
        
        # Parse task payload from request
        task_data = request.get_json(silent=True)
        if not task_data:
            logger.error("No task data received in request")
            return {"status": "error", "message": "No task data provided"}, 400
        
        # Extract common task fields
        task_type = task_data.get('task_type', 'unknown')
        task_id = task_data.get('task_id', f'task-{datetime.now().strftime("%Y%m%d-%H%M%S")}')
        created_at = task_data.get('created_at', datetime.now().isoformat())
        
        logger.info(f"Processing task {task_id} of type '{task_type}' created at {created_at}")
        
        # Route task to appropriate processor based on type
        if task_type == 'process_file':
            result = process_file_task(task_data, task_id)
        elif task_type == 'send_email':
            result = send_email_task(task_data, task_id)
        elif task_type == 'data_transform':
            result = data_transform_task(task_data, task_id)
        elif task_type == 'webhook_notification':
            result = webhook_notification_task(task_data, task_id)
        else:
            logger.warning(f"Unknown task type: {task_type}")
            result = {
                "status": "success", 
                "message": f"Unknown task type '{task_type}' - no processing performed",
                "task_id": task_id,
                "processed_at": datetime.now().isoformat()
            }
        
        logger.info(f"Task {task_id} completed successfully")
        return result, 200
        
    except Exception as e:
        error_msg = f"Task processing failed: {str(e)}"
        logger.error(error_msg, exc_info=True)
        
        return {
            "status": "error", 
            "message": error_msg,
            "task_id": task_data.get('task_id', 'unknown') if 'task_data' in locals() else 'unknown',
            "error_time": datetime.now().isoformat()
        }, 500

def process_file_task(task_data, task_id):
    """
    Process file-related background task.
    
    This demonstrates common file processing patterns like:
    - Content transformation
    - File uploads to Cloud Storage
    - Metadata generation
    
    Args:
        task_data (dict): Task payload data
        task_id (str): Unique task identifier
        
    Returns:
        dict: Processing result
    """
    try:
        filename = task_data.get('filename', f'processed-file-{task_id}.txt')
        content = task_data.get('content', 'Default task content')
        content_type = task_data.get('content_type', 'text/plain')
        
        logger.info(f"Processing file task: {filename}")
        
        # Initialize Cloud Storage client
        storage_client = storage.Client()
        bucket_name = os.environ.get('STORAGE_BUCKET')
        
        if not bucket_name:
            raise ValueError("STORAGE_BUCKET environment variable not set")
        
        bucket = storage_client.bucket(bucket_name)
        
        # Create processed content with metadata
        processed_content = generate_processed_content(content, task_id, task_data)
        
        # Upload to Cloud Storage with metadata
        blob_name = f"processed/{datetime.now().strftime('%Y/%m/%d')}/{filename}"
        blob = bucket.blob(blob_name)
        
        # Set custom metadata
        blob.metadata = {
            'task_id': task_id,
            'original_filename': filename,
            'processed_at': datetime.now().isoformat(),
            'processing_type': 'background_task',
            'content_length': str(len(processed_content))
        }
        
        # Upload the processed content
        blob.upload_from_string(
            processed_content,
            content_type=content_type
        )
        
        # Generate result
        result = {
            "status": "success",
            "message": f"File '{filename}' processed and saved successfully",
            "task_id": task_id,
            "processed_at": datetime.now().isoformat(),
            "output_path": f"gs://{bucket_name}/{blob_name}",
            "content_size": len(processed_content),
            "metadata": blob.metadata
        }
        
        logger.info(f"File processing completed for task {task_id}")
        return result
        
    except Exception as e:
        raise Exception(f"File processing failed for task {task_id}: {str(e)}")

def send_email_task(task_data, task_id):
    """
    Simulate email sending task.
    
    In production, this would integrate with:
    - SendGrid API
    - Mailgun API
    - Gmail API
    - Amazon SES
    
    Args:
        task_data (dict): Task payload data
        task_id (str): Unique task identifier
        
    Returns:
        dict: Processing result
    """
    try:
        recipient = task_data.get('recipient', 'user@example.com')
        subject = task_data.get('subject', 'Background Task Complete')
        body = task_data.get('body', 'Your background task has been processed successfully.')
        email_type = task_data.get('email_type', 'notification')
        
        logger.info(f"Processing email task for {recipient}: {subject}")
        
        # Simulate email processing delay
        import time
        processing_delay = task_data.get('processing_delay', 1)
        time.sleep(min(processing_delay, 5))  # Max 5 seconds delay
        
        # In production, replace this with actual email sending logic
        logger.info(f"Simulated email sent to {recipient} with subject: {subject}")
        
        # Log email details for audit trail
        email_log = {
            'task_id': task_id,
            'recipient': recipient,
            'subject': subject,
            'email_type': email_type,
            'sent_at': datetime.now().isoformat(),
            'status': 'sent'
        }
        
        # Store email log in Cloud Storage for audit purposes
        store_audit_log('email_logs', email_log, task_id)
        
        return {
            "status": "success",
            "message": f"Email sent to {recipient}",
            "task_id": task_id,
            "sent_at": datetime.now().isoformat(),
            "recipient": recipient,
            "subject": subject,
            "email_type": email_type
        }
        
    except Exception as e:
        raise Exception(f"Email sending failed for task {task_id}: {str(e)}")

def data_transform_task(task_data, task_id):
    """
    Handle data transformation tasks.
    
    This demonstrates common data processing patterns like:
    - JSON transformation
    - Data validation
    - Format conversion
    
    Args:
        task_data (dict): Task payload data
        task_id (str): Unique task identifier
        
    Returns:
        dict: Processing result
    """
    try:
        input_data = task_data.get('input_data', {})
        transform_type = task_data.get('transform_type', 'json_flatten')
        
        logger.info(f"Processing data transform task: {transform_type}")
        
        # Perform transformation based on type
        if transform_type == 'json_flatten':
            result_data = flatten_json(input_data)
        elif transform_type == 'data_validation':
            result_data = validate_data(input_data, task_data.get('validation_rules', {}))
        elif transform_type == 'format_conversion':
            result_data = convert_data_format(input_data, task_data.get('target_format', 'json'))
        else:
            result_data = input_data
            logger.warning(f"Unknown transform type: {transform_type}")
        
        # Store transformed data
        output_filename = f"transformed_data_{task_id}.json"
        store_processed_data('transformations', result_data, output_filename, task_id)
        
        return {
            "status": "success",
            "message": f"Data transformation '{transform_type}' completed",
            "task_id": task_id,
            "processed_at": datetime.now().isoformat(),
            "transform_type": transform_type,
            "input_records": len(input_data) if isinstance(input_data, (list, dict)) else 1,
            "output_records": len(result_data) if isinstance(result_data, (list, dict)) else 1
        }
        
    except Exception as e:
        raise Exception(f"Data transformation failed for task {task_id}: {str(e)}")

def webhook_notification_task(task_data, task_id):
    """
    Handle webhook notification tasks.
    
    This demonstrates how to send HTTP notifications to external systems.
    
    Args:
        task_data (dict): Task payload data
        task_id (str): Unique task identifier
        
    Returns:
        dict: Processing result
    """
    try:
        webhook_url = task_data.get('webhook_url')
        payload = task_data.get('payload', {})
        method = task_data.get('method', 'POST').upper()
        headers = task_data.get('headers', {'Content-Type': 'application/json'})
        
        if not webhook_url:
            raise ValueError("webhook_url is required for webhook tasks")
        
        logger.info(f"Processing webhook notification to: {webhook_url}")
        
        # In production, use requests library to send HTTP request
        # For this demo, we simulate the webhook call
        logger.info(f"Simulated {method} request to {webhook_url}")
        logger.info(f"Payload: {json.dumps(payload)}")
        
        # Store webhook log for audit purposes
        webhook_log = {
            'task_id': task_id,
            'webhook_url': webhook_url,
            'method': method,
            'payload': payload,
            'sent_at': datetime.now().isoformat(),
            'status': 'sent'
        }
        
        store_audit_log('webhook_logs', webhook_log, task_id)
        
        return {
            "status": "success",
            "message": f"Webhook notification sent to {webhook_url}",
            "task_id": task_id,
            "sent_at": datetime.now().isoformat(),
            "webhook_url": webhook_url,
            "method": method
        }
        
    except Exception as e:
        raise Exception(f"Webhook notification failed for task {task_id}: {str(e)}")

# Helper functions

def generate_processed_content(original_content, task_id, task_data):
    """Generate processed content with metadata and transformations."""
    processing_timestamp = datetime.now().isoformat()
    
    processed_content = f"""# Processed Task Report
Task ID: {task_id}
Processed At: {processing_timestamp}
Processing Status: Complete

## Original Content
{original_content}

## Processing Metadata
- Task Type: {task_data.get('task_type', 'unknown')}
- Created At: {task_data.get('created_at', 'unknown')}
- Content Length: {len(original_content)} characters
- Processing Node: Cloud Function Gen2

## Processing Results
✅ Content successfully processed
✅ Metadata extracted and stored
✅ Task completed without errors

---
Generated by Task Queue System
"""
    return processed_content

def flatten_json(data):
    """Flatten nested JSON structure."""
    def _flatten(obj, prefix=''):
        items = []
        if isinstance(obj, dict):
            for key, value in obj.items():
                new_key = f"{prefix}.{key}" if prefix else key
                if isinstance(value, (dict, list)):
                    items.extend(_flatten(value, new_key).items())
                else:
                    items.append((new_key, value))
        elif isinstance(obj, list):
            for i, value in enumerate(obj):
                new_key = f"{prefix}[{i}]"
                if isinstance(value, (dict, list)):
                    items.extend(_flatten(value, new_key).items())
                else:
                    items.append((new_key, value))
        return dict(items)
    
    return _flatten(data)

def validate_data(data, validation_rules):
    """Validate data against provided rules."""
    validated_data = {
        'original_data': data,
        'validation_results': {},
        'is_valid': True,
        'validation_errors': []
    }
    
    for field, rules in validation_rules.items():
        if field in data:
            value = data[field]
            field_valid = True
            
            if 'type' in rules and not isinstance(value, eval(rules['type'])):
                field_valid = False
                validated_data['validation_errors'].append(f"Field {field} type mismatch")
            
            if 'required' in rules and rules['required'] and not value:
                field_valid = False
                validated_data['validation_errors'].append(f"Field {field} is required")
            
            validated_data['validation_results'][field] = field_valid
            if not field_valid:
                validated_data['is_valid'] = False
    
    return validated_data

def convert_data_format(data, target_format):
    """Convert data to target format."""
    if target_format.lower() == 'json':
        return data  # Already in JSON format
    elif target_format.lower() == 'csv':
        # Simple CSV conversion for demo
        if isinstance(data, list) and all(isinstance(item, dict) for item in data):
            csv_data = []
            if data:
                headers = list(data[0].keys())
                csv_data.append(','.join(headers))
                for item in data:
                    csv_data.append(','.join(str(item.get(h, '')) for h in headers))
            return '\n'.join(csv_data)
    
    return data  # Return original if conversion not supported

def store_processed_data(category, data, filename, task_id):
    """Store processed data in Cloud Storage."""
    try:
        storage_client = storage.Client()
        bucket_name = os.environ.get('STORAGE_BUCKET')
        
        if bucket_name:
            bucket = storage_client.bucket(bucket_name)
            blob_name = f"{category}/{datetime.now().strftime('%Y/%m/%d')}/{filename}"
            blob = bucket.blob(blob_name)
            
            blob.metadata = {
                'task_id': task_id,
                'category': category,
                'stored_at': datetime.now().isoformat()
            }
            
            blob.upload_from_string(
                json.dumps(data, indent=2),
                content_type='application/json'
            )
            
            logger.info(f"Data stored: gs://{bucket_name}/{blob_name}")
    except Exception as e:
        logger.error(f"Failed to store processed data: {e}")

def store_audit_log(log_type, log_data, task_id):
    """Store audit logs in Cloud Storage."""
    try:
        storage_client = storage.Client()
        bucket_name = os.environ.get('STORAGE_BUCKET')
        
        if bucket_name:
            bucket = storage_client.bucket(bucket_name)
            log_filename = f"{log_type}_{task_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            blob_name = f"audit_logs/{log_type}/{datetime.now().strftime('%Y/%m/%d')}/{log_filename}"
            blob = bucket.blob(blob_name)
            
            blob.upload_from_string(
                json.dumps(log_data, indent=2),
                content_type='application/json'
            )
            
            logger.info(f"Audit log stored: gs://{bucket_name}/{blob_name}")
    except Exception as e:
        logger.error(f"Failed to store audit log: {e}")

if __name__ == "__main__":
    # For local testing
    print("Task processor function loaded successfully")