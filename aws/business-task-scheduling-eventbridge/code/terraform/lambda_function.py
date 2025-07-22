"""
Business Task Processor Lambda Function

This Lambda function handles automated business tasks including:
- Daily report generation
- Hourly data processing
- Weekly business notifications

The function is triggered by EventBridge Scheduler and processes different
task types based on the input event.
"""

import json
import boto3
import datetime
import os
import logging
from io import StringIO
import csv
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

# Environment variables
BUCKET_NAME = os.environ.get('BUCKET_NAME')
TOPIC_ARN = os.environ.get('TOPIC_ARN')
DEBUG_LOGGING = os.environ.get('DEBUG_LOGGING', 'false').lower() == 'true'

if DEBUG_LOGGING:
    logger.setLevel(logging.DEBUG)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function.
    
    Args:
        event: Event data from EventBridge Scheduler
        context: Lambda context object
        
    Returns:
        Response dictionary with status and results
    """
    try:
        logger.info(f"Processing business task with event: {json.dumps(event)}")
        
        # Get task type from event (default to 'report' for backward compatibility)
        task_type = event.get('task_type', 'report')
        
        # Validate environment variables
        if not BUCKET_NAME or not TOPIC_ARN:
            raise ValueError("Missing required environment variables: BUCKET_NAME or TOPIC_ARN")
        
        # Process the task based on type
        if task_type == 'report':
            result = generate_daily_report()
        elif task_type == 'data_processing':
            result = process_business_data()
        elif task_type == 'notification':
            result = send_business_notification()
        else:
            raise ValueError(f"Unknown task type: {task_type}")
        
        # Send success notification
        send_notification(
            subject=f"✅ Business Task Completed - {task_type.title()}",
            message=f"Business task completed successfully: {result}",
            is_success=True
        )
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Task completed successfully',
                'task_type': task_type,
                'result': result,
                'timestamp': datetime.datetime.now().isoformat(),
                'request_id': context.aws_request_id
            })
        }
        
        logger.info(f"Task completed successfully: {result}")
        return response
        
    except Exception as e:
        error_message = f"Business task failed: {str(e)}"
        logger.error(error_message, exc_info=True)
        
        # Send failure notification
        send_notification(
            subject=f"❌ Business Task Failed - {event.get('task_type', 'unknown')}",
            message=error_message,
            is_success=False
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'task_type': event.get('task_type', 'unknown'),
                'timestamp': datetime.datetime.now().isoformat(),
                'request_id': context.aws_request_id if context else 'unknown'
            })
        }


def generate_daily_report() -> str:
    """
    Generate a daily business report and store it in S3.
    
    Returns:
        String describing the generated report
    """
    logger.info("Starting daily report generation")
    
    try:
        # Generate sample business report data
        current_date = datetime.datetime.now()
        report_data = [
            ['Date', 'Revenue', 'Orders', 'Customers', 'Conversion Rate'],
            [
                current_date.strftime('%Y-%m-%d'),
                '12,500',
                '45',
                '38',
                '84.4%'
            ],
            [
                (current_date - datetime.timedelta(days=1)).strftime('%Y-%m-%d'),
                '15,800',
                '52',
                '41',
                '78.8%'
            ],
            [
                (current_date - datetime.timedelta(days=2)).strftime('%Y-%m-%d'),
                '11,200',
                '38',
                '32',
                '84.2%'
            ]
        ]
        
        # Convert to CSV format
        csv_buffer = StringIO()
        writer = csv.writer(csv_buffer)
        writer.writerows(report_data)
        csv_content = csv_buffer.getvalue()
        
        # Generate report filename with timestamp
        report_key = f"reports/daily-report-{current_date.strftime('%Y%m%d-%H%M%S')}.csv"
        
        # Upload to S3 with metadata
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=report_key,
            Body=csv_content,
            ContentType='text/csv',
            Metadata={
                'generated-by': 'business-automation-lambda',
                'report-type': 'daily-business-report',
                'generation-date': current_date.isoformat(),
                'record-count': str(len(report_data) - 1)  # Exclude header
            },
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Daily report uploaded to S3: {report_key}")
        return f"Daily report generated and stored: {report_key}"
        
    except Exception as e:
        logger.error(f"Failed to generate daily report: {str(e)}")
        raise


def process_business_data() -> str:
    """
    Process business data and store results in S3.
    
    Returns:
        String describing the data processing results
    """
    logger.info("Starting business data processing")
    
    try:
        current_time = datetime.datetime.now()
        
        # Simulate data processing with realistic business metrics
        processing_results = {
            'processed_at': current_time.isoformat(),
            'batch_id': f"batch-{current_time.strftime('%Y%m%d-%H%M%S')}",
            'records_processed': 1250,
            'success_rate': 98.4,
            'failed_records': 20,
            'processing_duration_seconds': 45.7,
            'data_sources': [
                'customer_transactions',
                'inventory_updates',
                'order_fulfillment'
            ],
            'quality_metrics': {
                'data_completeness': 99.1,
                'data_accuracy': 97.8,
                'duplicate_rate': 0.3
            },
            'alerts': [
                {
                    'type': 'warning',
                    'message': 'Higher than usual failed record count',
                    'threshold': 15,
                    'actual': 20
                }
            ]
        }
        
        # Save processed data to S3
        data_key = f"processed-data/batch-{current_time.strftime('%Y%m%d-%H%M%S')}.json"
        
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=data_key,
            Body=json.dumps(processing_results, indent=2),
            ContentType='application/json',
            Metadata={
                'generated-by': 'business-automation-lambda',
                'processing-type': 'hourly-data-batch',
                'processing-date': current_time.isoformat(),
                'batch-id': processing_results['batch_id']
            },
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Data processing results uploaded to S3: {data_key}")
        return f"Data processing completed: {processing_results['records_processed']} records processed with {processing_results['success_rate']}% success rate"
        
    except Exception as e:
        logger.error(f"Failed to process business data: {str(e)}")
        raise


def send_business_notification() -> str:
    """
    Send a business status notification.
    
    Returns:
        String confirming notification was sent
    """
    logger.info("Sending business status notification")
    
    try:
        current_time = datetime.datetime.now()
        
        # Generate comprehensive business status message
        status_message = f"""
