"""
Cloud Function for Invoice Approval Notifications
This function processes invoice data and sends approval notifications via email
based on configurable business rules and approval thresholds.
"""

import json
import base64
import os
import logging
from typing import Dict, Any, Tuple
from google.cloud import tasks_v2
from google.cloud import secretmanager
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment variables with template substitution
MANAGER_EMAIL = "${manager_email}"
DIRECTOR_EMAIL = "${director_email}"
EXECUTIVE_EMAIL = "${executive_email}"
MANAGER_THRESHOLD = ${manager_threshold}
DIRECTOR_THRESHOLD = ${director_threshold}
EXECUTIVE_THRESHOLD = ${executive_threshold}

# Runtime environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', 'default-project')
TASK_QUEUE_NAME = os.environ.get('TASK_QUEUE_NAME', 'approval-queue')
TASK_QUEUE_LOCATION = os.environ.get('TASK_QUEUE_LOCATION', 'us-central1')

@functions_framework.http
def send_approval_notification(request):
    """
    Cloud Function entry point for sending invoice approval notifications.
    
    This function processes invoice data from Cloud Workflows and routes
    approval notifications to the appropriate stakeholders based on
    invoice amounts and business rules.
    
    Args:
        request: HTTP request object containing invoice data
        
    Returns:
        JSON response with processing status and details
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            logger.error("No JSON data received in request")
            return {'status': 'error', 'message': 'No JSON data provided'}, 400
        
        # Extract invoice data from request
        invoice_data = request_json.get('invoice_data', {})
        if not invoice_data:
            logger.error("No invoice data found in request")
            return {'status': 'error', 'message': 'No invoice data provided'}, 400
        
        # Process invoice for approval routing
        result = process_invoice_approval(invoice_data, request_json)
        
        logger.info(f"Successfully processed invoice approval: {result}")
        return result
    
    except Exception as e:
        error_message = f"Error processing invoice approval: {str(e)}"
        logger.error(error_message)
        return {'status': 'error', 'message': error_message}, 500

def process_invoice_approval(invoice_data: Dict[str, Any], request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process invoice data and determine approval routing.
    
    Args:
        invoice_data: Structured invoice data from Document AI
        request_data: Full request data from workflow
        
    Returns:
        Dictionary containing processing results and approval routing information
    """
    # Extract and validate invoice details
    vendor_name = invoice_data.get('supplier_name', 'Unknown Vendor')
    invoice_number = invoice_data.get('invoice_id', 'N/A')
    invoice_date = invoice_data.get('invoice_date', 'N/A')
    due_date = invoice_data.get('due_date', 'N/A')
    
    # Parse and validate invoice amount
    amount_str = invoice_data.get('total_amount', '0')
    try:
        # Remove currency symbols and parse amount
        amount_clean = ''.join(filter(lambda x: x.isdigit() or x == '.', str(amount_str)))
        approval_amount = float(amount_clean) if amount_clean else 0.0
    except (ValueError, TypeError) as e:
        logger.warning(f"Unable to parse invoice amount '{amount_str}': {e}")
        approval_amount = 0.0
    
    # Determine approval routing based on amount
    approver_info = determine_approver(approval_amount)
    
    # Log approval routing decision
    logger.info(f"Invoice routing - Amount: ${approval_amount}, Approver: {approver_info['level']}")
    
    # Send notification (in production, this would integrate with Gmail API)
    notification_result = send_email_notification(
        approver_info['email'],
        invoice_data,
        vendor_name,
        invoice_number,
        approval_amount,
        approver_info['level']
    )
    
    # Prepare response with approval routing information
    response = {
        'status': 'success',
        'invoice_details': {
            'vendor_name': vendor_name,
            'invoice_number': invoice_number,
            'invoice_date': invoice_date,
            'due_date': due_date,
            'amount': approval_amount
        },
        'approval_routing': {
            'approver_email': approver_info['email'],
            'approval_level': approver_info['level'],
            'threshold_used': approver_info['threshold']
        },
        'notification_sent': notification_result['sent'],
        'processing_timestamp': request_data.get('timestamp', 'N/A')
    }
    
    return response

def determine_approver(amount: float) -> Dict[str, Any]:
    """
    Determine the appropriate approver based on invoice amount.
    
    Args:
        amount: Invoice amount in USD
        
    Returns:
        Dictionary with approver email, level, and threshold information
    """
    if amount < MANAGER_THRESHOLD:
        return {
            'email': MANAGER_EMAIL,
            'level': 'manager',
            'threshold': MANAGER_THRESHOLD
        }
    elif amount < DIRECTOR_THRESHOLD:
        return {
            'email': DIRECTOR_EMAIL,
            'level': 'director', 
            'threshold': DIRECTOR_THRESHOLD
        }
    else:
        return {
            'email': EXECUTIVE_EMAIL,
            'level': 'executive',
            'threshold': EXECUTIVE_THRESHOLD
        }

