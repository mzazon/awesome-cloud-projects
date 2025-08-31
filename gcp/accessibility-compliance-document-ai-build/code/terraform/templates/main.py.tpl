import json
import base64
import os
import logging
from typing import Dict, Any, Optional
from google.cloud import pubsub_v1
from google.cloud import storage
from google.cloud import secretmanager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_compliance_alert(event: Dict[str, Any], context: Any) -> str:
    """
    Process Security Command Center findings for accessibility compliance.
    
    This function receives Pub/Sub messages containing accessibility compliance
    findings and processes them to send notifications via configured channels.
    
    Args:
        event: Pub/Sub event data containing the compliance finding
        context: Cloud Functions context object
        
    Returns:
        str: Status message indicating processing result
    """
    
    try:
        # Extract environment variables
        project_id = os.environ.get('PROJECT_ID', '${project_id}')
        topic_name = os.environ.get('TOPIC_NAME', '')
        bucket_name = os.environ.get('BUCKET_NAME', '')
        enable_email = os.environ.get('ENABLE_EMAIL', 'false').lower() == 'true'
        notification_email = os.environ.get('NOTIFICATION_EMAIL', '')
        
        logger.info(f"Processing compliance alert for project: {project_id}")
        
        # Decode Pub/Sub message
        if 'data' in event:
            try:
                message_data = base64.b64decode(event['data']).decode('utf-8')
                finding_data = json.loads(message_data)
                logger.info(f"Decoded finding data: {finding_data.get('category', 'Unknown')}")
            except (json.JSONDecodeError, UnicodeDecodeError) as e:
                logger.error(f"Error decoding message data: {e}")
                return 'Error: Failed to decode message data'
        else:
            logger.warning("No data field in event")
            return 'Warning: No data in event'
        
        # Check if it's an accessibility compliance finding
        if finding_data.get('category') != 'ACCESSIBILITY_COMPLIANCE':
            logger.info(f"Skipping non-accessibility finding: {finding_data.get('category', 'Unknown')}")
            return 'Skipped: Not an accessibility compliance finding'
        
        # Extract finding details
        source_properties = finding_data.get('source_properties', {})
        file_path = source_properties.get('file_path', 'Unknown')
        violations_count = source_properties.get('violations_count', '0')
        high_severity_count = source_properties.get('high_severity', '0')
        
        # Determine severity level
        severity = 'HIGH' if int(high_severity_count) > 0 else 'MEDIUM'
        
        # Create alert message
        alert_message = f"""
🚨 Accessibility Compliance Alert

Severity: {severity}
File: {file_path}
Total Violations: {violations_count}
High Severity Issues: {high_severity_count}
Project: {project_id}

Please review the detailed compliance report for specific remediation steps.
Report Location: gs://{bucket_name}/reports/

Common Remediation Actions:
- Add alt text to images without alternative descriptions
- Fix heading structure to follow proper hierarchy (h1 → h2 → h3)
- Add labels to form inputs for screen reader compatibility
- Ensure proper language attributes on HTML elements

WCAG 2.1 Guidelines: https://www.w3.org/WAI/WCAG21/quickref/
        """.strip()
        
        logger.info(f"Generated alert message for {severity} severity finding")
        
        # Send notifications based on configuration
        notifications_sent = []
        
        # Console logging (always enabled)
        print(f"🔍 ACCESSIBILITY COMPLIANCE ALERT:")
        print(f"   Severity: {severity}")
        print(f"   File: {file_path}")
        print(f"   Violations: {violations_count}")
        print(f"   High Severity: {high_severity_count}")
        print(f"   Timestamp: {context.timestamp if context else 'Unknown'}")
        notifications_sent.append("console")
        
        # Email notifications (if enabled and configured)
        if enable_email and notification_email:
            try:
                send_email_notification(
                    notification_email, 
                    f"Accessibility Compliance Alert - {severity}", 
                    alert_message,
                    project_id
                )
                notifications_sent.append("email")
                logger.info(f"Email notification sent to: {notification_email}")
            except Exception as e:
                logger.error(f"Failed to send email notification: {e}")
        
        # Store alert details in Cloud Storage for audit trail
        try:
            store_alert_audit(
                bucket_name,
                finding_data,
                alert_message,
                project_id
            )
            notifications_sent.append("audit_log")
            logger.info("Alert details stored in audit log")
        except Exception as e:
            logger.error(f"Failed to store audit log: {e}")
        
        # Return success status
        result = f"Alert processed successfully. Notifications sent: {', '.join(notifications_sent)}"
        logger.info(result)
        return result
        
    except Exception as e:
        error_message = f"Error processing compliance alert: {str(e)}"
        logger.error(error_message)
        return error_message

