"""
Security Log Processor Lambda Function

This Lambda function processes VPC Lattice access logs, correlates them with
GuardDuty findings, and generates security compliance reports. It analyzes
network traffic patterns, identifies anomalies, and creates automated alerts
for security violations.

Key Features:
- Real-time processing of VPC Lattice access logs
- Correlation with GuardDuty threat intelligence
- Automated security metrics generation
- Compliance report generation and storage
- Real-time alerting for security violations
"""

import json
import boto3
import os
import logging
import gzip
import base64
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from dataclasses import dataclass

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
guardduty = boto3.client('guardduty')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')
s3 = boto3.client('s3')


@dataclass
class SecurityAnalysisResult:
    """Data class for security analysis results"""
    is_suspicious: bool
    risk_score: int
    reasons: List[str]
    log_entry: Dict[str, Any]
    timestamp: Optional[str] = None


@dataclass
class ComplianceMetrics:
    """Data class for compliance metrics"""
    total_requests: int
    error_rate: float
    average_duration_ms: float
    total_bytes_transferred: int
    suspicious_activity_count: int


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing security logs and GuardDuty findings
    
    Args:
        event: Lambda event containing log data or GuardDuty finding
        context: Lambda runtime context
        
    Returns:
        Dict containing processing results
    """
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Determine event type and process accordingly
        if 'awslogs' in event:
            # CloudWatch Logs event from VPC Lattice
            return process_vpc_lattice_logs(event, context)
        elif event.get('source') == 'aws.guardduty':
            # GuardDuty finding event
            return process_guardduty_finding(event, context)
        else:
            logger.warning(f"Unknown event type: {event}")
            return {
                'statusCode': 400,
                'body': json.dumps('Unknown event type')
            }
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }


def process_vpc_lattice_logs(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process VPC Lattice access logs from CloudWatch Logs
    
    Args:
        event: CloudWatch Logs event
        context: Lambda context
        
    Returns:
        Processing results
    """
    try:
        # Decode and decompress CloudWatch Logs data
        cw_data = event['awslogs']['data']
        compressed_payload = base64.b64decode(cw_data)
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_data = json.loads(uncompressed_payload)
        
        logger.info(f"Processing {len(log_data['logEvents'])} log events")
        
        suspicious_activities = []
        metrics_data = []
        
        # Process each log event
        for log_event in log_data['logEvents']:
            try:
                # Parse log entry (assuming JSON format)
                if log_event['message'].strip().startswith('{'):
                    log_entry = json.loads(log_event['message'])
                else:
                    # Handle non-JSON log entries
                    log_entry = parse_non_json_log(log_event['message'])
                
                # Analyze access patterns for security threats
                analysis_result = analyze_access_log(log_entry)
                
                if analysis_result.is_suspicious:
                    suspicious_activities.append(analysis_result)
                    logger.warning(f"Suspicious activity detected: {analysis_result}")
                
                # Collect metrics for compliance reporting
                metrics_data.append(extract_metrics(log_entry))
                
            except json.JSONDecodeError:
                logger.warning(f"Failed to parse log entry: {log_event['message']}")
                continue
            except Exception as e:
                logger.error(f"Error processing log event: {str(e)}")
                continue
        
        # Get recent GuardDuty findings for correlation
        recent_findings = get_recent_guardduty_findings()
        
        # Generate comprehensive compliance report
        compliance_report = generate_compliance_report(
            suspicious_activities, metrics_data, recent_findings
        )
        
        # Store compliance report in S3
        store_compliance_report(compliance_report)
        
        # Send security alerts if necessary
        if suspicious_activities:
            send_security_alert(suspicious_activities, recent_findings)
        
        # Publish metrics to CloudWatch
        publish_metrics(metrics_data, len(suspicious_activities))
        
        logger.info(f"Successfully processed {len(log_data['logEvents'])} log events")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processed_events': len(log_data['logEvents']),
                'suspicious_activities': len(suspicious_activities),
                'guardduty_findings': len(recent_findings)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing VPC Lattice logs: {str(e)}", exc_info=True)
        raise