Business Automation System - Weekly Status Report
Generated: {current_time.strftime('%Y-%m-%d %H:%M:%S UTC')}

System Health: ✅ OPERATIONAL

Recent Activity Summary:
• Daily reports: Generated successfully for the past 7 days
• Data processing: 99.2% success rate over past week
• Storage: {get_s3_usage_summary()}
• Notifications: All alerts delivered on time

Performance Metrics:
• Average processing time: 42.3 seconds
• Data accuracy: 98.1%
• System uptime: 99.9%

Upcoming Tasks:
• Monthly report compilation scheduled for end of month
• Quarterly data archive planned for next week
• Performance optimization review scheduled

For detailed metrics and logs, check the CloudWatch dashboard.
        """.strip()
        
        # Send the status notification
        send_notification(
            subject="📊 Weekly Business Automation Status Report",
            message=status_message,
            is_success=True
        )
        
        logger.info("Business status notification sent successfully")
        return "Weekly business status notification sent to stakeholders"
        
    except Exception as e:
        logger.error(f"Failed to send business notification: {str(e)}")
        raise


def send_notification(subject: str, message: str, is_success: bool = True) -> None:
    """
    Send notification via SNS.
    
    Args:
        subject: Email subject line
        message: Notification message body
        is_success: Whether this is a success or failure notification
    """
    try:
        # Add emoji and formatting based on success/failure
        if is_success:
            formatted_subject = f"✅ {subject}"
        else:
            formatted_subject = f"❌ {subject}"
        
        sns_client.publish(
            TopicArn=TOPIC_ARN,
            Message=message,
            Subject=formatted_subject,
            MessageAttributes={
                'notification_type': {
                    'DataType': 'String',
                    'StringValue': 'success' if is_success else 'failure'
                },
                'timestamp': {
                    'DataType': 'String',
                    'StringValue': datetime.datetime.now().isoformat()
                }
            }
        )
        
        logger.info(f"Notification sent: {formatted_subject}")
        
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")
        # Don't re-raise here to avoid infinite notification loops


def get_s3_usage_summary() -> str:
    """
    Get a summary of S3 bucket usage.
    
    Returns:
        String with S3 usage information
    """
    try:
        # List objects in the bucket
        response = s3_client.list_objects_v2(Bucket=BUCKET_NAME)
        
        if 'Contents' not in response:
            return "No files stored yet"
        
        total_size = sum(obj['Size'] for obj in response['Contents'])
        file_count = len(response['Contents'])
        
        # Convert bytes to human readable format
        if total_size < 1024:
            size_str = f"{total_size} B"
        elif total_size < 1024 * 1024:
            size_str = f"{total_size / 1024:.1f} KB"
        else:
            size_str = f"{total_size / (1024 * 1024):.1f} MB"
        
        return f"{file_count} files using {size_str}"
        
    except Exception as e:
        logger.warning(f"Could not get S3 usage summary: {str(e)}")
        return "Storage usage information unavailable"