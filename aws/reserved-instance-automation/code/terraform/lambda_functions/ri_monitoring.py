"""
Reserved Instance Monitoring Lambda Function

This function monitors RI expirations, tracks RI inventory, and sends alerts
for upcoming expirations and status changes.

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
    Main Lambda handler for RI monitoring and expiration tracking.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response with monitoring results
    """
    # Initialize AWS clients
    ec2 = boto3.client('ec2')
    rds = boto3.client('rds')
    dynamodb = boto3.resource('dynamodb')
    sns = boto3.client('sns')
    
    # Get environment variables
    table_name = os.environ.get('DYNAMODB_TABLE_NAME')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    expiration_warning_days = int(os.environ.get('EXPIRATION_WARNING_DAYS', '${expiration_warning_days}'))
    critical_expiration_days = int(os.environ.get('CRITICAL_EXPIRATION_DAYS', '${critical_expiration_days}'))
    slack_webhook_url = os.environ.get('SLACK_WEBHOOK_URL', '')
    
    # Validate required environment variables
    if not table_name or not sns_topic_arn:
        logger.error("Missing required environment variables")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Missing required environment variables'})
        }
    
    table = dynamodb.Table(table_name)
    current_time = datetime.datetime.utcnow()
    
    try:
        logger.info("Starting RI monitoring and expiration tracking")
        
        # Monitor EC2 Reserved Instances
        ec2_alerts = monitor_ec2_reservations(ec2, table, current_time, expiration_warning_days, critical_expiration_days)
        
        # Monitor RDS Reserved Instances
        rds_alerts = monitor_rds_reservations(rds, table, current_time, expiration_warning_days, critical_expiration_days)
        
        # Combine all alerts
        all_alerts = ec2_alerts + rds_alerts
        
        # Generate monitoring report
        monitoring_report = {
            'monitoring_date': current_time.strftime('%Y-%m-%d %H:%M:%S'),
            'ec2_reservations_monitored': len([a for a in ec2_alerts if a.get('service') == 'EC2']),
            'rds_reservations_monitored': len([a for a in rds_alerts if a.get('service') == 'RDS']),
            'total_alerts': len(all_alerts),
            'critical_alerts': len([a for a in all_alerts if a.get('severity') == 'CRITICAL']),
            'warning_alerts': len([a for a in all_alerts if a.get('severity') == 'WARNING']),
            'alerts': all_alerts,
            'thresholds': {
                'warning_days': expiration_warning_days,
                'critical_days': critical_expiration_days
            }
        }
        
        # Send alerts if any
        if all_alerts:
            try:
                send_monitoring_alerts(sns, sns_topic_arn, monitoring_report, slack_webhook_url)
                logger.info(f"Sent {len(all_alerts)} monitoring alerts")
            except Exception as e:
                logger.error(f"Failed to send alerts: {e}")
        
        logger.info(f"RI monitoring completed. Found {len(all_alerts)} alerts")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI monitoring completed successfully',
                'total_reservations_monitored': monitoring_report['ec2_reservations_monitored'] + monitoring_report['rds_reservations_monitored'],
                'alerts_generated': len(all_alerts),
                'critical_alerts': monitoring_report['critical_alerts'],
                'warning_alerts': monitoring_report['warning_alerts']
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

