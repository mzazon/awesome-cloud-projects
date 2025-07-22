# Output values for the serverless real-time analytics pipeline
# These outputs provide important information for verification and integration

# =====================================
# Core Infrastructure Outputs
# =====================================

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.analytics_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.analytics_stream.arn
}

output "kinesis_stream_shard_count" {
  description = "Number of shards in the Kinesis Data Stream"
  value       = aws_kinesis_stream.analytics_stream.shard_count
}

output "lambda_function_name" {
  description = "Name of the Lambda function processing Kinesis events"
  value       = aws_lambda_function.kinesis_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.kinesis_processor.arn
}

output "lambda_function_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing analytics results"
  value       = aws_dynamodb_table.analytics_results.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.analytics_results.arn
}

# =====================================
# Monitoring and Observability Outputs
# =====================================

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch Log Group ARN for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications (if created)"
  value       = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? aws_sns_topic.alarm_notifications[0].arn : null
}

output "lambda_dlq_url" {
  description = "URL of the Dead Letter Queue for failed Lambda invocations"
  value       = aws_sqs_queue.lambda_dlq.url
}

output "lambda_dlq_arn" {
  description = "ARN of the Dead Letter Queue for failed Lambda invocations"
  value       = aws_sqs_queue.lambda_dlq.arn
}

# =====================================
# Event Source Mapping Output
# =====================================

output "event_source_mapping_uuid" {
  description = "UUID of the event source mapping between Kinesis and Lambda"
  value       = aws_lambda_event_source_mapping.kinesis_lambda_mapping.uuid
}

output "event_source_mapping_state" {
  description = "State of the event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_lambda_mapping.state
}

# =====================================
# Configuration Information
# =====================================

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# =====================================
# Testing and Validation Commands
# =====================================

output "kinesis_put_record_command" {
  description = "AWS CLI command to send a test record to Kinesis"
  value = "aws kinesis put-record --stream-name ${aws_kinesis_stream.analytics_stream.name} --data '{\"eventType\":\"page_view\",\"userId\":\"test-user\",\"pageUrl\":\"/test\"}' --partition-key test-user"
}

output "dynamodb_scan_command" {
  description = "AWS CLI command to scan DynamoDB table for processed records"
  value = "aws dynamodb scan --table-name ${aws_dynamodb_table.analytics_results.name} --max-items 5"
}

output "lambda_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --start-time $(date -d '10 minutes ago' +%s)000"
}

output "cloudwatch_metrics_command" {
  description = "AWS CLI command to view custom CloudWatch metrics"
  value = "aws cloudwatch get-metric-statistics --namespace RealTimeAnalytics --metric-name EventsProcessed --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum"
}

# =====================================
# Data Producer Script
# =====================================

output "python_data_producer_script" {
  description = "Python script to generate test data for the pipeline"
  value = <<-EOT
#!/usr/bin/env python3
"""
Data producer script for testing the serverless analytics pipeline
Usage: python3 data_producer.py
"""

import boto3
import json
import time
import random
from datetime import datetime

# Initialize Kinesis client
kinesis = boto3.client('kinesis')

def generate_sample_events():
    """Generate sample events for testing"""
    event_types = ['page_view', 'purchase', 'user_signup', 'click']
    device_types = ['desktop', 'mobile', 'tablet']
    
    events = []
    
    for i in range(10):
        event = {
            'eventType': random.choice(event_types),
            'userId': f'user_{random.randint(1000, 9999)}',
            'sessionId': f'session_{random.randint(100000, 999999)}',
            'deviceType': random.choice(device_types),
            'timestamp': datetime.now().isoformat(),
            'location': {
                'country': random.choice(['US', 'UK', 'DE', 'FR', 'JP']),
                'city': random.choice(['New York', 'London', 'Berlin', 'Paris', 'Tokyo'])
            }
        }
        
        # Add event-specific data
        if event['eventType'] == 'page_view':
            event.update({
                'pageUrl': f'/page/{random.randint(1, 100)}',
                'loadTime': random.randint(500, 3000),
                'sessionLength': random.randint(10, 1800),
                'pagesViewed': random.randint(1, 10)
            })
        elif event['eventType'] == 'purchase':
            event.update({
                'amount': round(random.uniform(10.99, 299.99), 2),
                'currency': 'USD',
                'itemsCount': random.randint(1, 5)
            })
        elif event['eventType'] == 'user_signup':
            event.update({
                'signupMethod': random.choice(['email', 'social', 'phone']),
                'campaignSource': random.choice(['google', 'facebook', 'direct', 'email'])
            })
        
        events.append(event)
    
    return events

def send_events_to_kinesis(stream_name, events):
    """Send events to Kinesis Data Stream"""
    for event in events:
        try:
            response = kinesis.put_record(
                StreamName=stream_name,
                Data=json.dumps(event),
                PartitionKey=event['userId']
            )
            print(f"Sent event {event['eventType']} - Shard: {response['ShardId']}")
            time.sleep(0.1)  # Small delay between events
            
        except Exception as e:
            print(f"Error sending event: {str(e)}")

if __name__ == "__main__":
    stream_name = "${aws_kinesis_stream.analytics_stream.name}"
    
    print("Generating and sending sample events...")
    
    # Send multiple batches of events
    for batch in range(3):
        print(f"\\nSending batch {batch + 1}...")
        events = generate_sample_events()
        send_events_to_kinesis(stream_name, events)
        time.sleep(2)  # Wait between batches
    
    print("\\nCompleted sending test events!")
EOT
}

# =====================================
# Summary Information
# =====================================

output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = <<-EOT
Serverless Real-Time Analytics Pipeline Deployed Successfully!

🎯 Core Resources Created:
- Kinesis Data Stream: ${aws_kinesis_stream.analytics_stream.name}
- Lambda Function: ${aws_lambda_function.kinesis_processor.function_name}
- DynamoDB Table: ${aws_dynamodb_table.analytics_results.name}
- CloudWatch Log Group: ${aws_cloudwatch_log_group.lambda_logs.name}

📊 Monitoring:
- CloudWatch Alarms: ${var.enable_cloudwatch_alarms ? "Enabled" : "Disabled"}
- SNS Notifications: ${var.alarm_email_endpoint != "" ? "Configured" : "Not configured"}
- Dead Letter Queue: ${aws_sqs_queue.lambda_dlq.name}

🚀 Next Steps:
1. Use the data producer script output to test the pipeline
2. Monitor Lambda logs: ${aws_cloudwatch_log_group.lambda_logs.name}
3. View processed data in DynamoDB: ${aws_dynamodb_table.analytics_results.name}
4. Check custom metrics in CloudWatch namespace: RealTimeAnalytics

💡 Testing Commands:
- Send test record: Use 'kinesis_put_record_command' output
- View processed data: Use 'dynamodb_scan_command' output  
- Check logs: Use 'lambda_logs_command' output
- View metrics: Use 'cloudwatch_metrics_command' output

Region: ${data.aws_region.current.name}
Account: ${data.aws_caller_identity.current.account_id}
EOT
}