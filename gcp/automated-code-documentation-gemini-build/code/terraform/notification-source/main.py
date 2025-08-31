# Notification Cloud Function for documentation updates
# This function sends notifications when documentation is generated or updated

import json
import os
from google.cloud import storage
import functions_framework
from typing import Dict, Any
import datetime

@functions_framework.cloud_event
def notify_team(cloud_event) -> Dict[str, Any]:
    """
    Send notification when documentation is updated in Cloud Storage.
    
    This function is triggered by Eventarc when files are uploaded to the 
    documentation storage bucket. It processes the event and sends appropriate
    notifications to the team.
    
    Args:
        cloud_event: CloudEvent object containing storage event data
    
    Returns:
        Dictionary with notification status
    """
    
    try:
        # Parse the Cloud Storage event data
        event_data = cloud_event.data
        bucket_name = event_data.get('bucket', '')
        file_name = event_data.get('name', '')
        event_type = event_data.get('eventType', '')
        time_created = event_data.get('timeCreated', '')
        
        print(f"Processing event: {event_type} for file: {file_name} in bucket: {bucket_name}")
        
        # Check if this is a documentation-related file
        if not is_documentation_file(file_name):
            print(f"Ignoring non-documentation file: {file_name}")
            return {'status': 'ignored', 'reason': 'not a documentation file'}
        
        # Determine notification type based on file
        notification_type = determine_notification_type(file_name)
        
        # Generate and send notification
        message = generate_notification_message(
            bucket_name, file_name, notification_type, time_created
        )
        
        # Log the notification (in production, send to Slack, email, etc.)
        print(f"Documentation notification: {message}")
        
        # Here you can integrate with various notification services:
        # - Send email via SendGrid or Gmail API
        # - Post to Slack via webhook
        # - Send SMS via Twilio
        # - Create Pub/Sub message for further processing
        
        # Example: Send to Pub/Sub for additional processing
        send_to_pubsub(message, notification_type, file_name)
        
        return {
            'status': 'notification_sent',
            'file_name': file_name,
            'notification_type': notification_type,
            'timestamp': datetime.datetime.now().isoformat()
        }
        
    except Exception as e:
        print(f"Error processing notification: {str(e)}")
        return {
            'status': 'error',
            'message': str(e),
            'timestamp': datetime.datetime.now().isoformat()
        }

def is_documentation_file(file_name: str) -> bool:
    """
    Check if the uploaded file is a documentation file that should trigger notifications.
    
    Args:
        file_name: Name of the uploaded file
    
    Returns:
        True if the file should trigger a notification
    """
    
    # Documentation file patterns
    doc_patterns = [
        'api/',          # API documentation
        'readme/',       # README files
        'comments/',     # Enhanced code with comments
        'index.md',      # Documentation index
        'website/'       # Website files
    ]
    
    # Check if file matches any documentation pattern
    return any(pattern in file_name for pattern in doc_patterns)

def determine_notification_type(file_name: str) -> str:
    """
    Determine the type of notification based on the file path.
    
    Args:
        file_name: Name of the uploaded file
    
    Returns:
        Notification type string
    """
    
    if 'index.md' in file_name:
        return 'index_update'
    elif file_name.startswith('api/'):
        return 'api_documentation'
    elif file_name.startswith('readme/'):
        return 'readme_update'
    elif file_name.startswith('comments/'):
        return 'code_enhancement'
    elif file_name.startswith('website/'):
        return 'website_update'
    else:
        return 'general_documentation'

def generate_notification_message(bucket_name: str, file_name: str, 
                                notification_type: str, time_created: str) -> str:
    """
    Generate a formatted notification message based on the update type.
    
    Args:
        bucket_name: Name of the storage bucket
        file_name: Name of the uploaded file
        notification_type: Type of notification
        time_created: Timestamp when file was created
    
    Returns:
        Formatted notification message
    """
    
    messages = {
        'index_update': f"""
📚 **Documentation Index Updated!**

The documentation index has been refreshed with the latest changes.

🔗 **Quick Links:**
• Documentation Browser: https://console.cloud.google.com/storage/browser/{bucket_name}
• API Documentation: gs://{bucket_name}/api/
• README Files: gs://{bucket_name}/readme/
• Enhanced Code: gs://{bucket_name}/comments/

⏰ Updated: {time_created}
📁 File: {file_name}
        """,
        
        'api_documentation': f"""
📖 **New API Documentation Generated!**

Fresh API documentation has been created using AI analysis.

🔗 **Access:**
• Direct Link: gs://{bucket_name}/{file_name}
• Storage Browser: https://console.cloud.google.com/storage/browser/{bucket_name}/api/

⏰ Generated: {time_created}
🤖 Generated by: Gemini AI Documentation System
        """,
        
        'readme_update': f"""
📝 **README Documentation Updated!**

A new README file has been generated with project information and usage guidelines.

🔗 **Access:**
• Direct Link: gs://{bucket_name}/{file_name}
• Storage Browser: https://console.cloud.google.com/storage/browser/{bucket_name}/readme/

⏰ Generated: {time_created}
💡 Tip: Review the generated content and customize as needed for your project.
        """,
        
        'code_enhancement': f"""
💬 **Code Comments Enhanced!**

AI has analyzed your code and added comprehensive inline comments.

🔗 **Access:**
• Direct Link: gs://{bucket_name}/{file_name}
• Storage Browser: https://console.cloud.google.com/storage/browser/{bucket_name}/comments/

⏰ Enhanced: {time_created}
🎯 Benefit: Improved code readability and maintainability
        """,
        
        'website_update': f"""
🌐 **Documentation Website Updated!**

The documentation website has been updated with new content.

🔗 **Access:**
• Website: https://storage.googleapis.com/{bucket_name}/website/index.html
• File: gs://{bucket_name}/{file_name}

⏰ Updated: {time_created}
        """,
        
        'general_documentation': f"""
📄 **Documentation Updated!**

New documentation has been generated and stored.

🔗 **Access:**
• File: gs://{bucket_name}/{file_name}
• Storage Browser: https://console.cloud.google.com/storage/browser/{bucket_name}

⏰ Updated: {time_created}
        """
    }
    
    return messages.get(notification_type, messages['general_documentation'])

def send_to_pubsub(message: str, notification_type: str, file_name: str) -> None:
    """
    Send notification to Pub/Sub for additional processing or routing.
    
    Args:
        message: Formatted notification message
        notification_type: Type of notification
        file_name: Name of the updated file
    """
    
    try:
        # This is a placeholder for Pub/Sub integration
        # In a real implementation, you would:
        # 1. Import google.cloud.pubsub_v1
        # 2. Create a publisher client
        # 3. Publish the message to a topic
        
        notification_data = {
            'message': message,
            'type': notification_type,
            'file_name': file_name,
            'timestamp': datetime.datetime.now().isoformat(),
            'source': 'documentation-automation'
        }
        
        print(f"Would send to Pub/Sub: {json.dumps(notification_data, indent=2)}")
        
    except Exception as e:
        print(f"Error sending to Pub/Sub: {str(e)}")

# Health check endpoint
@functions_framework.http
def health_check(request):
    """Simple health check endpoint for monitoring the notification function."""
    return {
        'status': 'healthy',
        'timestamp': datetime.datetime.now().isoformat(),
        'service': 'notification-processor'
    }