def process_guardduty_finding(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process GuardDuty finding events
    
    Args:
        event: GuardDuty finding event
        context: Lambda context
        
    Returns:
        Processing results
    """
    try:
        finding = event.get('detail', {})
        logger.info(f"Processing GuardDuty finding: {finding.get('title', 'Unknown')}")
        
        # Extract finding details
        finding_info = {
            'id': finding.get('id'),
            'title': finding.get('title'),
            'description': finding.get('description'),
            'severity': finding.get('severity'),
            'type': finding.get('type'),
            'timestamp': event.get('time'),
            'region': finding.get('region'),
            'account_id': finding.get('accountId')
        }
        
        # Store finding for correlation with VPC Lattice logs
        store_guardduty_finding(finding_info)
        
        # Send immediate alert for high-severity findings
        if finding.get('severity', 0) >= 7.0:
            send_high_severity_alert(finding_info)
        
        # Update security metrics
        publish_guardduty_metrics(finding_info)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'finding_id': finding_info['id'],
                'severity': finding_info['severity'],
                'processed': True
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing GuardDuty finding: {str(e)}", exc_info=True)
        raise


def parse_non_json_log(log_message: str) -> Dict[str, Any]:
    """
    Parse non-JSON log messages into structured format
    
    Args:
        log_message: Raw log message string
        
    Returns:
        Parsed log entry dictionary
    """
    # Basic parsing for common log formats
    # This is a simplified parser - extend based on actual log format
    return {
        'message': log_message,
        'timestamp': datetime.utcnow().isoformat(),
        'raw': True
    }


def analyze_access_log(log_entry: Dict[str, Any]) -> SecurityAnalysisResult:
    """
    Analyze VPC Lattice access log for suspicious patterns
    
    Args:
        log_entry: Parsed log entry
        
    Returns:
        Security analysis result
    """
    is_suspicious = False
    risk_score = 0
    reasons = []
    
    # Check for high error rates (4xx/5xx responses)
    response_code = log_entry.get('responseCode', 0)
    if response_code >= 400:
        if response_code >= 500:
            risk_score += 25
            reasons.append('Server error response (5xx)')
        else:
            risk_score += 15
            reasons.append('Client error response (4xx)')
    
    # Check for potentially sensitive HTTP methods
    method = log_entry.get('requestMethod', '').upper()
    if method in ['PUT', 'DELETE', 'PATCH']:
        risk_score += 10
        reasons.append(f'Potentially sensitive operation: {method}')
    
    # Check for authentication failures
    auth_denied = log_entry.get('authDeniedReason')
    if auth_denied:
        risk_score += 30
        reasons.append(f'Authentication failure: {auth_denied}')
    
    # Check for unusual response times (potential DoS or system stress)
    duration = log_entry.get('duration', 0)
    if duration > 10000:  # More than 10 seconds
        risk_score += 15
        reasons.append(f'Unusually long response time: {duration}ms')
    
    # Check for large request/response sizes (potential data exfiltration)
    bytes_sent = log_entry.get('bytesSent', 0)
    bytes_received = log_entry.get('bytesReceived', 0)
    
    if bytes_sent > 10 * 1024 * 1024:  # > 10MB
        risk_score += 20
        reasons.append(f'Large response size: {bytes_sent} bytes')
    
    if bytes_received > 100 * 1024 * 1024:  # > 100MB
        risk_score += 25
        reasons.append(f'Large request size: {bytes_received} bytes')
    
    # Check for suspicious user agents or referrers
    user_agent = log_entry.get('userAgent', '').lower()
    suspicious_agents = ['curl', 'wget', 'python-requests', 'bot', 'scanner']
    if any(agent in user_agent for agent in suspicious_agents):
        risk_score += 10
        reasons.append(f'Suspicious user agent: {user_agent}')
    
    # Check for repeated requests from same source (potential brute force)
    # This would require maintaining state across invocations in production
    
    # Mark as suspicious if risk score exceeds threshold
    if risk_score >= 25:
        is_suspicious = True
    
    return SecurityAnalysisResult(
        is_suspicious=is_suspicious,
        risk_score=risk_score,
        reasons=reasons,
        log_entry=log_entry,
        timestamp=log_entry.get('startTime') or log_entry.get('timestamp')
    )


def get_recent_guardduty_findings() -> List[Dict[str, Any]]:
    """
    Retrieve recent GuardDuty findings for correlation
    
    Returns:
        List of recent GuardDuty findings
    """
    detector_id = os.environ.get('GUARDDUTY_DETECTOR_ID')
    if not detector_id:
        logger.warning("GuardDuty detector ID not configured")
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
            return findings_response['Findings']
        
        return []
        
    except Exception as e:
        logger.error(f"Error retrieving GuardDuty findings: {str(e)}")
        return []


def generate_compliance_report(
    suspicious_activities: List[SecurityAnalysisResult],
    metrics_data: List[Dict[str, Any]],
    guardduty_findings: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Generate comprehensive compliance report
    
    Args:
        suspicious_activities: List of suspicious activities detected
        metrics_data: List of metric data points
        guardduty_findings: List of GuardDuty findings
        
    Returns:
        Compliance report dictionary
    """
    # Calculate summary metrics
    summary_metrics = calculate_summary_metrics(metrics_data)
    
    # Determine compliance status
    compliance_status = "COMPLIANT"
    if suspicious_activities or guardduty_findings:
        compliance_status = "NON_COMPLIANT"
    elif summary_metrics.error_rate > 5.0:  # > 5% error rate
        compliance_status = "WARNING"
    
    report = {
        'timestamp': datetime.utcnow().isoformat(),
        'report_version': '1.0',
        'summary': {
            'total_requests': summary_metrics.total_requests,
            'suspicious_activities': len(suspicious_activities),
            'guardduty_findings': len(guardduty_findings),
            'compliance_status': compliance_status,
            'error_rate_percent': round(summary_metrics.error_rate, 2),
            'average_response_time_ms': round(summary_metrics.average_duration_ms, 2)
        },
        'suspicious_activities': [
            {
                'timestamp': activity.timestamp,
                'risk_score': activity.risk_score,
                'reasons': activity.reasons,
                'source_ip': activity.log_entry.get('sourceIp'),
                'target_service': activity.log_entry.get('targetService'),
                'method': activity.log_entry.get('requestMethod'),
                'response_code': activity.log_entry.get('responseCode')
            }
            for activity in suspicious_activities[:10]  # Limit to top 10
        ],
        'guardduty_findings': [
            {
                'title': finding.get('Title'),
                'severity': finding.get('Severity'),
                'type': finding.get('Type'),
                'updated_at': finding.get('UpdatedAt'),
                'region': finding.get('Region')
            }
            for finding in guardduty_findings[:5]  # Limit to top 5
        ],
        'metrics': {
            'total_requests': summary_metrics.total_requests,
            'error_rate_percent': summary_metrics.error_rate,
            'average_duration_ms': summary_metrics.average_duration_ms,
            'total_bytes_transferred': summary_metrics.total_bytes_transferred,
            'suspicious_activity_count': summary_metrics.suspicious_activity_count
        },
        'compliance_framework': {
            'framework': 'AWS Security Best Practices',
            'controls_evaluated': [
                'Network Traffic Monitoring',
                'Threat Detection',
                'Incident Response',
                'Access Logging'
            ],
            'passing_controls': 4 - (1 if suspicious_activities else 0) - (1 if guardduty_findings else 0)
        }
    }
    
    return report


def store_compliance_report(report: Dict[str, Any]) -> None:
    """
    Store compliance report in S3
    
    Args:
        report: Compliance report to store
    """
    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        logger.warning("S3 bucket name not configured")
        return
    
    try:
        # Generate S3 key with timestamp partitioning
        timestamp = datetime.utcnow()
        key = f"compliance-reports/{timestamp.year}/{timestamp.month:02d}/{timestamp.day:02d}/{timestamp.hour:02d}/report-{int(timestamp.timestamp())}.json"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256',
            Metadata={
                'report-type': 'security-compliance',
                'compliance-status': report['summary']['compliance_status'],
                'generated-by': 'security-processor-lambda'
            }
        )
        
        logger.info(f"Compliance report stored: s3://{bucket_name}/{key}")
        
    except Exception as e:
        logger.error(f"Error storing compliance report: {str(e)}")


