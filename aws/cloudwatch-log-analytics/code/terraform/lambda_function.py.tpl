import json
import boto3
import time
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    Lambda function for automated log analysis using CloudWatch Logs Insights.
    
    This function:
    1. Queries CloudWatch Logs Insights for errors in the specified time window
    2. Analyzes the results and checks against the error threshold
    3. Sends SNS notifications when errors exceed the threshold
    4. Provides detailed logging for monitoring and debugging
    """
    
    # Initialize AWS clients
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    # Get configuration from environment variables
    log_group_name = os.environ['LOG_GROUP_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    error_threshold = int(os.environ['ERROR_THRESHOLD'])
    analysis_window_hours = int(os.environ['ANALYSIS_WINDOW_HOURS'])
    
    # Calculate time window for analysis
    end_time = int(time.time())
    start_time = end_time - (analysis_window_hours * 3600)  # Convert hours to seconds
    
    print(f"Starting log analysis for log group: {log_group_name}")
    print(f"Analysis window: {analysis_window_hours} hours")
    print(f"Error threshold: {error_threshold}")
    print(f"Time range: {datetime.fromtimestamp(start_time)} to {datetime.fromtimestamp(end_time)}")
    
    # Define CloudWatch Logs Insights query for error analysis
    error_query = '''
    fields @timestamp, @message
    | filter @message like /ERROR/
    | stats count() as error_count
    '''
    
    # Define additional queries for comprehensive analysis
    warning_query = '''
    fields @timestamp, @message
    | filter @message like /WARN/
    | stats count() as warning_count
    '''
    
    performance_query = '''
    fields @timestamp, @message
    | filter @message like /API Request/
    | parse @message "* - *ms" as status, response_time
    | stats avg(response_time) as avg_response_time, max(response_time) as max_response_time, count() as request_count
    '''
    
    try:
        # Execute error analysis query
        print("Executing error analysis query...")
        error_response = logs_client.start_query(
            logGroupName=log_group_name,
            startTime=start_time,
            endTime=end_time,
            queryString=error_query
        )
        
        error_query_id = error_response['queryId']
        print(f"Error query started with ID: {error_query_id}")
        
        # Execute warning analysis query
        print("Executing warning analysis query...")
        warning_response = logs_client.start_query(
            logGroupName=log_group_name,
            startTime=start_time,
            endTime=end_time,
            queryString=warning_query
        )
        
        warning_query_id = warning_response['queryId']
        print(f"Warning query started with ID: {warning_query_id}")
        
        # Execute performance analysis query
        print("Executing performance analysis query...")
        performance_response = logs_client.start_query(
            logGroupName=log_group_name,
            startTime=start_time,
            endTime=end_time,
            queryString=performance_query
        )
        
        performance_query_id = performance_response['queryId']
        print(f"Performance query started with ID: {performance_query_id}")
        
        # Wait for error query completion
        error_result = wait_for_query_completion(logs_client, error_query_id, "error")
        warning_result = wait_for_query_completion(logs_client, warning_query_id, "warning")
        performance_result = wait_for_query_completion(logs_client, performance_query_id, "performance")
        
        # Process results
        analysis_results = process_query_results(error_result, warning_result, performance_result)
        
        # Check error threshold and send alert if needed
        error_count = analysis_results.get('error_count', 0)
        
        if error_count >= error_threshold:
            alert_message = create_alert_message(analysis_results, analysis_window_hours)
            
            print(f"Error threshold exceeded! Sending alert...")
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=alert_message,
                Subject=f'Log Analytics Alert - {error_count} Errors Detected'
            )
            
            print(f"Alert sent successfully for {error_count} errors")
        else:
            print(f"Error count ({error_count}) is below threshold ({error_threshold}). No alert sent.")
        
        # Log analysis summary
        print("=== Analysis Summary ===")
        print(f"Errors: {analysis_results.get('error_count', 0)}")
        print(f"Warnings: {analysis_results.get('warning_count', 0)}")
        print(f"API Requests: {analysis_results.get('request_count', 0)}")
        print(f"Average Response Time: {analysis_results.get('avg_response_time', 'N/A')}ms")
        print(f"Max Response Time: {analysis_results.get('max_response_time', 'N/A')}ms")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log analysis completed successfully',
                'analysis_results': analysis_results,
                'alert_sent': error_count >= error_threshold
            })
        }
        
    except Exception as e:
        error_message = f"Error during log analysis: {str(e)}"
        print(error_message)
        
        # Send error notification
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=f"Log Analytics Function Error: {error_message}",
                Subject='Log Analytics Function Error'
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error during log analysis',
                'error': str(e)
            })
        }

def wait_for_query_completion(logs_client, query_id, query_type, max_wait_time=50):
    """
    Wait for CloudWatch Logs Insights query to complete.
    
    Args:
        logs_client: Boto3 CloudWatch Logs client
        query_id: ID of the query to monitor
        query_type: Type of query for logging purposes
        max_wait_time: Maximum time to wait in seconds
    
    Returns:
        Query results or None if timeout
    """
    wait_time = 0
    while wait_time < max_wait_time:
        try:
            result = logs_client.get_query_results(queryId=query_id)
            status = result['status']
            
            if status == 'Complete':
                print(f"{query_type.title()} query completed successfully")
                return result
            elif status == 'Failed':
                print(f"{query_type.title()} query failed")
                return None
            elif status == 'Cancelled':
                print(f"{query_type.title()} query was cancelled")
                return None
            else:
                print(f"{query_type.title()} query status: {status}")
                time.sleep(2)
                wait_time += 2
                
        except Exception as e:
            print(f"Error checking {query_type} query status: {str(e)}")
            return None
    
    print(f"{query_type.title()} query timed out after {max_wait_time} seconds")
    return None

def process_query_results(error_result, warning_result, performance_result):
    """
    Process the results from multiple CloudWatch Logs Insights queries.
    
    Args:
        error_result: Results from error analysis query
        warning_result: Results from warning analysis query
        performance_result: Results from performance analysis query
    
    Returns:
        Dictionary containing processed analysis results
    """
    analysis = {
        'error_count': 0,
        'warning_count': 0,
        'request_count': 0,
        'avg_response_time': None,
        'max_response_time': None
    }
    
    # Process error results
    if error_result and error_result.get('results'):
        try:
            analysis['error_count'] = int(error_result['results'][0][0]['value'])
        except (IndexError, KeyError, ValueError) as e:
            print(f"Error processing error results: {str(e)}")
    
    # Process warning results
    if warning_result and warning_result.get('results'):
        try:
            analysis['warning_count'] = int(warning_result['results'][0][0]['value'])
        except (IndexError, KeyError, ValueError) as e:
            print(f"Error processing warning results: {str(e)}")
    
    # Process performance results
    if performance_result and performance_result.get('results'):
        try:
            result_row = performance_result['results'][0]
            analysis['avg_response_time'] = float(result_row[0]['value']) if result_row[0]['value'] else None
            analysis['max_response_time'] = float(result_row[1]['value']) if result_row[1]['value'] else None
            analysis['request_count'] = int(result_row[2]['value']) if result_row[2]['value'] else 0
        except (IndexError, KeyError, ValueError) as e:
            print(f"Error processing performance results: {str(e)}")
    
    return analysis

def create_alert_message(analysis_results, analysis_window_hours):
    """
    Create a detailed alert message based on analysis results.
    
    Args:
        analysis_results: Dictionary containing analysis results
        analysis_window_hours: Time window used for analysis
    
    Returns:
        Formatted alert message string
    """
    message = f"""
LOG ANALYTICS ALERT
===================

Time Window: Last {analysis_window_hours} hour(s)
Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}

ISSUE SUMMARY:
- Errors Detected: {analysis_results.get('error_count', 0)}
- Warnings: {analysis_results.get('warning_count', 0)}
- Total API Requests: {analysis_results.get('request_count', 0)}

PERFORMANCE METRICS:
- Average Response Time: {analysis_results.get('avg_response_time', 'N/A')}ms
- Maximum Response Time: {analysis_results.get('max_response_time', 'N/A')}ms

RECOMMENDED ACTIONS:
1. Review error logs in CloudWatch Logs Insights
2. Check application health and dependencies
3. Monitor system resources and performance
4. Investigate any recent deployments or changes

This alert was generated automatically by the Log Analytics System.
"""
    
    return message.strip()