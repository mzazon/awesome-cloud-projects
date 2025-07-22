"""
Reserved Instance Utilization Analysis Lambda Function

This function analyzes RI utilization using AWS Cost Explorer API and generates
alerts for underperforming reservations.

Author: AWS RI Management System
Version: 1.0
"""

import json
import boto3
import datetime
import os
import logging
from botocore.exceptions import ClientError
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for RI utilization analysis.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response with analysis results
    """
    # Initialize AWS clients
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get environment variables
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    utilization_threshold = float(os.environ.get('UTILIZATION_THRESHOLD', '${utilization_threshold}'))
    slack_webhook_url = os.environ.get('SLACK_WEBHOOK_URL', '')
    
    # Validate required environment variables
    if not bucket_name or not sns_topic_arn:
        logger.error("Missing required environment variables")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Missing required environment variables'})
        }
    
    # Calculate date range (last 30 days)
    end_date = datetime.date.today()
    start_date = end_date - datetime.timedelta(days=30)
    
    try:
        logger.info(f"Starting RI utilization analysis for period {start_date} to {end_date}")
        
        # Get RI utilization data from Cost Explorer
        response = ce.get_reservation_utilization(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        # Process utilization data
        utilization_data = []
        alerts = []
        total_utilization = 0
        service_count = 0
        
        for result in response['UtilizationsByTime']:
            for group in result['Groups']:
                service = group['Keys'][0]
                utilization_percent = float(group['Attributes']['UtilizationPercentage'])
                
                utilization_record = {
                    'service': service,
                    'utilization_percentage': utilization_percent,
                    'period': result['TimePeriod']['Start'],
                    'total_actual_hours': group['Attributes']['TotalActualHours'],
                    'unused_hours': group['Attributes']['UnusedHours'],
                    'total_reserved_hours': group['Attributes'].get('TotalReservedHours', '0'),
                    'purchased_hours': group['Attributes'].get('PurchasedHours', '0')
                }
                
                utilization_data.append(utilization_record)
                total_utilization += utilization_percent
                service_count += 1
                
                # Check for low utilization alerts
                if utilization_percent < utilization_threshold:
                    alert_severity = 'CRITICAL' if utilization_percent < 50 else 'WARNING'
                    alerts.append({
                        'service': service,
                        'utilization': utilization_percent,
                        'severity': alert_severity,
                        'type': 'LOW_UTILIZATION',
                        'message': f'Low RI utilization for {service}: {utilization_percent:.1f}%',
                        'unused_hours': group['Attributes']['UnusedHours'],
                        'potential_savings': calculate_potential_savings(
                            group['Attributes']['UnusedHours'], 
                            service
                        )
                    })
        
        # Calculate overall utilization
        overall_utilization = total_utilization / service_count if service_count > 0 else 0
        
        # Generate comprehensive report
        report_data = {
            'report_date': end_date.strftime('%Y-%m-%d'),
            'analysis_period': f"{start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}",
            'overall_utilization': round(overall_utilization, 2),
            'threshold': utilization_threshold,
            'services_analyzed': service_count,
            'alerts_generated': len(alerts),
            'utilization_data': utilization_data,
            'alerts': alerts,
            'recommendations': generate_utilization_recommendations(utilization_data, alerts)
        }
        
        # Save report to S3
        report_key = f"ri-utilization-reports/{start_date.strftime('%Y-%m-%d')}_analysis.json"
        
        try:
            s3.put_object(
                Bucket=bucket_name,
                Key=report_key,
                Body=json.dumps(report_data, indent=2, default=str),
                ContentType='application/json',
                ServerSideEncryption='AES256'
            )
            logger.info(f"Report saved to S3: s3://{bucket_name}/{report_key}")
        except ClientError as e:
            logger.error(f"Failed to save report to S3: {e}")
            
        # Send alerts if any issues found
        if alerts:
            try:
                send_utilization_alerts(sns, sns_topic_arn, alerts, overall_utilization, slack_webhook_url)
                logger.info(f"Sent {len(alerts)} utilization alerts")
            except Exception as e:
                logger.error(f"Failed to send alerts: {e}")
        
        logger.info(f"RI utilization analysis completed successfully. Overall utilization: {overall_utilization:.1f}%")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI utilization analysis completed successfully',
                'report_location': f"s3://{bucket_name}/{report_key}",
                'overall_utilization': overall_utilization,
                'services_analyzed': service_count,
                'alerts_generated': len(alerts),
                'analysis_period': f"{start_date} to {end_date}"
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS API error ({error_code}): {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"AWS API error: {error_message}",
                'error_code': error_code
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f"Unexpected error: {str(e)}"})
        }

def calculate_potential_savings(unused_hours: str, service: str) -> float:
    """
    Calculate potential cost savings from unused RI hours.
    
    Args:
        unused_hours: Number of unused reservation hours
        service: AWS service name
        
    Returns:
        Estimated potential savings in USD
    """
    try:
        hours = float(unused_hours)
        
        # Approximate hourly rates for different services (these are estimates)
        service_rates = {
            'Amazon Elastic Compute Cloud - Compute': 0.10,  # EC2
            'Amazon Relational Database Service': 0.15,       # RDS
            'Amazon ElastiCache': 0.08,                      # ElastiCache
            'Amazon Redshift': 0.25,                         # Redshift
            'Amazon OpenSearch Service': 0.12                # OpenSearch
        }
        
        # Default rate if service not found
        default_rate = 0.10
        hourly_rate = service_rates.get(service, default_rate)
        
        return round(hours * hourly_rate, 2)
        
    except (ValueError, TypeError):
        return 0.0

def generate_utilization_recommendations(utilization_data: List[Dict], alerts: List[Dict]) -> List[str]:
    """
    Generate actionable recommendations based on utilization analysis.
    
    Args:
        utilization_data: List of utilization data by service
        alerts: List of generated alerts
        
    Returns:
        List of recommendation strings
    """
    recommendations = []
    
    if not utilization_data:
        recommendations.append("No RI utilization data available. Ensure Reserved Instances are active.")
        return recommendations
    
    # Analyze overall patterns
    low_util_services = [alert['service'] for alert in alerts if alert['type'] == 'LOW_UTILIZATION']
    
    if low_util_services:
        recommendations.append(
            f"Consider rightsizing or canceling underutilized RIs for: {', '.join(set(low_util_services))}"
        )
    
    # Check for services with very high utilization
    high_util_services = [
        data['service'] for data in utilization_data 
        if data['utilization_percentage'] > 95
    ]
    
    if high_util_services:
        recommendations.append(
            f"Consider purchasing additional RIs for high-utilization services: {', '.join(set(high_util_services))}"
        )
    
    # General recommendations
    recommendations.extend([
        "Review RI coverage regularly to ensure optimal cost savings",
        "Consider convertible RIs for workloads with changing requirements",
        "Use RI modification to adjust instance families or sizes as needed",
        "Monitor application patterns to identify opportunities for RI optimization"
    ])
    
    return recommendations

def send_utilization_alerts(sns_client, topic_arn: str, alerts: List[Dict], overall_utilization: float, slack_webhook_url: str = "") -> None:
    """
    Send utilization alerts via SNS and optionally Slack.
    
    Args:
        sns_client: Boto3 SNS client
        topic_arn: SNS topic ARN
        alerts: List of alerts to send
        overall_utilization: Overall utilization percentage
        slack_webhook_url: Optional Slack webhook URL
    """
    if not alerts:
        return
    
    # Prepare SNS message
    message = f"Reserved Instance Utilization Alert Report\\n\\n"
    message += f"Overall RI Utilization: {overall_utilization:.1f}%\\n"
    message += f"Number of Issues Found: {len(alerts)}\\n\\n"
    
    critical_alerts = [a for a in alerts if a.get('severity') == 'CRITICAL']
    warning_alerts = [a for a in alerts if a.get('severity') == 'WARNING']
    
    if critical_alerts:
        message += "CRITICAL ISSUES:\\n"
        for alert in critical_alerts:
            message += f"- {alert['message']} (Potential savings: ${alert['potential_savings']})\\n"
        message += "\\n"
    
    if warning_alerts:
        message += "WARNINGS:\\n"
        for alert in warning_alerts:
            message += f"- {alert['message']} (Potential savings: ${alert['potential_savings']})\\n"
        message += "\\n"
    
    message += "Please review your Reserved Instance utilization and consider optimization actions.\\n"
    message += f"Report generated at: {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC"
    
    # Send SNS notification
    sns_client.publish(
        TopicArn=topic_arn,
        Subject="Reserved Instance Utilization Alert",
        Message=message
    )
    
    # Send Slack notification if webhook URL provided
    if slack_webhook_url:
        try:
            import urllib3
            http = urllib3.PoolManager()
            
            slack_message = {
                "text": f"🚨 Reserved Instance Utilization Alert",
                "attachments": [
                    {
                        "color": "warning" if critical_alerts else "good",
                        "fields": [
                            {
                                "title": "Overall Utilization",
                                "value": f"{overall_utilization:.1f}%",
                                "short": True
                            },
                            {
                                "title": "Issues Found",
                                "value": str(len(alerts)),
                                "short": True
                            }
                        ],
                        "text": message.replace("\\n", "\\n")
                    }
                ]
            }
            
            http.request(
                'POST',
                slack_webhook_url,
                body=json.dumps(slack_message),
                headers={'Content-Type': 'application/json'}
            )
            
        except Exception as e:
            logger.warning(f"Failed to send Slack notification: {e}")