def store_guardduty_finding(finding_info: Dict[str, Any]) -> None:
    """
    Store GuardDuty finding for correlation analysis
    
    Args:
        finding_info: GuardDuty finding information
    """
    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        return
    
    try:
        timestamp = datetime.utcnow()
        key = f"guardduty-findings/{timestamp.year}/{timestamp.month:02d}/{timestamp.day:02d}/finding-{finding_info['id']}.json"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(finding_info, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"GuardDuty finding stored: s3://{bucket_name}/{key}")
        
    except Exception as e:
        logger.error(f"Error storing GuardDuty finding: {str(e)}")


def send_security_alert(
    suspicious_activities: List[SecurityAnalysisResult],
    guardduty_findings: List[Dict[str, Any]]
) -> None:
    """
    Send security alert via SNS
    
    Args:
        suspicious_activities: List of suspicious activities
        guardduty_findings: List of GuardDuty findings
    """
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        logger.warning("SNS topic ARN not configured")
        return
    
    try:
        # Create alert message
        alert_message = {
            'timestamp': datetime.utcnow().isoformat(),
            'alert_type': 'SECURITY_VIOLATION',
            'severity': determine_alert_severity(suspicious_activities, guardduty_findings),
            'summary': {
                'suspicious_activities': len(suspicious_activities),
                'guardduty_findings': len(guardduty_findings),
                'highest_risk_score': max((a.risk_score for a in suspicious_activities), default=0)
            },
            'details': {
                'top_suspicious_activities': [
                    {
                        'risk_score': activity.risk_score,
                        'reasons': activity.reasons,
                        'timestamp': activity.timestamp
                    }
                    for activity in sorted(suspicious_activities, key=lambda x: x.risk_score, reverse=True)[:3]
                ],
                'recent_guardduty_findings': [
                    finding.get('Title', 'Unknown Finding')
                    for finding in guardduty_findings[:3]
                ]
            },
            'recommended_actions': generate_recommended_actions(suspicious_activities, guardduty_findings)
        }
        
        subject = f"🚨 Security Alert - {alert_message['severity']} Severity"
        
        sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=json.dumps(alert_message, indent=2, default=str)
        )
        
        logger.info("Security alert sent successfully")
        
    except Exception as e:
        logger.error(f"Error sending security alert: {str(e)}")


