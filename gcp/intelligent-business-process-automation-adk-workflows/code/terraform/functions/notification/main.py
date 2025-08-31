"""
Business Process Notification Cloud Function

This function sends process notifications to stakeholders with audit logging.
Designed for deployment via Terraform with Cloud SQL connectivity.
"""

import functions_framework
import json
import os
import pg8000
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def send_notification(request):
    """
    Send process notifications to stakeholders with comprehensive audit logging.
    
    Expected request format:
    {
        "request_id": "string",
        "type": "approval_requested|process_completed|status_update",
        "recipient_email": "string",
        "message": "string (optional)",
        "priority": "high|medium|low (optional)"
    }
    """
    try:
        # Enable CORS for web requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)

        # Set CORS headers for actual request
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }

        if request.method != 'POST':
            return ({'error': 'Method not allowed'}, 405, headers)
        
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({'error': 'No JSON data provided'}, 400, headers)
        
        # Extract required parameters
        request_id = request_json.get('request_id')
        notification_type = request_json.get('type')
        recipient = request_json.get('recipient_email')
        custom_message = request_json.get('message', '')
        priority = request_json.get('priority', 'medium')
        
        if not all([request_id, notification_type, recipient]):
            return ({'error': 'Missing required fields: request_id, type, recipient_email'}, 400, headers)
        
        if notification_type not in ['approval_requested', 'process_completed', 'status_update', 'error_notification']:
            return ({'error': 'Invalid notification type'}, 400, headers)
        
        logger.info(f"Sending notification: {request_id}, type: {notification_type}, recipient: {recipient}")
        
        try:
            conn = get_database_connection()
            cursor = conn.cursor()
            
            # Get process details from database
            cursor.execute("""
                SELECT pr.process_type, pr.status, pr.requester_email, pr.created_at, pr.request_data, pr.priority
                FROM process_requests pr
                WHERE pr.request_id = %s
            """, (request_id,))
            
            process_data = cursor.fetchone()
            if not process_data:
                conn.close()
                return ({'error': f'Process request {request_id} not found'}, 404, headers)
            
            process_type, status, requester, created_at, request_data, process_priority = process_data
            
            # Generate notification content based on type and process details
            notification_content = generate_notification_content(
                notification_type, request_id, process_type, status, 
                requester, created_at, request_data, custom_message, priority
            )
            
            # Send notification (in production, integrate with actual email/messaging service)
            notification_result = send_actual_notification(
                recipient, notification_content, notification_type, priority
            )
            
            # Log notification in audit trail
            audit_details = {
                'notification_type': notification_type,
                'recipient': recipient,
                'priority': priority,
                'notification_content': notification_content,
                'delivery_status': notification_result['status'],
                'custom_message': custom_message
            }
            
            cursor.execute("""
                INSERT INTO process_audit 
                (request_id, action, actor, details)
                VALUES (%s, %s, %s, %s)
            """, (request_id, f'Notification sent - {notification_type}', 'system', json.dumps(audit_details)))
            
            conn.commit()
            conn.close()
            
            logger.info(f"Successfully sent notification: {request_id} -> {recipient}")
            
            response_data = {
                'status': 'success',
                'request_id': request_id,
                'notification_type': notification_type,
                'recipient': recipient,
                'delivery_status': notification_result['status'],
                'sent_at': datetime.utcnow().isoformat() + 'Z'
            }
            
            return (response_data, 200, headers)
            
        except Exception as db_error:
            logger.error(f"Database error: {str(db_error)}")
            try:
                conn.close()
            except:
                pass
            return ({'error': 'Database operation failed', 'details': str(db_error)}, 500, headers)
        
    except Exception as e:
        logger.error(f"Unexpected error in send_notification: {str(e)}")
        return ({'error': 'Internal server error', 'details': str(e)}, 500, headers)


def get_database_connection():
    """
    Establish connection to Cloud SQL database.
    Supports both Unix socket (private) and TCP (public) connections.
    """
    project_id = os.environ.get('PROJECT_ID', '${project_id}')
    region = os.environ.get('REGION', '${region}')
    db_instance = os.environ.get('DB_INSTANCE', '${db_instance}')
    db_password = os.environ.get('DB_PASSWORD')
    
    if not db_password:
        raise ValueError("DB_PASSWORD environment variable not set")
    
    # Try Unix socket connection first (for private IP)
    db_socket_path = "/cloudsql"
    instance_connection_name = f"{project_id}:{region}:{db_instance}"
    
    try:
        # Attempt Unix socket connection
        unix_socket = f"{db_socket_path}/{instance_connection_name}/.s.PGSQL.5432"
        conn = pg8000.connect(
            user='postgres',
            password=db_password,
            unix_sock=unix_socket,
            database='business_processes'
        )
        logger.info("Connected to database via Unix socket")
        return conn
        
    except Exception as unix_error:
        logger.warning(f"Unix socket connection failed: {unix_error}")
        
        # Fallback to TCP connection (for public IP)
        try:
            conn = pg8000.connect(
                user='postgres',
                password=db_password,
                host='127.0.0.1',  # This would be the actual Cloud SQL IP
                port=5432,
                database='business_processes'
            )
            logger.info("Connected to database via TCP")
            return conn
            
        except Exception as tcp_error:
            logger.error(f"TCP connection failed: {tcp_error}")
            raise Exception(f"Failed to connect to database. Unix socket: {unix_error}, TCP: {tcp_error}")


