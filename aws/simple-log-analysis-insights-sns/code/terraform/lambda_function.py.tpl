import json
import boto3
import time
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    Lambda function to analyze CloudWatch logs for error patterns
    and send SNS notifications when errors are detected.
    
    This function uses CloudWatch Logs Insights to query application logs
    for specific error patterns and automatically sends notifications via SNS
    when critical issues are detected.
    """
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    # Get configuration from environment variables with defaults
    log_group = os.environ.get('LOG_GROUP_NAME', '${log_group_name}')
    sns_topic = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
    error_pattern = os.environ.get('ERROR_PATTERN', '${error_pattern}')
    query_time_range = int(os.environ.get('QUERY_TIME_RANGE', '${query_time_range}'))
    max_errors = int(os.environ.get('MAX_ERRORS_TO_DISPLAY', '${max_errors_to_display}'))
    
    # Define time range for log analysis (look back from current time)
    end_time = datetime.now()
    start_time = end_time - timedelta(minutes=query_time_range)
    
    # CloudWatch Logs Insights query for error patterns
    # This query searches for messages containing the specified error patterns
    query = f"""
    fields @timestamp, @message
    | filter @message like /{error_pattern}/
    | sort @timestamp desc
    | limit 100
    """
    
    try:
        print(f"Starting log analysis for log group: {log_group}")
        print(f"Time range: {start_time} to {end_time}")
        print(f"Error pattern: {error_pattern}")
        
        # Start the CloudWatch Logs Insights query
        response = logs_client.start_query(
            logGroupName=log_group,
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = response['queryId']
        print(f"Started query with ID: {query_id}")
        
        # Wait for query completion with timeout protection
        max_wait_time = 60  # Maximum wait time in seconds
        wait_start = time.time()
        
        while True:
            # Check for timeout to prevent indefinite waiting
            if time.time() - wait_start > max_wait_time:
                raise Exception(f'Query timeout after {max_wait_time} seconds')
                
            time.sleep(2)
            result = logs_client.get_query_results(queryId=query_id)
            
            if result['status'] == 'Complete':
                break
            elif result['status'] == 'Failed':
                raise Exception(f"Query failed: {result.get('statusMessage', 'Unknown error')}")
            elif result['status'] in ['Cancelled', 'Timeout']:
                raise Exception(f"Query {result['status'].lower()}")
        
        # Process query results
        error_count = len(result['results'])
        print(f"Query completed. Found {error_count} error(s)")
        
        if error_count > 0:
            # Format alert message with error details
            alert_message = f"""🚨 CloudWatch Log Analysis Alert

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Log Group: {log_group}
Error Pattern: {error_pattern}
Error Count: {error_count} error(s) found in the last {query_time_range} minutes

Recent Errors:"""
            
            # Add up to max_errors recent errors to the message
            for i, log_entry in enumerate(result['results'][:max_errors]):
                try:
                    # Extract timestamp and message from query results
                    timestamp = next(field['value'] for field in log_entry if field['field'] == '@timestamp')
                    message = next(field['value'] for field in log_entry if field['field'] == '@message')
                    alert_message += f"\n{i+1}. {timestamp}: {message}"
                except (StopIteration, KeyError) as e:
                    print(f"Error parsing log entry {i}: {e}")
                    continue
            
            # Add note if there are more errors than displayed
            if error_count > max_errors:
                alert_message += f"\n... and {error_count - max_errors} more error(s)"
            
            # Add CloudWatch Logs Insights console link for further investigation
            console_url = f"https://console.aws.amazon.com/cloudwatch/home?region={os.environ.get('AWS_REGION', 'us-east-1')}#logsV2:logs-insights"
            alert_message += f"\n\n🔍 Investigate further: {console_url}"
            
            # Send SNS notification
            sns_response = sns_client.publish(
                TopicArn=sns_topic,
                Subject=f'CloudWatch Log Analysis Alert - {error_count} Error(s) Detected',
                Message=alert_message
            )
            
            print(f"Alert sent successfully. SNS Message ID: {sns_response.get('MessageId')}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Alert sent successfully',
                    'error_count': error_count,
                    'query_id': query_id,
                    'sns_message_id': sns_response.get('MessageId'),
                    'log_group': log_group,
                    'time_range_minutes': query_time_range,
                    'status': 'success'
                })
            }
        else:
            print("No errors detected in recent logs")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No errors detected',
                    'error_count': 0,
                    'query_id': query_id,
                    'log_group': log_group,
                    'time_range_minutes': query_time_range,
                    'status': 'success'
                })
            }
            
    except Exception as e:
        error_message = f"Error analyzing logs: {str(e)}"
        print(error_message)
        
        # Send error notification to SNS for operational awareness
        try:
            sns_client.publish(
                TopicArn=sns_topic,
                Subject='CloudWatch Log Analysis Function Error',
                Message=f"""❌ Log Analysis Function Error

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Log Group: {log_group}
Error: {error_message}

The log analysis function encountered an error and may need attention.
Please check the Lambda function logs for more details.

Function: {context.function_name if context else 'Unknown'}
Request ID: {context.aws_request_id if context else 'Unknown'}"""
            )
            print("Error notification sent to SNS")
        except Exception as sns_error:
            print(f"Failed to send error notification: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'log_group': log_group,
                'status': 'error'
            })
        }