def send_high_severity_alert(finding_info: Dict[str, Any]) -> None:
    """
    Send immediate alert for high-severity GuardDuty findings
    
    Args:
        finding_info: GuardDuty finding information
    """
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        return
    
    try:
        alert_message = {
            'timestamp': datetime.utcnow().isoformat(),
            'alert_type': 'HIGH_SEVERITY_FINDING',
            'finding': finding_info,
            'immediate_action_required': True
        }
        
        sns.publish(
            TopicArn=topic_arn,
            Subject=f"🔴 URGENT: High Severity Security Finding - {finding_info['title']}",
            Message=json.dumps(alert_message, indent=2, default=str)
        )
        
        logger.warning(f"High severity alert sent for finding: {finding_info['id']}")
        
    except Exception as e:
        logger.error(f"Error sending high severity alert: {str(e)}")


def determine_alert_severity(
    suspicious_activities: List[SecurityAnalysisResult],
    guardduty_findings: List[Dict[str, Any]]
) -> str:
    """
    Determine alert severity based on activities and findings
    
    Args:
        suspicious_activities: List of suspicious activities
        guardduty_findings: List of GuardDuty findings
        
    Returns:
        Severity level string
    """
    if guardduty_findings:
        max_gd_severity = max((f.get('Severity', 0) for f in guardduty_findings), default=0)
        if max_gd_severity >= 7.0:
            return 'CRITICAL'
        elif max_gd_severity >= 4.0:
            return 'HIGH'
    
    if suspicious_activities:
        max_risk_score = max(a.risk_score for a in suspicious_activities)
        if max_risk_score >= 50:
            return 'HIGH'
        elif max_risk_score >= 30:
            return 'MEDIUM'
    
    return 'LOW'


