#!/usr/bin/env python3
"""
Workflow Handler Lambda Function for Content Moderation

This Lambda function is triggered by EventBridge events containing moderation
decisions and handles the workflow processing for approved, rejected, and
review content by moving files to appropriate buckets and sending notifications.

Author: AWS Recipe Generator
Version: 1.0
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS service clients
s3 = boto3.client('s3')
sns = boto3.client('sns')

# Environment variables
WORKFLOW_TYPE = os.environ.get('WORKFLOW_TYPE', '${workflow_type}')
TARGET_BUCKET = os.environ.get('TARGET_BUCKET', '${target_bucket}')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for workflow processing based on moderation decisions.
    
    Args:
        event: EventBridge event containing moderation decision details
        context: Lambda context object
        
    Returns:
        Dictionary containing response status and message
    """
    try:
        logger.info(f"Processing workflow event: {json.dumps(event)}")
        
        # Extract event details from EventBridge event
        detail = event['detail']
        source_bucket = detail['bucket']
        source_key = detail['key']
        decision = detail['decision']
        confidence = detail['confidence']
        reason = detail['reason']
        categories = detail.get('categories', [])
        timestamp = detail['timestamp']
        
        logger.info(f"Processing {decision} content: {source_key} with confidence {confidence}")
        
        # Create target key with organized folder structure
        target_key = create_target_key(source_key, decision)
        
        # Copy content to appropriate target bucket with metadata
        copy_result = copy_content_with_metadata(
            source_bucket, source_key, target_key, 
            decision, confidence, reason, timestamp
        )
        
        if not copy_result:
            logger.error(f"Failed to copy content {source_key}")
            return create_response(500, "Failed to copy content")
        
        # Send notification about the moderation decision
        notification_sent = send_moderation_notification(
            source_key, target_key, decision, confidence, 
            reason, categories, timestamp
        )
        
        if notification_sent:
            logger.info(f"Successfully processed {decision} workflow for {source_key}")
            return create_response(200, {
                'message': f'Content processed for {decision} workflow',
                'source_location': f's3://{source_bucket}/{source_key}',
                'target_location': f's3://{TARGET_BUCKET}/{target_key}',
                'notification_sent': True
            })
        else:
            logger.warning(f"Content copied but notification failed for {source_key}")
            return create_response(200, {
                'message': f'Content processed for {decision} workflow',
                'target_location': f's3://{TARGET_BUCKET}/{target_key}',
                'notification_sent': False
            })
            
    except Exception as e:
        logger.error(f"Error in {WORKFLOW_TYPE} workflow handler: {str(e)}", exc_info=True)
        return create_response(500, {'error': str(e), 'workflow': WORKFLOW_TYPE})

def create_target_key(source_key: str, decision: str) -> str:
    """
    Create organized target key with folder structure based on decision and date.
    
    Args:
        source_key: Original S3 object key
        decision: Moderation decision (approved, rejected, review)
        
    Returns:
        Formatted target key with folder structure
    """
    current_date = datetime.utcnow()
    date_prefix = current_date.strftime('%Y/%m/%d')
    
    # Clean source key to remove any existing folder structure
    filename = source_key.split('/')[-1]
    
    # Create target key with organized structure
    if decision == 'review':
        # Review items go to rejected bucket but with special prefix
        target_key = f"review/{date_prefix}/{filename}"
    else:
        target_key = f"{decision}/{date_prefix}/{filename}"
    
    return target_key

def copy_content_with_metadata(source_bucket: str, source_key: str, target_key: str,
                               decision: str, confidence: float, reason: str, 
                               timestamp: str) -> bool:
    """
    Copy content from source to target bucket with moderation metadata.
    
    Args:
        source_bucket: Source S3 bucket name
        source_key: Source S3 object key
        target_key: Target S3 object key
        decision: Moderation decision
        confidence: Confidence score
        reason: Moderation reason
        timestamp: Processing timestamp
        
    Returns:
        Boolean indicating success or failure
    """
    try:
        # Create copy source specification
        copy_source = {'Bucket': source_bucket, 'Key': source_key}
        
        # Prepare metadata for the copied object
        metadata = {
            'moderation-decision': decision,
            'moderation-confidence': str(confidence),
            'moderation-reason': reason.replace(',', ';'),  # Replace commas to avoid metadata issues
            'processed-timestamp': timestamp,
            'workflow-type': WORKFLOW_TYPE,
            'original-location': f"{source_bucket}/{source_key}"
        }
        
        # Copy object to target bucket with updated metadata
        s3.copy_object(
            CopySource=copy_source,
            Bucket=TARGET_BUCKET,
            Key=target_key,
            MetadataDirective='REPLACE',
            Metadata=metadata,
            ServerSideEncryption='AES256'  # Ensure copied content is encrypted
        )
        
        logger.info(f"Successfully copied content to s3://{TARGET_BUCKET}/{target_key}")
        return True
        
    except Exception as e:
        logger.error(f"Error copying content: {str(e)}")
        return False

def send_moderation_notification(source_key: str, target_key: str, decision: str,
                                confidence: float, reason: str, categories: list,
                                timestamp: str) -> bool:
    """
    Send SNS notification about moderation decision.
    
    Args:
        source_key: Original content key
        target_key: Target content key
        decision: Moderation decision
        confidence: Confidence score
        reason: Moderation reason
        categories: Policy violation categories
        timestamp: Processing timestamp
        
    Returns:
        Boolean indicating success or failure
    """
    try:
        # Create comprehensive notification message
        subject = f'Content Moderation Alert: {decision.title()} - {source_key}'
        
        message_body = f"""Content Moderation System Notification

MODERATION RESULT: {decision.upper()}
=====================================

Content Details:
- Original File: {source_key}
- Processing Time: {timestamp}
- Confidence Score: {confidence:.2f}
- Decision Reason: {reason}

Policy Analysis:
- Categories Flagged: {', '.join(categories) if categories else 'None'}
- Workflow Type: {WORKFLOW_TYPE}

Storage Information:
- Target Location: s3://{TARGET_BUCKET}/{target_key}
- Security: Content encrypted with AES256

Next Steps:
"""
        
        # Add workflow-specific next steps
        if decision == 'approved':
            message_body += """
- Content has been approved and moved to the approved content bucket
- Content is ready for publication or further processing
- No further action required unless additional review is needed
"""
        elif decision == 'rejected':
            message_body += """
- Content has been rejected due to policy violations
- Content has been quarantined in the rejected content bucket
- Review the flagged categories and take appropriate action
- Consider providing feedback to the content creator
"""
        elif decision == 'review':
            message_body += """
- Content requires human review due to borderline policy compliance
- Content has been queued for manual review
- A content moderator should examine this content within 24 hours
- Update content status after manual review is complete
"""
        
        message_body += f"""
System Information:
- Moderation System: Amazon Bedrock + EventBridge
- Timestamp: {datetime.utcnow().isoformat()}Z
- Environment: {os.environ.get('AWS_REGION', 'Unknown')}

This is an automated notification from the Content Moderation System.
"""
        
        # Publish notification to SNS topic
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message_body
        )
        
        logger.info(f"Successfully sent notification for {decision} decision")
        return True
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
        return False

def create_response(status_code: int, body: Any) -> Dict[str, Any]:
    """
    Create standardized Lambda response object.
    
    Args:
        status_code: HTTP status code
        body: Response body content
        
    Returns:
        Formatted Lambda response dictionary
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'X-Workflow-Type': WORKFLOW_TYPE
        },
        'body': json.dumps(body) if isinstance(body, (dict, list)) else str(body)
    }