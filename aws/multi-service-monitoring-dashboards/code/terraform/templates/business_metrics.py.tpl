import json
import boto3
import random
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Lambda function to collect and publish business metrics to CloudWatch.
    This function simulates business KPIs and publishes them as custom metrics.
    """
    try:
        # Simulate business metrics (replace with real business logic)
        
        # Revenue metrics
        hourly_revenue = random.uniform(10000, 50000)
        transaction_count = random.randint(100, 1000)
        average_order_value = hourly_revenue / transaction_count
        
        # User engagement metrics
        active_users = random.randint(500, 5000)
        page_views = random.randint(10000, 50000)
        bounce_rate = random.uniform(0.2, 0.8)
        
        # Performance metrics
        api_response_time = random.uniform(100, 2000)
        error_rate = random.uniform(0.001, 0.05)
        throughput = random.randint(100, 1000)
        
        # Customer satisfaction
        nps_score = random.uniform(6.0, 9.5)
        support_ticket_volume = random.randint(5, 50)
        
        # Send custom metrics to CloudWatch
        metrics = [
            {
                'MetricName': 'HourlyRevenue',
                'Value': hourly_revenue,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'},
                    {'Name': 'BusinessUnit', 'Value': '${business_unit}'}
                ]
            },
            {
                'MetricName': 'TransactionCount',
                'Value': transaction_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'},
                    {'Name': 'BusinessUnit', 'Value': '${business_unit}'}
                ]
            },
            {
                'MetricName': 'AverageOrderValue',
                'Value': average_order_value,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'},
                    {'Name': 'BusinessUnit', 'Value': '${business_unit}'}
                ]
            },
            {
                'MetricName': 'ActiveUsers',
                'Value': active_users,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'}
                ]
            },
            {
                'MetricName': 'APIResponseTime',
                'Value': api_response_time,
                'Unit': 'Milliseconds',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'},
                    {'Name': 'Service', 'Value': 'api-gateway'}
                ]
            },
            {
                'MetricName': 'ErrorRate',
                'Value': error_rate,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'},
                    {'Name': 'Service', 'Value': 'api-gateway'}
                ]
            },
            {
                'MetricName': 'NPSScore',
                'Value': nps_score,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'}
                ]
            },
            {
                'MetricName': 'SupportTicketVolume',
                'Value': support_ticket_volume,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${environment}'}
                ]
            }
        ]
        
        # Submit metrics in batches
        for i in range(0, len(metrics), 20):
            batch = metrics[i:i+20]
            cloudwatch.put_metric_data(
                Namespace='Business/Metrics',
                MetricData=batch
            )
        
        # Calculate and submit composite health score
        health_score = calculate_health_score(
            api_response_time, error_rate, nps_score, 
            support_ticket_volume, active_users
        )
        
        cloudwatch.put_metric_data(
            Namespace='Business/Health',
            MetricData=[
                {
                    'MetricName': 'CompositeHealthScore',
                    'Value': health_score,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': '${environment}'}
                    ]
                }
            ]
        )
        
        print(f"Successfully published {len(metrics)} business metrics")
        print(f"Composite health score: {health_score:.2f}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Business metrics published successfully',
                'health_score': health_score,
                'metrics_count': len(metrics)
            })
        }
        
    except Exception as e:
        print(f"Error publishing business metrics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def calculate_health_score(response_time, error_rate, nps, tickets, users):
    """
    Calculate a composite health score based on multiple business metrics.
    
    Args:
        response_time: API response time in milliseconds
        error_rate: Error rate as a percentage
        nps: Net Promoter Score
        tickets: Number of support tickets
        users: Number of active users
        
    Returns:
        float: Composite health score (0-100)
    """
    # Normalize metrics to 0-100 scale and weight them
    response_score = max(0, 100 - (response_time / 20))  # Lower is better
    error_score = max(0, 100 - (error_rate * 2000))      # Lower is better
    nps_score = (nps / 10) * 100                         # Higher is better
    ticket_score = max(0, 100 - (tickets * 2))          # Lower is better
    user_score = min(100, (users / 50))                 # Higher is better
    
    # Weighted average
    weights = [0.25, 0.30, 0.20, 0.15, 0.10]
    scores = [response_score, error_score, nps_score, ticket_score, user_score]
    
    composite_score = sum(w * s for w, s in zip(weights, scores))
    
    return round(composite_score, 2)