def generate_recommended_actions(
    suspicious_activities: List[SecurityAnalysisResult],
    guardduty_findings: List[Dict[str, Any]]
) -> List[str]:
    """
    Generate recommended actions based on detected issues
    
    Args:
        suspicious_activities: List of suspicious activities
        guardduty_findings: List of GuardDuty findings
        
    Returns:
        List of recommended actions
    """
    actions = []
    
    if guardduty_findings:
        actions.append("Review GuardDuty findings in AWS Console")
        actions.append("Verify affected resources are secure")
    
    if suspicious_activities:
        actions.append("Investigate suspicious network traffic patterns")
        actions.append("Review access logs for potential security incidents")
        
        # Check for specific patterns
        auth_failures = [a for a in suspicious_activities if 'Authentication failure' in a.reasons]
        if auth_failures:
            actions.append("Review authentication failures and consider IP blocking")
        
        high_error_rates = [a for a in suspicious_activities if any('error' in r.lower() for r in a.reasons)]
        if high_error_rates:
            actions.append("Investigate application errors for potential attacks")
    
    if not actions:
        actions.append("Continue monitoring - no immediate action required")
    
    return actions


def extract_metrics(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract metrics from log entry
    
    Args:
        log_entry: Parsed log entry
        
    Returns:
        Metrics dictionary
    """
    return {
        'response_code': log_entry.get('responseCode', 0),
        'duration': log_entry.get('duration', 0),
        'bytes_sent': log_entry.get('bytesSent', 0),
        'bytes_received': log_entry.get('bytesReceived', 0),
        'method': log_entry.get('requestMethod', 'UNKNOWN'),
        'timestamp': log_entry.get('startTime') or log_entry.get('timestamp')
    }


def calculate_summary_metrics(metrics_data: List[Dict[str, Any]]) -> ComplianceMetrics:
    """
    Calculate summary metrics from collected data
    
    Args:
        metrics_data: List of metrics data points
        
    Returns:
        Calculated compliance metrics
    """
    if not metrics_data:
        return ComplianceMetrics(0, 0.0, 0.0, 0, 0)
    
    total_requests = len(metrics_data)
    error_count = sum(1 for m in metrics_data if m['response_code'] >= 400)
    error_rate = (error_count / total_requests) * 100 if total_requests > 0 else 0
    
    avg_duration = sum(m['duration'] for m in metrics_data) / total_requests
    total_bytes = sum(m['bytes_sent'] + m['bytes_received'] for m in metrics_data)
    
    return ComplianceMetrics(
        total_requests=total_requests,
        error_rate=error_rate,
        average_duration_ms=avg_duration,
        total_bytes_transferred=total_bytes,
        suspicious_activity_count=0  # This will be set by caller
    )


def publish_metrics(metrics_data: List[Dict[str, Any]], suspicious_count: int) -> None:
    """
    Publish custom metrics to CloudWatch
    
    Args:
        metrics_data: List of metrics data points
        suspicious_count: Number of suspicious activities detected
    """
    if not metrics_data:
        return
    
    try:
        summary_metrics = calculate_summary_metrics(metrics_data)
        
        # Publish metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Security/VPCLattice',
            MetricData=[
                {
                    'MetricName': 'RequestCount',
                    'Value': summary_metrics.total_requests,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'ErrorCount',
                    'Value': sum(1 for m in metrics_data if m['response_code'] >= 400),
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'AverageResponseTime',
                    'Value': summary_metrics.average_duration_ms,
                    'Unit': 'Milliseconds',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'SuspiciousActivityCount',
                    'Value': suspicious_count,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'ErrorRate',
                    'Value': summary_metrics.error_rate,
                    'Unit': 'Percent',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        logger.info("Metrics published to CloudWatch successfully")
        
    except Exception as e:
        logger.error(f"Error publishing metrics: {str(e)}")


def publish_guardduty_metrics(finding_info: Dict[str, Any]) -> None:
    """
    Publish GuardDuty-specific metrics to CloudWatch
    
    Args:
        finding_info: GuardDuty finding information
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='Security/GuardDuty',
            MetricData=[
                {
                    'MetricName': 'FindingCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Severity',
                            'Value': str(finding_info.get('severity', 'Unknown'))
                        },
                        {
                            'Name': 'FindingType',
                            'Value': finding_info.get('type', 'Unknown')
                        }
                    ],
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        logger.info("GuardDuty metrics published successfully")
        
    except Exception as e:
        logger.error(f"Error publishing GuardDuty metrics: {str(e)}")