def send_email_notification(email: str, subject: str, message: str, project_id: str) -> None:
    """
    Send email notification using available email service.
    
    Note: This is a placeholder implementation. In production, you would
    integrate with your preferred email service (SendGrid, Gmail API, etc.)
    
    Args:
        email: Recipient email address
        subject: Email subject line
        message: Email message body
        project_id: GCP project ID
    """
    
    # Placeholder for email integration
    # In production, integrate with:
    # - SendGrid API
    # - Gmail API
    # - Cloud Functions with SendGrid
    # - Third-party email service
    
    logger.info(f"EMAIL NOTIFICATION (placeholder):")
    logger.info(f"To: {email}")
    logger.info(f"Subject: {subject}")
    logger.info(f"Message preview: {message[:100]}...")
    
    # Example integration points:
    # 1. Use Secret Manager to store API keys
    # 2. Initialize email service client
    # 3. Send formatted email with HTML content
    # 4. Log delivery status

def store_alert_audit(bucket_name: str, finding_data: Dict[str, Any], 
                     alert_message: str, project_id: str) -> None:
    """
    Store alert details in Cloud Storage for compliance audit trail.
    
    Args:
        bucket_name: Cloud Storage bucket name
        finding_data: Original finding data from Security Command Center
        alert_message: Formatted alert message
        project_id: GCP project ID
    """
    
    if not bucket_name:
        logger.warning("No bucket name provided for audit storage")
        return
    
    try:
        # Initialize Cloud Storage client
        storage_client = storage.Client(project=project_id)
        bucket = storage_client.bucket(bucket_name)
        
        # Create audit record
        import datetime
        timestamp = datetime.datetime.utcnow().isoformat()
        
        audit_record = {
            'timestamp': timestamp,
            'event_type': 'accessibility_compliance_alert',
            'severity': 'HIGH' if int(finding_data.get('source_properties', {}).get('high_severity', '0')) > 0 else 'MEDIUM',
            'finding_data': finding_data,
            'alert_message': alert_message,
            'project_id': project_id,
            'processing_status': 'success'
        }
        
        # Generate unique filename
        file_path = finding_data.get('source_properties', {}).get('file_path', 'unknown')
        safe_file_path = file_path.replace('/', '_').replace('\\', '_')
        blob_name = f"audit/alerts/{timestamp}_{safe_file_path}_alert.json"
        
        # Upload audit record
        blob = bucket.blob(blob_name)
        blob.upload_from_string(
            json.dumps(audit_record, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Audit record stored: gs://{bucket_name}/{blob_name}")
        
    except Exception as e:
        logger.error(f"Failed to store audit record: {e}")
        raise

def get_secret(secret_id: str, project_id: str) -> Optional[str]:
    """
    Retrieve secret from Google Secret Manager.
    
    Args:
        secret_id: Secret identifier in Secret Manager
        project_id: GCP project ID
        
    Returns:
        str: Secret value or None if not found
    """
    
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        logger.error(f"Failed to retrieve secret {secret_id}: {e}")
        return None

# Health check endpoint for monitoring
def health_check(request) -> tuple:
    """
    Simple health check endpoint for Cloud Functions monitoring.
    
    Returns:
        tuple: (response_text, status_code)
    """
    
    try:
        project_id = os.environ.get('PROJECT_ID', 'unknown')
        function_name = os.environ.get('FUNCTION_NAME', 'compliance-notifier')
        
        health_status = {
            'status': 'healthy',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'project_id': project_id,
            'function_name': function_name,
            'version': '1.0'
        }
        
        return (json.dumps(health_status), 200)
        
    except Exception as e:
        error_response = {
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
        return (json.dumps(error_response), 500)