def monitor_ec2_reservations(ec2_client, table, current_time: datetime.datetime, warning_days: int, critical_days: int) -> List[Dict]:
    """
    Monitor EC2 Reserved Instances for expirations and issues.
    
    Args:
        ec2_client: Boto3 EC2 client
        table: DynamoDB table resource
        current_time: Current UTC datetime
        warning_days: Days before expiration to warn
        critical_days: Days before expiration for critical alert
        
    Returns:
        List of alert dictionaries
    """
    alerts = []
    
    try:
        # Get active EC2 Reserved Instances
        response = ec2_client.describe_reserved_instances(
            Filters=[
                {
                    'Name': 'state',
                    'Values': ['active']
                }
            ]
        )
        
        logger.info(f"Found {len(response['ReservedInstances'])} active EC2 Reserved Instances")
        
        for ri in response['ReservedInstances']:
            ri_id = ri['ReservedInstancesId']
            end_date = ri['End']
            
            # Calculate days until expiration
            days_until_expiration = (end_date.replace(tzinfo=None) - current_time).days
            
            # Store RI data in DynamoDB
            try:
                table.put_item(
                    Item={
                        'ReservationId': ri_id,
                        'Timestamp': int(current_time.timestamp()),
                        'Service': 'EC2',
                        'InstanceType': ri['InstanceType'],
                        'InstanceCount': ri['InstanceCount'],
                        'State': ri['State'],
                        'Start': ri['Start'].isoformat(),
                        'End': ri['End'].isoformat(),
                        'Duration': ri['Duration'],
                        'OfferingClass': ri['OfferingClass'],
                        'OfferingType': ri['OfferingType'],
                        'DaysUntilExpiration': days_until_expiration,
                        'AvailabilityZone': ri.get('AvailabilityZone', 'N/A'),
                        'Region': ri['AvailabilityZone'][:-1] if ri.get('AvailabilityZone') else 'N/A',
                        'Platform': ri.get('ProductDescription', 'N/A'),
                        'Scope': ri.get('Scope', 'Region'),
                        'CurrencyCode': ri.get('CurrencyCode', 'USD'),
                        'FixedPrice': float(ri.get('FixedPrice', 0)),
                        'UsagePrice': float(ri.get('UsagePrice', 0))
                    }
                )
            except Exception as e:
                logger.warning(f"Failed to store RI data for {ri_id}: {e}")
            
            # Check for expiration alerts
            alert = check_expiration_alert(ri, days_until_expiration, warning_days, critical_days, 'EC2')
            if alert:
                alerts.append(alert)
                
    except ClientError as e:
        logger.error(f"Failed to describe EC2 Reserved Instances: {e}")
        
    return alerts

def monitor_rds_reservations(rds_client, table, current_time: datetime.datetime, warning_days: int, critical_days: int) -> List[Dict]:
    """
    Monitor RDS Reserved Instances for expirations and issues.
    
    Args:
        rds_client: Boto3 RDS client
        table: DynamoDB table resource
        current_time: Current UTC datetime
        warning_days: Days before expiration to warn
        critical_days: Days before expiration for critical alert
        
    Returns:
        List of alert dictionaries
    """
    alerts = []
    
    try:
        # Get active RDS Reserved Instances
        response = rds_client.describe_reserved_db_instances()
        
        active_rds_ris = [ri for ri in response['ReservedDBInstances'] if ri['State'] == 'active']
        logger.info(f"Found {len(active_rds_ris)} active RDS Reserved Instances")
        
        for ri in active_rds_ris:
            ri_id = ri['ReservedDBInstanceId']
            end_date = ri['StartTime'] + datetime.timedelta(seconds=ri['Duration'])
            
            # Calculate days until expiration
            days_until_expiration = (end_date.replace(tzinfo=None) - current_time).days
            
            # Store RI data in DynamoDB
            try:
                table.put_item(
                    Item={
                        'ReservationId': ri_id,
                        'Timestamp': int(current_time.timestamp()),
                        'Service': 'RDS',
                        'InstanceType': ri['DBInstanceClass'],
                        'InstanceCount': ri['DBInstanceCount'],
                        'State': ri['State'],
                        'Start': ri['StartTime'].isoformat(),
                        'End': end_date.isoformat(),
                        'Duration': ri['Duration'],
                        'OfferingType': ri['OfferingType'],
                        'DaysUntilExpiration': days_until_expiration,
                        'Engine': ri['ProductDescription'],
                        'MultiAZ': ri.get('MultiAZ', False),
                        'CurrencyCode': ri.get('CurrencyCode', 'USD'),
                        'FixedPrice': float(ri.get('FixedPrice', 0)),
                        'UsagePrice': float(ri.get('UsagePrice', 0))
                    }
                )
            except Exception as e:
                logger.warning(f"Failed to store RDS RI data for {ri_id}: {e}")
            
            # Check for expiration alerts
            alert = check_expiration_alert_rds(ri, end_date, days_until_expiration, warning_days, critical_days)
            if alert:
                alerts.append(alert)
                
    except ClientError as e:
        logger.error(f"Failed to describe RDS Reserved Instances: {e}")
        
    return alerts