def send_email_notification(to_email: str, invoice_data: Dict[str, Any], 
                          vendor: str, invoice_id: str, amount: float, 
                          approval_level: str) -> Dict[str, Any]:
    """
    Send email notification for invoice approval.
    
    In production, this would integrate with Gmail API or other email service.
    For this implementation, we log the notification details.
    
    Args:
        to_email: Recipient email address
        invoice_data: Complete invoice data from Document AI
        vendor: Vendor/supplier name
        invoice_id: Invoice number/ID
        amount: Invoice amount
        approval_level: Required approval level (manager/director/executive)
        
    Returns:
        Dictionary with notification status and details
    """
    try:
        # Construct email content
        subject = f"Invoice Approval Required: {vendor} - ${amount:,.2f}"
        
        body = f"""
        Invoice Approval Request
        
        An invoice requires your approval:
        
        Vendor/Supplier: {vendor}
        Invoice Number: {invoice_id}
        Amount: ${amount:,.2f}
        Invoice Date: {invoice_data.get('invoice_date', 'N/A')}
        Due Date: {invoice_data.get('due_date', 'N/A')}
        
        Approval Level: {approval_level.title()}
        
        Please review the invoice details and provide approval through
        your organization's approval system.
        
        For questions about this invoice, please contact the finance team.
        
        This is an automated notification from the Invoice Processing System.
        """
        
        # Log notification details (in production, send actual email)
        logger.info(f"Email notification prepared for {to_email}")
        logger.info(f"Subject: {subject}")
        logger.info(f"Approval Level: {approval_level}")
        logger.info(f"Invoice Amount: ${amount:,.2f}")
        
        # In production environment, implement actual email sending:
        # - Use Gmail API with proper OAuth2 authentication
        # - Or integrate with SendGrid, Mailgun, or similar service
        # - Include proper error handling and retry logic
        # - Add HTML email templates for better formatting
        # - Include invoice attachments when available
        
        # Simulate successful email delivery
        return {
            'sent': True,
            'recipient': to_email,
            'subject': subject,
            'approval_level': approval_level,
            'timestamp': 'simulated_timestamp'
        }
        
    except Exception as e:
        error_message = f"Failed to send email notification: {str(e)}"
        logger.error(error_message)
        return {
            'sent': False,
            'error': error_message,
            'recipient': to_email
        }

def validate_invoice_data(invoice_data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Validate invoice data completeness and accuracy.
    
    Args:
        invoice_data: Invoice data extracted by Document AI
        
    Returns:
        Tuple of (is_valid, error_message)
    """
    required_fields = ['supplier_name', 'total_amount']
    
    for field in required_fields:
        if not invoice_data.get(field):
            return False, f"Missing required field: {field}"
    
    # Validate amount is parseable
    try:
        amount_str = invoice_data.get('total_amount', '0')
        float(''.join(filter(lambda x: x.isdigit() or x == '.', str(amount_str))))
    except (ValueError, TypeError):
        return False, f"Invalid amount format: {amount_str}"
    
    return True, "Valid"

def get_business_rules() -> Dict[str, Any]:
    """
    Get business rules for invoice processing.
    
    In production, these could be stored in Cloud Firestore,
    Cloud SQL, or retrieved from a configuration service.
    
    Returns:
        Dictionary containing business rules and thresholds
    """
    return {
        'approval_thresholds': {
            'manager': MANAGER_THRESHOLD,
            'director': DIRECTOR_THRESHOLD,
            'executive': EXECUTIVE_THRESHOLD
        },
        'notification_emails': {
            'manager': MANAGER_EMAIL,
            'director': DIRECTOR_EMAIL,
            'executive': EXECUTIVE_EMAIL
        },
        'validation_rules': {
            'required_fields': ['supplier_name', 'total_amount'],
            'max_amount': 1000000,  # $1M maximum
            'min_amount': 1         # $1 minimum
        }
    }

def log_audit_event(event_type: str, invoice_data: Dict[str, Any], 
                   details: Dict[str, Any]) -> None:
    """
    Log audit events for compliance and monitoring.
    
    Args:
        event_type: Type of audit event (approval_request, notification_sent, etc.)
        invoice_data: Invoice data for context
        details: Additional event details
    """
    audit_entry = {
        'event_type': event_type,
        'timestamp': 'current_timestamp',  # Use actual timestamp in production
        'project_id': PROJECT_ID,
        'invoice_id': invoice_data.get('invoice_id', 'unknown'),
        'vendor': invoice_data.get('supplier_name', 'unknown'),
        'amount': invoice_data.get('total_amount', 0),
        'details': details
    }
    
    # Log to Cloud Logging for audit trail
    logger.info(f"AUDIT_EVENT: {json.dumps(audit_entry)}")