def generate_notification_content(notification_type, request_id, process_type, status, 
                                requester, created_at, request_data, custom_message, priority):
    """
    Generate notification content based on type and process details.
    """
    
    # Process type friendly names
    process_names = {
        'expense_approval': 'Expense Approval',
        'leave_request': 'Leave Request', 
        'access_request': 'Access Request',
        'general_request': 'General Request'
    }
    
    friendly_process_type = process_names.get(process_type, process_type.replace('_', ' ').title())
    
    # Base notification content
    content = {
        'subject': '',
        'body': '',
        'priority': priority,
        'process_details': {
            'request_id': request_id,
            'process_type': friendly_process_type,
            'status': status.title(),
            'requester': requester,
            'created_at': created_at.isoformat() if hasattr(created_at, 'isoformat') else str(created_at),
            'request_data': request_data
        }
    }
    
    if notification_type == 'approval_requested':
        content['subject'] = f'Approval Required: {friendly_process_type} - {request_id}'
        content['body'] = f"""
        A new {friendly_process_type.lower()} requires your approval.
        
        Request ID: {request_id}
        Requester: {requester}
        Created: {created_at}
        Status: {status.title()}
        Priority: {priority.title()}
        
        Process Details: {json.dumps(request_data, indent=2)}
        
        {custom_message}
        
        Please review and approve or reject this request through the Business Process Automation system.
        """
        
    elif notification_type == 'process_completed':
        content['subject'] = f'Process Complete: {friendly_process_type} - {request_id}'
        content['body'] = f"""
        Your {friendly_process_type.lower()} has been completed.
        
        Request ID: {request_id}
        Final Status: {status.title()}
        Created: {created_at}
        
        Process Details: {json.dumps(request_data, indent=2)}
        
        {custom_message}
        
        This is an automated notification from the Business Process Automation system.
        """
        
    elif notification_type == 'status_update':
        content['subject'] = f'Status Update: {friendly_process_type} - {request_id}'
        content['body'] = f"""
        Your {friendly_process_type.lower()} status has been updated.
        
        Request ID: {request_id}
        Current Status: {status.title()}
        Requester: {requester}
        Created: {created_at}
        
        {custom_message}
        
        This is an automated notification from the Business Process Automation system.
        """
        
    elif notification_type == 'error_notification':
        content['subject'] = f'Process Error: {friendly_process_type} - {request_id}'
        content['body'] = f"""
        An error occurred while processing your {friendly_process_type.lower()}.
        
        Request ID: {request_id}
        Status: {status.title()}
        Created: {created_at}
        
        Error Details: {custom_message}
        
        Please contact system administrator for assistance.
        """
    
    return content


def send_actual_notification(recipient, content, notification_type, priority):
    """
    Send the actual notification via email, SMS, or other messaging service.
    In production, integrate with Google Cloud Pub/Sub, SendGrid, or similar service.
    """
    
    # For this example, we'll simulate sending and log the notification
    logger.info(f"NOTIFICATION SENT TO: {recipient}")
    logger.info(f"SUBJECT: {content['subject']}")
    logger.info(f"BODY: {content['body'][:200]}...")
    
    # In production, you would integrate with actual notification services:
    #
    # Email via SendGrid:
    # import sendgrid
    # sg = sendgrid.SendGridAPIClient(api_key=os.environ.get('SENDGRID_API_KEY'))
    # ...
    #
    # SMS via Twilio:
    # from twilio.rest import Client
    # client = Client(account_sid, auth_token)
    # ...
    #
    # Push notifications via Firebase:
    # import firebase_admin
    # ...
    #
    # Slack notifications:
    # import slack_sdk
    # ...
    
    # Simulate delivery status
    delivery_status = 'delivered'  # In production: 'delivered', 'failed', 'pending'
    
    return {
        'status': delivery_status,
        'delivery_id': f"notif_{datetime.utcnow().timestamp()}",
        'provider': 'simulated',
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    }


if __name__ == "__main__":
    # For local testing
    import sys
    from unittest.mock import Mock
    
    # Mock request for testing
    mock_request = Mock()
    mock_request.method = 'POST'
    mock_request.get_json.return_value = {
        'request_id': 'test-001',
        'type': 'approval_requested',
        'recipient_email': 'manager@company.com',
        'message': 'Urgent approval needed for expense report',
        'priority': 'high'
    }
    
    print("Testing notification function...")
    try:
        result = send_notification(mock_request)
        print(f"Result: {result}")
    except Exception as e:
        print(f"Error: {e}")