def check_expiration_alert(ri: Dict, days_until_expiration: int, warning_days: int, critical_days: int, service: str) -> Dict:
    """
    Check if RI needs expiration alert.
    
    Args:
        ri: Reserved Instance details
        days_until_expiration: Days until RI expires
        warning_days: Warning threshold
        critical_days: Critical threshold
        service: Service type (EC2/RDS)
        
    Returns:
        Alert dictionary or None
    """
    if days_until_expiration <= critical_days:
        severity = 'CRITICAL'
        alert_type = 'EXPIRING_VERY_SOON'
    elif days_until_expiration <= warning_days:
        severity = 'WARNING'
        alert_type = 'EXPIRING_SOON'
    else:
        return None
    
    return {
        'service': service,
        'reservation_id': ri['ReservedInstancesId'],
        'instance_type': ri['InstanceType'],
        'instance_count': ri['InstanceCount'],
        'days_until_expiration': days_until_expiration,
        'end_date': ri['End'].strftime('%Y-%m-%d'),
        'severity': severity,
        'alert_type': alert_type,
        'offering_class': ri.get('OfferingClass', 'N/A'),
        'offering_type': ri.get('OfferingType', 'N/A'),
        'availability_zone': ri.get('AvailabilityZone', 'N/A'),
        'estimated_monthly_cost': estimate_monthly_cost(ri, service)
    }

def check_expiration_alert_rds(ri: Dict, end_date: datetime.datetime, days_until_expiration: int, warning_days: int, critical_days: int) -> Dict:
    """
    Check if RDS RI needs expiration alert.
    
    Args:
        ri: RDS Reserved Instance details
        end_date: Calculated end date
        days_until_expiration: Days until RI expires
        warning_days: Warning threshold
        critical_days: Critical threshold
        
    Returns:
        Alert dictionary or None
    """
    if days_until_expiration <= critical_days:
        severity = 'CRITICAL'
        alert_type = 'EXPIRING_VERY_SOON'
    elif days_until_expiration <= warning_days:
        severity = 'WARNING'
        alert_type = 'EXPIRING_SOON'
    else:
        return None
    
    return {
        'service': 'RDS',
        'reservation_id': ri['ReservedDBInstanceId'],
        'instance_type': ri['DBInstanceClass'],
        'instance_count': ri['DBInstanceCount'],
        'days_until_expiration': days_until_expiration,
        'end_date': end_date.strftime('%Y-%m-%d'),
        'severity': severity,
        'alert_type': alert_type,
        'offering_type': ri.get('OfferingType', 'N/A'),
        'database_engine': ri['ProductDescription'],
        'multi_az': ri.get('MultiAZ', False),
        'estimated_monthly_cost': estimate_monthly_cost(ri, 'RDS')
    }

def estimate_monthly_cost(ri: Dict, service: str) -> float:
    """
    Estimate monthly cost impact of RI expiration.
    
    Args:
        ri: Reserved Instance details
        service: Service type
        
    Returns:
        Estimated monthly cost in USD
    """
    try:
        if service == 'EC2':
            # Simplified estimation based on instance type and count
            instance_count = ri.get('InstanceCount', 1)
            
            # Basic hourly rates (these are rough estimates)
            base_rates = {
                't2': 0.05, 't3': 0.06, 'm5': 0.10, 'c5': 0.09,
                'r5': 0.15, 'i3': 0.20, 'x1': 0.50
            }
            
            instance_family = ri['InstanceType'].split('.')[0]
            hourly_rate = base_rates.get(instance_family, 0.10)
            
            return round(hourly_rate * 24 * 30 * instance_count, 2)
            
        elif service == 'RDS':
            # Simplified estimation for RDS
            instance_count = ri.get('DBInstanceCount', 1)
            
            # Basic hourly rates for RDS (rough estimates)
            base_rates = {
                'db.t2': 0.08, 'db.t3': 0.09, 'db.m5': 0.20,
                'db.r5': 0.25, 'db.x1': 0.60
            }
            
            instance_family = '.'.join(ri['DBInstanceClass'].split('.')[:2])
            hourly_rate = base_rates.get(instance_family, 0.15)
            
            # Factor in Multi-AZ
            if ri.get('MultiAZ', False):
                hourly_rate *= 2
            
            return round(hourly_rate * 24 * 30 * instance_count, 2)
            
    except Exception as e:
        logger.warning(f"Failed to estimate monthly cost: {e}")
        
    return 0.0

