"""
Security Compliance Processor Lambda Function

This function processes VPC Lattice access logs, correlates them with GuardDuty findings,
and generates security metrics and compliance reports.

Key Features:
- Analyzes VPC Lattice access logs for suspicious patterns
- Correlates network traffic with GuardDuty threat intelligence
- Generates compliance reports and stores them in S3
- Publishes custom security metrics to CloudWatch
- Sends real-time alerts via SNS for security violations
"""

import json
import boto3
import os
from datetime import datetime, timedelta
import gzip
import base64
from typing import Dict, List, Any, Optional
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
guardduty = boto3.client('guardduty')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')
s3 = boto3.client('s3')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing VPC Lattice access logs
    
    Args:
        event: CloudWatch Logs event containing VPC Lattice access logs
        context: Lambda context object
        
    Returns:
        Response with status code and processing summary
    """
    try:
        logger.info("Starting security log processing")
        
        # Process CloudWatch Logs events
        cw_data = event['awslogs']['data']
        compressed_payload = base64.b64decode(cw_data)
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_data = json.loads(uncompressed_payload)
        
        suspicious_activities = []
        metrics_data = []
        
        # Process each log event
        for log_event in log_data['logEvents']:
            try:
                log_entry = json.loads(log_event['message'])
                
                # Analyze access patterns for security threats
                analysis_result = analyze_access_log(log_entry)
                
                if analysis_result['is_suspicious']:
                    suspicious_activities.append(analysis_result)
                    logger.warning(f"Suspicious activity detected: {analysis_result['reasons']}")
                
                # Collect metrics for analysis
                metrics_data.append(extract_metrics(log_entry))
                
            except json.JSONDecodeError:
                logger.error(f"Failed to parse log entry: {log_event['message']}")
                continue
            except Exception as e:
                logger.error(f"Error processing log event: {str(e)}")
                continue
        
        # Correlate with GuardDuty findings
        recent_findings = get_recent_guardduty_findings()
        
        # Generate comprehensive compliance report
        compliance_report = generate_compliance_report(
            suspicious_activities, metrics_data, recent_findings
        )
        
        # Store report in S3 for audit purposes
        store_compliance_report(compliance_report)
        
        # Send alerts if security violations detected
        if suspicious_activities or recent_findings:
            send_security_alert(suspicious_activities, recent_findings)
        
        # Publish metrics to CloudWatch
        publish_metrics(metrics_data)
        
        logger.info(f"Successfully processed {len(log_data['logEvents'])} log events")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Processed {len(log_data["logEvents"])} log events',
                'suspicious_activities': len(suspicious_activities),
                'guardduty_findings': len(recent_findings)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing logs: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }


def analyze_access_log(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze VPC Lattice access log for suspicious patterns
    
    Args:
        log_entry: Parsed VPC Lattice access log entry
        
    Returns:
        Analysis result with risk assessment
    """
    is_suspicious = False
    risk_score = 0
    reasons = []
    
    # Check for HTTP error responses (potential probing or attacks)
    response_code = log_entry.get('responseCode', 0)
    if response_code >= 400:
        risk_score += 20
        reasons.append(f'HTTP error response: {response_code}')
    
    # Check for potentially sensitive operations
    request_method = log_entry.get('requestMethod', '')
    if request_method in ['PUT', 'DELETE', 'PATCH']:
        risk_score += 10
        reasons.append(f'Potentially sensitive operation: {request_method}')
    
    # Check for authentication failures
    auth_denied_reason = log_entry.get('authDeniedReason')
    if auth_denied_reason:
        risk_score += 30
        reasons.append(f'Authentication failure: {auth_denied_reason}')
    
    # Check for unusual response times (potential DoS or resource exhaustion)
    duration = log_entry.get('duration', 0)
    if duration > 10000:  # More than 10 seconds
        risk_score += 15
        reasons.append(f'Unusually long response time: {duration}ms')
    
    # Check for suspicious user agents or request patterns
    user_agent = log_entry.get('userAgent', '')
    if any(pattern in user_agent.lower() for pattern in ['bot', 'crawler', 'scanner', 'exploit']):
        risk_score += 25
        reasons.append(f'Suspicious user agent: {user_agent}')
    
    # Check for unusual request sizes (potential data exfiltration)
    bytes_sent = log_entry.get('bytesSent', 0)
    if bytes_sent > 10 * 1024 * 1024:  # More than 10MB
        risk_score += 20
        reasons.append(f'Large response size: {bytes_sent} bytes')
    
    # Mark as suspicious if risk score exceeds threshold
    if risk_score >= 25:
        is_suspicious = True
    
    return {
        'is_suspicious': is_suspicious,
        'risk_score': risk_score,
        'reasons': reasons,
        'log_entry': log_entry,
        'timestamp': log_entry.get('startTime'),
        'source_ip': log_entry.get('sourceIpAddress'),
        'target_service': log_entry.get('serviceName')
    }


