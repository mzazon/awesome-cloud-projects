import json
import boto3
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
xray_client = boto3.client('xray')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Automated trace analysis Lambda function.
    
    This function:
    - Retrieves traces from the last hour
    - Analyzes trace patterns and performance metrics
    - Publishes custom metrics to CloudWatch
    - Provides actionable insights for monitoring
    """
    try:
        logger.info("Starting automated trace analysis")
        
        # Define time range for analysis (last hour)
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        logger.info(f"Analyzing traces from {start_time} to {end_time}")
        
        # Get trace summaries for order processor service
        trace_summaries = get_trace_summaries(start_time, end_time)
        
        # Analyze trace data
        analysis_results = analyze_traces(trace_summaries)
        
        # Publish metrics to CloudWatch
        publish_metrics(analysis_results)
        
        # Generate summary report
        summary_report = generate_summary_report(analysis_results)
        
        logger.info(f"Trace analysis completed successfully: {summary_report}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'success',
                'analysis_period': {
                    'start_time': start_time.isoformat(),
                    'end_time': end_time.isoformat()
                },
                'results': analysis_results,
                'summary': summary_report
            })
        }
        
    except Exception as e:
        logger.error(f"Error in trace analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'error': str(e)
            })
        }

def get_trace_summaries(start_time, end_time):
    """
    Retrieve trace summaries from X-Ray for the specified time range.
    
    Args:
        start_time (datetime): Start of analysis period
        end_time (datetime): End of analysis period
        
    Returns:
        list: List of trace summaries
    """
    try:
        # Get traces for order processor service
        response = xray_client.get_trace_summaries(
            TimeRangeType='TimeStamp',
            StartTime=start_time,
            EndTime=end_time,
            FilterExpression='service("order-processor")',
            SamplingStrategy={
                'Name': 'PartialScan',
                'Value': 0.1  # Sample 10% of traces for analysis
            }
        )
        
        trace_summaries = response.get('TraceSummaries', [])
        logger.info(f"Retrieved {len(trace_summaries)} trace summaries")
        
        # Handle pagination if needed
        while 'NextToken' in response:
            response = xray_client.get_trace_summaries(
                TimeRangeType='TimeStamp',
                StartTime=start_time,
                EndTime=end_time,
                FilterExpression='service("order-processor")',
                NextToken=response['NextToken'],
                SamplingStrategy={
                    'Name': 'PartialScan',
                    'Value': 0.1
                }
            )
            trace_summaries.extend(response.get('TraceSummaries', []))
        
        return trace_summaries
        
    except Exception as e:
        logger.error(f"Error retrieving trace summaries: {str(e)}")
        return []

def analyze_traces(trace_summaries):
    """
    Analyze trace summaries to extract performance and error metrics.
    
    Args:
        trace_summaries (list): List of trace summaries from X-Ray
        
    Returns:
        dict: Analysis results with various metrics
    """
    total_traces = len(trace_summaries)
    
    if total_traces == 0:
        logger.warning("No traces found for analysis")
        return {
            'total_traces': 0,
            'error_traces': 0,
            'fault_traces': 0,
            'throttle_traces': 0,
            'high_latency_traces': 0,
            'average_response_time': 0,
            'p95_response_time': 0,
            'error_rate': 0,
            'fault_rate': 0
        }
    
    # Initialize counters
    error_traces = 0
    fault_traces = 0
    throttle_traces = 0
    high_latency_traces = 0
    response_times = []
    
    # Analyze each trace
    for trace in trace_summaries:
        # Count errors and faults
        if trace.get('HasError', False):
            error_traces += 1
        if trace.get('HasFault', False):
            fault_traces += 1
        if trace.get('HasThrottle', False):
            throttle_traces += 1
        
        # Analyze response times
        response_time = trace.get('ResponseTime', 0)
        response_times.append(response_time)
        
        # Count high latency traces (> 2 seconds)
        if response_time > 2.0:
            high_latency_traces += 1
    
    # Calculate response time statistics
    if response_times:
        average_response_time = sum(response_times) / len(response_times)
        sorted_times = sorted(response_times)
        p95_index = int(0.95 * len(sorted_times))
        p95_response_time = sorted_times[p95_index] if p95_index < len(sorted_times) else sorted_times[-1]
    else:
        average_response_time = 0
        p95_response_time = 0
    
    # Calculate rates
    error_rate = (error_traces / total_traces) * 100 if total_traces > 0 else 0
    fault_rate = (fault_traces / total_traces) * 100 if total_traces > 0 else 0
    
    analysis_results = {
        'total_traces': total_traces,
        'error_traces': error_traces,
        'fault_traces': fault_traces,
        'throttle_traces': throttle_traces,
        'high_latency_traces': high_latency_traces,
        'average_response_time': round(average_response_time, 3),
        'p95_response_time': round(p95_response_time, 3),
        'error_rate': round(error_rate, 2),
        'fault_rate': round(fault_rate, 2)
    }
    
    logger.info(f"Trace analysis results: {analysis_results}")
    return analysis_results

def publish_metrics(analysis_results):
    """
    Publish custom metrics to CloudWatch based on trace analysis.
    
    Args:
        analysis_results (dict): Results from trace analysis
    """
    try:
        metric_data = []
        
        # Create metric data points
        metrics_to_publish = [
            ('TotalTraces', analysis_results['total_traces'], 'Count'),
            ('ErrorTraces', analysis_results['error_traces'], 'Count'),
            ('FaultTraces', analysis_results['fault_traces'], 'Count'),
            ('ThrottleTraces', analysis_results['throttle_traces'], 'Count'),
            ('HighLatencyTraces', analysis_results['high_latency_traces'], 'Count'),
            ('AverageResponseTime', analysis_results['average_response_time'], 'Seconds'),
            ('P95ResponseTime', analysis_results['p95_response_time'], 'Seconds'),
            ('ErrorRate', analysis_results['error_rate'], 'Percent'),
            ('FaultRate', analysis_results['fault_rate'], 'Percent')
        ]
        
        for metric_name, value, unit in metrics_to_publish:
            metric_data.append({
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit,
                'Timestamp': datetime.utcnow()
            })
        
        # Publish metrics in batches (CloudWatch limit is 20 metrics per call)
        batch_size = 20
        for i in range(0, len(metric_data), batch_size):
            batch = metric_data[i:i + batch_size]
            
            cloudwatch.put_metric_data(
                Namespace='XRay/Analysis',
                MetricData=batch
            )
        
        logger.info(f"Published {len(metric_data)} metrics to CloudWatch")
        
    except Exception as e:
        logger.error(f"Error publishing metrics: {str(e)}")

def generate_summary_report(analysis_results):
    """
    Generate a human-readable summary report of the trace analysis.
    
    Args:
        analysis_results (dict): Results from trace analysis
        
    Returns:
        dict: Summary report with insights and recommendations
    """
    total_traces = analysis_results['total_traces']
    error_rate = analysis_results['error_rate']
    avg_response_time = analysis_results['average_response_time']
    p95_response_time = analysis_results['p95_response_time']
    
    # Generate health status
    if error_rate > 5:
        health_status = 'CRITICAL'
    elif error_rate > 2 or avg_response_time > 1:
        health_status = 'WARNING'
    else:
        health_status = 'HEALTHY'
    
    # Generate recommendations
    recommendations = []
    
    if error_rate > 5:
        recommendations.append("High error rate detected. Review application logs and error handling.")
    
    if avg_response_time > 1:
        recommendations.append("Average response time is high. Consider performance optimization.")
    
    if p95_response_time > 3:
        recommendations.append("95th percentile response time is concerning. Investigate slow requests.")
    
    if analysis_results['high_latency_traces'] > 0:
        recommendations.append(f"{analysis_results['high_latency_traces']} high latency traces detected. Review trace details.")
    
    if total_traces == 0:
        recommendations.append("No traces found. Verify X-Ray configuration and application traffic.")
    
    if not recommendations:
        recommendations.append("Application performance appears healthy.")
    
    summary = {
        'health_status': health_status,
        'total_requests': total_traces,
        'performance_summary': f"Avg: {avg_response_time}s, P95: {p95_response_time}s",
        'error_summary': f"Error rate: {error_rate}%",
        'recommendations': recommendations
    }
    
    return summary