def send_monitoring_alerts(sns_client, topic_arn: str, monitoring_report: Dict, slack_webhook_url: str = "") -> None:
    """
    Send monitoring alerts via SNS and optionally Slack.
    
    Args:
        sns_client: Boto3 SNS client
        topic_arn: SNS topic ARN
        monitoring_report: Complete monitoring report
        slack_webhook_url: Optional Slack webhook URL
    """
    alerts = monitoring_report['alerts']
    
    if not alerts:
        return
    
    critical_alerts = [a for a in alerts if a.get('severity') == 'CRITICAL']
    warning_alerts = [a for a in alerts if a.get('severity') == 'WARNING']
    
    # Prepare SNS message
    message = f"Reserved Instance Expiration Alert Report\\n\\n"
    message += f"Monitoring Date: {monitoring_report['monitoring_date']}\\n"
    message += f"Total Alerts: {len(alerts)}\\n"
    message += f"Critical Alerts: {len(critical_alerts)}\\n"
    message += f"Warning Alerts: {len(warning_alerts)}\\n\\n"
    
    if critical_alerts:
        message += "🚨 CRITICAL - EXPIRING VERY SOON:\\n"
        for alert in critical_alerts:
            message += f"- {alert['service']}: {alert['reservation_id']}\\n"
            message += f"  Type: {alert['instance_type']} (Count: {alert['instance_count']})\\n"
            message += f"  Expires: {alert['end_date']} ({alert['days_until_expiration']} days)\\n"
            message += f"  Est. Monthly Impact: ${alert['estimated_monthly_cost']}\\n\\n"
    
    if warning_alerts:
        message += "⚠️  WARNING - EXPIRING SOON:\\n"
        for alert in warning_alerts:
            message += f"- {alert['service']}: {alert['reservation_id']}\\n"
            message += f"  Type: {alert['instance_type']} (Count: {alert['instance_count']})\\n"
            message += f"  Expires: {alert['end_date']} ({alert['days_until_expiration']} days)\\n"
            message += f"  Est. Monthly Impact: ${alert['estimated_monthly_cost']}\\n\\n"
    
    message += "Please review and plan for RI renewals or capacity adjustments.\\n"
    message += f"Thresholds: Warning at {monitoring_report['thresholds']['warning_days']} days, Critical at {monitoring_report['thresholds']['critical_days']} days"
    
    # Send SNS notification
    sns_client.publish(
        TopicArn=topic_arn,
        Subject="Reserved Instance Expiration Alert",
        Message=message
    )
    
    # Send Slack notification if webhook URL provided
    if slack_webhook_url:
        try:
            import urllib3
            http = urllib3.PoolManager()
            
            color = "danger" if critical_alerts else "warning"
            emoji = "🚨" if critical_alerts else "⚠️"
            
            slack_message = {
                "text": f"{emoji} Reserved Instance Expiration Alert",
                "attachments": [
                    {
                        "color": color,
                        "fields": [
                            {
                                "title": "Total Alerts",
                                "value": str(len(alerts)),
                                "short": True
                            },
                            {
                                "title": "Critical",
                                "value": str(len(critical_alerts)),
                                "short": True
                            },
                            {
                                "title": "Warnings",
                                "value": str(len(warning_alerts)),
                                "short": True
                            }
                        ],
                        "text": f"Expiring RIs require attention. Check AWS console for renewal options."
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