def get_recent_guardduty_findings() -> List[Dict[str, Any]]:
    """
    Retrieve recent GuardDuty findings for correlation
    
    Returns:
        List of recent GuardDuty findings
    """
    detector_id = os.environ.get('GUARDDUTY_DETECTOR_ID')
    if not detector_id:
        logger.warning("GuardDuty detector ID not found in environment variables")
        return []
    
    try:
        # Get findings from the last hour
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        response = guardduty.list_findings(
            DetectorId=detector_id,
            FindingCriteria={
                'Criterion': {
                    'updatedAt': {
                        'Gte': int(start_time.timestamp() * 1000),
                        'Lte': int(end_time.timestamp() * 1000)
                    }
                }
            },
            MaxResults=50
        )
        
        if response['FindingIds']:
            findings_response = guardduty.get_findings(
                DetectorId=detector_id,
                FindingIds=response['FindingIds']
            )
            logger.info(f"Retrieved {len(findings_response['Findings'])} GuardDuty findings")
            return findings_response['Findings']
        
        return []
        
    except Exception as e:
        logger.error(f"Error retrieving GuardDuty findings: {str(e)}")
        return []


def generate_compliance_report(
    suspicious_activities: List[Dict[str, Any]], 
    metrics_data: List[Dict[str, Any]], 
    guardduty_findings: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Generate comprehensive compliance report
    
    Args:
        suspicious_activities: List of detected suspicious activities
        metrics_data: List of traffic metrics
        guardduty_findings: List of GuardDuty findings
        
    Returns:
        Comprehensive compliance report
    """
    report = {
        'timestamp': datetime.utcnow().isoformat(),
        'report_id': f"compliance-{int(datetime.utcnow().timestamp())}",
        'summary': {
            'total_requests': len(metrics_data),
            'suspicious_activities': len(suspicious_activities),
            'guardduty_findings': len(guardduty_findings),
            'compliance_status': 'COMPLIANT' if len(suspicious_activities) == 0 and len(guardduty_findings) == 0 else 'NON_COMPLIANT'
        },
        'risk_assessment': {
            'overall_risk_level': calculate_risk_level(suspicious_activities, guardduty_findings),
            'threat_indicators': extract_threat_indicators(suspicious_activities, guardduty_findings)
        },
        'suspicious_activities': suspicious_activities,
        'guardduty_findings': [
            {
                'id': finding.get('Id'),
                'type': finding.get('Type'),
                'severity': finding.get('Severity'),
                'title': finding.get('Title'),
                'description': finding.get('Description')
            } for finding in guardduty_findings
        ],
        'traffic_metrics': calculate_summary_metrics(metrics_data),
        'recommendations': generate_security_recommendations(suspicious_activities, guardduty_findings)
    }
    
    return report


def calculate_risk_level(suspicious_activities: List[Dict[str, Any]], guardduty_findings: List[Dict[str, Any]]) -> str:
    """Calculate overall risk level based on detected threats"""
    if not suspicious_activities and not guardduty_findings:
        return 'LOW'
    
    high_risk_count = sum(1 for activity in suspicious_activities if activity.get('risk_score', 0) >= 50)
    critical_findings = sum(1 for finding in guardduty_findings if finding.get('Severity', 0) >= 7.0)
    
    if high_risk_count > 0 or critical_findings > 0:
        return 'HIGH'
    elif len(suspicious_activities) > 5 or len(guardduty_findings) > 2:
        return 'MEDIUM'
    else:
        return 'LOW'


def extract_threat_indicators(suspicious_activities: List[Dict[str, Any]], guardduty_findings: List[Dict[str, Any]]) -> List[str]:
    """Extract key threat indicators from activities and findings"""
    indicators = []
    
    # Extract from suspicious activities
    for activity in suspicious_activities:
        if activity.get('source_ip'):
            indicators.append(f"Suspicious IP: {activity['source_ip']}")
        for reason in activity.get('reasons', []):
            indicators.append(f"Activity: {reason}")
    
    # Extract from GuardDuty findings
    for finding in guardduty_findings:
        if finding.get('Type'):
            indicators.append(f"GuardDuty: {finding['Type']}")
    
    return list(set(indicators))  # Remove duplicates


def generate_security_recommendations(suspicious_activities: List[Dict[str, Any]], guardduty_findings: List[Dict[str, Any]]) -> List[str]:
    """Generate security recommendations based on detected threats"""
    recommendations = []
    
    if suspicious_activities:
        recommendations.append("Review and investigate flagged suspicious network activities")
        recommendations.append("Consider implementing additional rate limiting or IP blocking")
        recommendations.append("Enhance monitoring for the identified suspicious patterns")
    
    if guardduty_findings:
        recommendations.append("Investigate GuardDuty findings immediately")
        recommendations.append("Review security group configurations and access controls")
        recommendations.append("Consider implementing automated incident response procedures")
    
    if not suspicious_activities and not guardduty_findings:
        recommendations.append("Continue monitoring - no immediate threats detected")
        recommendations.append("Review security baselines and detection rules periodically")
    
    return recommendations


def store_compliance_report(report: Dict[str, Any]) -> None:
    """
    Store compliance report in S3 for audit purposes
    
    Args:
        report: Compliance report to store
    """
    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        logger.warning("S3 bucket name not found in environment variables")
        return
    
    timestamp = datetime.utcnow().strftime('%Y/%m/%d/%H')
    key = f"compliance-reports/{timestamp}/report-{report['report_id']}.json"
    
    try:
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        logger.info(f"Compliance report stored: s3://{bucket_name}/{key}")
    except Exception as e:
        logger.error(f"Error storing compliance report: {str(e)}")


def send_security_alert(suspicious_activities: List[Dict[str, Any]], guardduty_findings: List[Dict[str, Any]]) -> None:
    """
    Send security alert via SNS
    
    Args:
        suspicious_activities: List of suspicious activities
        guardduty_findings: List of GuardDuty findings
    """
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        logger.warning("SNS topic ARN not found in environment variables")
        return
    
    alert_message = {
        'timestamp': datetime.utcnow().isoformat(),
        'alert_type': 'SECURITY_VIOLATION',
        'risk_level': calculate_risk_level(suspicious_activities, guardduty_findings),
        'summary': {
            'suspicious_count': len(suspicious_activities),
            'guardduty_count': len(guardduty_findings)
        },
        'details': {
            'suspicious_activities': suspicious_activities[:5],  # Limit to first 5
            'recent_guardduty_findings': [
                f"{finding.get('Type', 'Unknown')} - {finding.get('Title', 'No title')}" 
                for finding in guardduty_findings[:3]
            ]
        },
        'actions_required': [
            'Review security dashboard immediately',
            'Investigate flagged activities',
            'Consider implementing additional security controls'
        ]
    }
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Subject='🚨 Security Compliance Alert - Suspicious Activity Detected',
            Message=json.dumps(alert_message, indent=2, default=str)
        )
        logger.info("Security alert sent successfully")
    except Exception as e:
        logger.error(f"Error sending security alert: {str(e)}")


def extract_metrics(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract metrics from VPC Lattice log entry
    
    Args:
        log_entry: Parsed log entry
        
    Returns:
        Extracted metrics
    """
    return {
        'response_code': log_entry.get('responseCode', 0),
        'duration': log_entry.get('duration', 0),
        'bytes_sent': log_entry.get('bytesSent', 0),
        'bytes_received': log_entry.get('bytesReceived', 0),
        'method': log_entry.get('requestMethod', 'UNKNOWN'),
        'source_ip': log_entry.get('sourceIpAddress', ''),
        'service_name': log_entry.get('serviceName', ''),
        'timestamp': log_entry.get('startTime')
    }


def calculate_summary_metrics(metrics_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Calculate summary metrics from collected data
    
    Args:
        metrics_data: List of metric data points
        
    Returns:
        Summary metrics
    """
    if not metrics_data:
        return {}
    
    total_requests = len(metrics_data)
    error_count = sum(1 for m in metrics_data if m['response_code'] >= 400)
    avg_duration = sum(m['duration'] for m in metrics_data) / total_requests if total_requests > 0 else 0
    total_bytes = sum(m['bytes_sent'] + m['bytes_received'] for m in metrics_data)
    
    # Calculate method distribution
    method_distribution = {}
    for metric in metrics_data:
        method = metric['method']
        method_distribution[method] = method_distribution.get(method, 0) + 1
    
    return {
        'total_requests': total_requests,
        'error_rate': (error_count / total_requests) * 100 if total_requests > 0 else 0,
        'average_duration_ms': round(avg_duration, 2),
        'total_bytes_transferred': total_bytes,
        'method_distribution': method_distribution,
        'unique_source_ips': len(set(m['source_ip'] for m in metrics_data if m['source_ip'])),
        'unique_services': len(set(m['service_name'] for m in metrics_data if m['service_name']))
    }


def publish_metrics(metrics_data: List[Dict[str, Any]]) -> None:
    """
    Publish custom metrics to CloudWatch
    
    Args:
        metrics_data: List of metric data points
    """
    if not metrics_data:
        return
    
    try:
        # Calculate key metrics
        error_count = sum(1 for m in metrics_data if m['response_code'] >= 400)
        avg_duration = sum(m['duration'] for m in metrics_data) / len(metrics_data)
        total_bytes = sum(m['bytes_sent'] + m['bytes_received'] for m in metrics_data)
        
        # Prepare metric data
        metric_data = [
            {
                'MetricName': 'RequestCount',
                'Value': len(metrics_data),
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'ErrorCount',
                'Value': error_count,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'AverageResponseTime',
                'Value': avg_duration,
                'Unit': 'Milliseconds',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'TotalBytesTransferred',
                'Value': total_bytes,
                'Unit': 'Bytes',
                'Timestamp': datetime.utcnow()
            }
        ]
        
        # Publish metrics in batches (CloudWatch limit is 20 metrics per call)
        for i in range(0, len(metric_data), 20):
            batch = metric_data[i:i+20]
            cloudwatch.put_metric_data(
                Namespace='Security/VPCLattice',
                MetricData=batch
            )
        
        logger.info(f"Published {len(metric_data)} metrics to CloudWatch")
        
    except Exception as e:
        logger.error(f"Error publishing metrics: {str(e)}")