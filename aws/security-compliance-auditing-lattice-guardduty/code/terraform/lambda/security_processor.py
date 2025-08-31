"""
security_processor.py
Lambda function for processing VPC Lattice access logs and correlating with GuardDuty findings
for security compliance auditing and automated threat detection.

This function:
1. Processes CloudWatch Logs events from VPC Lattice
2. Analyzes access patterns for suspicious activities
3. Correlates findings with GuardDuty threat intelligence
4. Generates compliance reports and stores them in S3
5. Sends security alerts via SNS
6. Publishes custom metrics to CloudWatch
"""

import json
import boto3
import os
import logging
from datetime import datetime, timedelta
import gzip
import base64
from typing import Dict, List, Any, Optional
from botocore.exceptions import ClientError, BotoCoreError

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# Initialize AWS clients with error handling
try:
    guardduty = boto3.client('guardduty')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    s3 = boto3.client('s3')
except Exception as e:
    logger.error(f"Failed to initialize AWS clients: {str(e)}")
    raise

# Configuration constants
SUSPICIOUS_METHODS = ['PUT', 'DELETE', 'PATCH']
RISK_THRESHOLD = 25
MAX_RESPONSE_TIME_MS = 10000
METRICS_NAMESPACE = 'Security/VPCLattice'

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for processing VPC Lattice access logs.
    
    Args:
        event: CloudWatch Logs event containing compressed log data
        context: Lambda context object
        
    Returns:
        Dict containing status code and response message
    """
    try:
        logger.info(f"Processing CloudWatch Logs event: {json.dumps(event, default=str)}")
        
        # Validate event structure
        if 'awslogs' not in event or 'data' not in event['awslogs']:
            raise ValueError("Invalid event structure: missing awslogs.data")
        
        # Decode and decompress CloudWatch Logs data
        log_data = decode_cloudwatch_logs_data(event['awslogs']['data'])
        
        # Initialize processing metrics
        suspicious_activities = []
        metrics_data = []
        processing_errors = 0
        
        # Process each log event
        for log_event in log_data.get('logEvents', []):
            try:
                # Parse VPC Lattice access log entry
                log_entry = parse_log_entry(log_event['message'])
                if not log_entry:
                    continue
                
                # Analyze access patterns for suspicious activity
                analysis_result = analyze_access_log(log_entry)
                
                if analysis_result['is_suspicious']:
                    suspicious_activities.append(analysis_result)
                    logger.warning(f"Suspicious activity detected: {analysis_result['reasons']}")
                
                # Extract metrics for monitoring
                metrics_data.append(extract_metrics(log_entry))
                
            except Exception as e:
                processing_errors += 1
                logger.error(f"Failed to process log entry: {str(e)}")
                continue
        
        # Correlate with GuardDuty findings
        recent_findings = get_recent_guardduty_findings()
        
        # Generate comprehensive compliance report
        compliance_report = generate_compliance_report(
            suspicious_activities, metrics_data, recent_findings, processing_errors
        )
        
        # Store compliance report in S3
        store_compliance_report(compliance_report)
        
        # Send security alerts if necessary
        if suspicious_activities or recent_findings:
            send_security_alert(suspicious_activities, recent_findings)
        
        # Publish metrics to CloudWatch
        publish_metrics(metrics_data, processing_errors)
        
        # Log processing summary
        logger.info(f"Successfully processed {len(log_data.get('logEvents', []))} log events, "
                   f"found {len(suspicious_activities)} suspicious activities, "
                   f"{processing_errors} processing errors")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Processed {len(log_data.get("logEvents", []))} log events',
                'suspicious_activities': len(suspicious_activities),
                'guardduty_findings': len(recent_findings),
                'processing_errors': processing_errors
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing logs: {str(e)}")
        # Publish error metric
        try:
            publish_error_metric(str(e))
        except Exception as metric_error:
            logger.error(f"Failed to publish error metric: {str(metric_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process security logs'
            })
        }

def decode_cloudwatch_logs_data(encoded_data: str) -> Dict[str, Any]:
    """
    Decode and decompress CloudWatch Logs data.
    
    Args:
        encoded_data: Base64 encoded and gzipped log data
        
    Returns:
        Dict containing decoded log data
    """
    try:
        compressed_payload = base64.b64decode(encoded_data)
        uncompressed_payload = gzip.decompress(compressed_payload)
        return json.loads(uncompressed_payload)
    except Exception as e:
        logger.error(f"Failed to decode CloudWatch Logs data: {str(e)}")
        raise ValueError(f"Invalid CloudWatch Logs data format: {str(e)}")

def parse_log_entry(message: str) -> Optional[Dict[str, Any]]:
    """
    Parse VPC Lattice access log entry.
    
    Args:
        message: Raw log message string
        
    Returns:
        Parsed log entry dict or None if parsing fails
    """
    try:
        # Try to parse as JSON (structured logs)
        return json.loads(message)
    except json.JSONDecodeError:
        try:
            # Try to parse as space-separated values (if using CLF format)
            # This is a simplified parser - adjust based on your log format
            logger.debug(f"Failed to parse as JSON, attempting CLF parsing: {message}")
            return parse_clf_log_entry(message)
        except Exception as e:
            logger.warning(f"Failed to parse log entry: {message[:100]}... Error: {str(e)}")
            return None

def parse_clf_log_entry(message: str) -> Dict[str, Any]:
    """
    Parse Common Log Format or similar space-separated log entries.
    
    Args:
        message: Space-separated log message
        
    Returns:
        Dict containing parsed log fields
    """
    # This is a basic parser - customize based on your VPC Lattice log format
    parts = message.split()
    if len(parts) < 10:
        raise ValueError("Insufficient log fields")
    
    return {
        'clientIp': parts[0] if parts[0] != '-' else None,
        'timestamp': parts[3] + ' ' + parts[4] if len(parts) > 4 else None,
        'requestMethod': parts[5].strip('"') if len(parts) > 5 else None,
        'requestUri': parts[6] if len(parts) > 6 else None,
        'responseCode': int(parts[8]) if len(parts) > 8 and parts[8].isdigit() else 0,
        'duration': 0,  # Default values for missing fields
        'bytesSent': 0,
        'bytesReceived': 0
    }

def analyze_access_log(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze VPC Lattice access log for suspicious patterns.
    
    Args:
        log_entry: Parsed log entry dictionary
        
    Returns:
        Dict containing analysis results with risk assessment
    """
    is_suspicious = False
    risk_score = 0
    reasons = []
    
    try:
        # Check for HTTP error responses (4xx, 5xx)
        response_code = log_entry.get('responseCode', 0)
        if response_code >= 400:
            risk_score += 20
            reasons.append(f'HTTP error response: {response_code}')
            if response_code >= 500:
                risk_score += 10  # Server errors are more concerning
                reasons.append('Server error response')
        
        # Check for potentially sensitive HTTP methods
        request_method = log_entry.get('requestMethod', '').upper()
        if request_method in SUSPICIOUS_METHODS:
            risk_score += 10
            reasons.append(f'Potentially sensitive operation: {request_method}')
        
        # Check for authentication failures
        auth_denied_reason = log_entry.get('authDeniedReason')
        if auth_denied_reason:
            risk_score += 30
            reasons.append(f'Authentication failure: {auth_denied_reason}')
        
        # Check for unusual response times
        duration = log_entry.get('duration', 0)
        if duration > MAX_RESPONSE_TIME_MS:
            risk_score += 15
            reasons.append(f'Unusually long response time: {duration}ms')
        
        # Check for suspicious user agents
        user_agent = log_entry.get('userAgent', '').lower()
        suspicious_agents = ['bot', 'crawler', 'scanner', 'curl', 'wget']
        if any(agent in user_agent for agent in suspicious_agents):
            risk_score += 5
            reasons.append(f'Suspicious user agent: {user_agent[:50]}')
        
        # Check for high frequency requests from same IP
        client_ip = log_entry.get('clientIp')
        if client_ip and is_high_frequency_ip(client_ip):
            risk_score += 15
            reasons.append(f'High frequency requests from IP: {client_ip}')
        
        # Check for access to sensitive endpoints
        request_uri = log_entry.get('requestUri', '').lower()
        sensitive_patterns = ['/admin', '/config', '/api/v1/secrets', '/.env', '/password']
        if any(pattern in request_uri for pattern in sensitive_patterns):
            risk_score += 25
            reasons.append(f'Access to sensitive endpoint: {request_uri}')
        
        # Mark as suspicious if risk score exceeds threshold
        if risk_score >= RISK_THRESHOLD:
            is_suspicious = True
        
        return {
            'is_suspicious': is_suspicious,
            'risk_score': risk_score,
            'reasons': reasons,
            'log_entry': log_entry,
            'timestamp': log_entry.get('startTime') or log_entry.get('timestamp'),
            'client_ip': client_ip,
            'analysis_timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error analyzing access log: {str(e)}")
        return {
            'is_suspicious': False,
            'risk_score': 0,
            'reasons': [f'Analysis error: {str(e)}'],
            'log_entry': log_entry,
            'timestamp': log_entry.get('startTime') or log_entry.get('timestamp'),
            'analysis_timestamp': datetime.utcnow().isoformat()
        }

def is_high_frequency_ip(client_ip: str) -> bool:
    """
    Check if an IP address is making high frequency requests.
    This is a simplified implementation - consider using ElastiCache for production.
    
    Args:
        client_ip: Client IP address
        
    Returns:
        Boolean indicating if IP is high frequency
    """
    # In a production environment, you would use a cache like ElastiCache
    # to track IP request frequencies across multiple Lambda invocations
    # For now, this is a placeholder that could be enhanced
    
    # Known problematic IP ranges (example)
    suspicious_ranges = ['10.0.0.0/8', '192.168.0.0/16']  # Add real suspicious ranges
    
    try:
        import ipaddress
        ip = ipaddress.ip_address(client_ip)
        for range_str in suspicious_ranges:
            if ip in ipaddress.ip_network(range_str):
                return True
    except ValueError:
        pass
    
    return False

def get_recent_guardduty_findings() -> List[Dict[str, Any]]:
    """
    Retrieve recent GuardDuty findings for correlation analysis.
    
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
        
        logger.debug(f"Retrieving GuardDuty findings from {start_time} to {end_time}")
        
        response = guardduty.list_findings(
            DetectorId=detector_id,
            FindingCriteria={
                'Criterion': {
                    'updatedAt': {
                        'Gte': int(start_time.timestamp() * 1000),
                        'Lte': int(end_time.timestamp() * 1000)
                    },
                    'severity': {
                        'Gte': 1.0  # Include all severity levels
                    }
                }
            },
            MaxResults=50  # Limit to prevent excessive processing
        )
        
        finding_ids = response.get('FindingIds', [])
        if not finding_ids:
            logger.debug("No recent GuardDuty findings found")
            return []
        
        # Get detailed information for findings
        findings_response = guardduty.get_findings(
            DetectorId=detector_id,
            FindingIds=finding_ids
        )
        
        findings = findings_response.get('Findings', [])
        logger.info(f"Retrieved {len(findings)} GuardDuty findings")
        
        return findings
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'BadRequestException':
            logger.error(f"Invalid GuardDuty request: {str(e)}")
        elif error_code == 'AccessDeniedException':
            logger.error(f"Insufficient permissions for GuardDuty: {str(e)}")
        else:
            logger.error(f"GuardDuty client error: {str(e)}")
        return []
    except Exception as e:
        logger.error(f"Error retrieving GuardDuty findings: {str(e)}")
        return []

def generate_compliance_report(
    suspicious_activities: List[Dict[str, Any]], 
    metrics_data: List[Dict[str, Any]], 
    guardduty_findings: List[Dict[str, Any]],
    processing_errors: int
) -> Dict[str, Any]:
    """
    Generate comprehensive compliance report.
    
    Args:
        suspicious_activities: List of detected suspicious activities
        metrics_data: List of extracted metrics
        guardduty_findings: List of GuardDuty findings
        processing_errors: Number of processing errors encountered
        
    Returns:
        Dict containing comprehensive compliance report
    """
    try:
        # Calculate summary metrics
        summary_metrics = calculate_summary_metrics(metrics_data)
        
        # Determine compliance status
        compliance_status = 'COMPLIANT'
        if suspicious_activities or guardduty_findings:
            compliance_status = 'NON_COMPLIANT'
        elif processing_errors > 0:
            compliance_status = 'WARNING'
        
        # Generate risk assessment
        risk_assessment = generate_risk_assessment(suspicious_activities, guardduty_findings)
        
        report = {
            'report_id': f"compliance-{int(datetime.utcnow().timestamp())}",
            'timestamp': datetime.utcnow().isoformat(),
            'report_version': '1.0',
            'summary': {
                'total_requests': len(metrics_data),
                'suspicious_activities': len(suspicious_activities),
                'guardduty_findings': len(guardduty_findings),
                'processing_errors': processing_errors,
                'compliance_status': compliance_status,
                'risk_level': risk_assessment['risk_level']
            },
            'suspicious_activities': suspicious_activities[:10],  # Limit for storage efficiency
            'guardduty_findings': [
                {
                    'id': finding.get('Id'),
                    'type': finding.get('Type'),
                    'severity': finding.get('Severity'),
                    'title': finding.get('Title'),
                    'description': finding.get('Description'),
                    'updatedAt': finding.get('UpdatedAt')
                } for finding in guardduty_findings[:5]  # Limit for storage efficiency
            ],
            'metrics': summary_metrics,
            'risk_assessment': risk_assessment,
            'recommendations': generate_recommendations(suspicious_activities, guardduty_findings),
            'metadata': {
                'generated_by': 'security-compliance-processor',
                'lambda_function': os.environ.get('AWS_LAMBDA_FUNCTION_NAME'),
                'aws_region': os.environ.get('AWS_REGION'),
                'report_type': 'automated_security_compliance'
            }
        }
        
        return report
        
    except Exception as e:
        logger.error(f"Error generating compliance report: {str(e)}")
        # Return minimal report on error
        return {
            'report_id': f"compliance-error-{int(datetime.utcnow().timestamp())}",
            'timestamp': datetime.utcnow().isoformat(),
            'summary': {
                'compliance_status': 'ERROR',
                'error_message': str(e)
            }
        }

def generate_risk_assessment(
    suspicious_activities: List[Dict[str, Any]], 
    guardduty_findings: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Generate risk assessment based on detected activities and findings.
    
    Args:
        suspicious_activities: List of suspicious activities
        guardduty_findings: List of GuardDuty findings
        
    Returns:
        Dict containing risk assessment
    """
    total_risk_score = 0
    risk_factors = []
    
    # Calculate risk from suspicious activities
    for activity in suspicious_activities:
        total_risk_score += activity.get('risk_score', 0)
        risk_factors.extend(activity.get('reasons', []))
    
    # Calculate risk from GuardDuty findings
    for finding in guardduty_findings:
        severity = finding.get('Severity', 0)
        total_risk_score += severity * 10  # Scale GuardDuty severity
        risk_factors.append(f"GuardDuty: {finding.get('Type', 'Unknown')}")
    
    # Determine risk level
    if total_risk_score >= 100:
        risk_level = 'CRITICAL'
    elif total_risk_score >= 50:
        risk_level = 'HIGH'
    elif total_risk_score >= 25:
        risk_level = 'MEDIUM'
    elif total_risk_score > 0:
        risk_level = 'LOW'
    else:
        risk_level = 'MINIMAL'
    
    return {
        'risk_level': risk_level,
        'risk_score': total_risk_score,
        'risk_factors': list(set(risk_factors)),  # Remove duplicates
        'assessment_timestamp': datetime.utcnow().isoformat()
    }

def generate_recommendations(
    suspicious_activities: List[Dict[str, Any]], 
    guardduty_findings: List[Dict[str, Any]]
) -> List[str]:
    """
    Generate security recommendations based on findings.
    
    Args:
        suspicious_activities: List of suspicious activities
        guardduty_findings: List of GuardDuty findings
        
    Returns:
        List of security recommendations
    """
    recommendations = []
    
    if suspicious_activities:
        recommendations.append("Review and investigate suspicious access patterns")
        recommendations.append("Consider implementing additional access controls")
        
        # Check for specific patterns
        high_risk_activities = [a for a in suspicious_activities if a.get('risk_score', 0) >= 50]
        if high_risk_activities:
            recommendations.append("Immediately investigate high-risk activities")
    
    if guardduty_findings:
        recommendations.append("Review GuardDuty findings and take appropriate action")
        
        # Check for specific finding types
        finding_types = set(f.get('Type', '') for f in guardduty_findings)
        if any('Trojan' in t for t in finding_types):
            recommendations.append("Scan for malware and isolate affected systems")
        if any('Backdoor' in t for t in finding_types):
            recommendations.append("Check for unauthorized access and change credentials")
    
    if not suspicious_activities and not guardduty_findings:
        recommendations.append("Continue monitoring - no immediate threats detected")
        recommendations.append("Review and update security policies regularly")
    
    return recommendations

def store_compliance_report(report: Dict[str, Any]) -> None:
    """
    Store compliance report in S3 with organized structure.
    
    Args:
        report: Compliance report dictionary
    """
    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        logger.error("S3 bucket name not configured")
        return
    
    try:
        # Create organized S3 key structure
        timestamp = datetime.utcnow()
        s3_key = (f"compliance-reports/"
                 f"{timestamp.strftime('%Y/%m/%d/%H')}/"
                 f"report-{report.get('report_id', int(timestamp.timestamp()))}.json")
        
        # Store report with metadata
        s3.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json',
            Metadata={
                'report-type': 'security-compliance',
                'compliance-status': report.get('summary', {}).get('compliance_status', 'UNKNOWN'),
                'risk-level': report.get('risk_assessment', {}).get('risk_level', 'UNKNOWN'),
                'generated-by': 'lambda-security-processor'
            },
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Compliance report stored: s3://{bucket_name}/{s3_key}")
        
    except ClientError as e:
        logger.error(f"Failed to store compliance report in S3: {str(e)}")
    except Exception as e:
        logger.error(f"Error storing compliance report: {str(e)}")

def send_security_alert(
    suspicious_activities: List[Dict[str, Any]], 
    guardduty_findings: List[Dict[str, Any]]
) -> None:
    """
    Send security alert via SNS.
    
    Args:
        suspicious_activities: List of suspicious activities
        guardduty_findings: List of GuardDuty findings
    """
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        logger.error("SNS topic ARN not configured")
        return
    
    try:
        # Create alert message
        alert_message = {
            'timestamp': datetime.utcnow().isoformat(),
            'alert_type': 'SECURITY_VIOLATION',
            'suspicious_count': len(suspicious_activities),
            'guardduty_count': len(guardduty_findings),
            'details': {
                'suspicious_activities': [
                    {
                        'risk_score': activity.get('risk_score'),
                        'reasons': activity.get('reasons', []),
                        'client_ip': activity.get('client_ip'),
                        'timestamp': activity.get('timestamp')
                    } for activity in suspicious_activities[:3]  # Limit for message size
                ],
                'recent_guardduty_findings': [
                    {
                        'type': finding.get('Type'),
                        'severity': finding.get('Severity'),
                        'title': finding.get('Title')
                    } for finding in guardduty_findings[:3]  # Limit for message size
                ]
            }
        }
        
        # Determine alert severity
        high_risk_count = len([a for a in suspicious_activities if a.get('risk_score', 0) >= 50])
        critical_findings = len([f for f in guardduty_findings if f.get('Severity', 0) >= 7.0])
        
        if high_risk_count > 0 or critical_findings > 0:
            subject = "🚨 CRITICAL Security Alert - Immediate Action Required"
        elif len(suspicious_activities) > 5 or len(guardduty_findings) > 2:
            subject = "⚠️ HIGH Security Alert - Review Required"
        else:
            subject = "ℹ️ Security Alert - Monitoring Notification"
        
        # Send SNS notification
        sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=json.dumps(alert_message, indent=2, default=str)
        )
        
        logger.info(f"Security alert sent successfully to {topic_arn}")
        
    except ClientError as e:
        logger.error(f"Failed to send security alert via SNS: {str(e)}")
    except Exception as e:
        logger.error(f"Error sending security alert: {str(e)}")

def extract_metrics(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract metrics from log entry for monitoring.
    
    Args:
        log_entry: Parsed log entry
        
    Returns:
        Dict containing extracted metrics
    """
    return {
        'response_code': log_entry.get('responseCode', 0),
        'duration': log_entry.get('duration', 0),
        'bytes_sent': log_entry.get('bytesSent', 0),
        'bytes_received': log_entry.get('bytesReceived', 0),
        'method': log_entry.get('requestMethod', 'UNKNOWN'),
        'timestamp': log_entry.get('startTime') or log_entry.get('timestamp'),
        'client_ip': log_entry.get('clientIp'),
        'target_group': log_entry.get('targetGroupArn', '').split('/')[-1] if log_entry.get('targetGroupArn') else None
    }

def calculate_summary_metrics(metrics_data: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Calculate summary metrics from collected data.
    
    Args:
        metrics_data: List of extracted metrics
        
    Returns:
        Dict containing summary metrics
    """
    if not metrics_data:
        return {}
    
    try:
        total_requests = len(metrics_data)
        error_count = sum(1 for m in metrics_data if m.get('response_code', 0) >= 400)
        
        # Calculate average duration (handle missing values)
        durations = [m.get('duration', 0) for m in metrics_data if m.get('duration', 0) > 0]
        avg_duration = sum(durations) / len(durations) if durations else 0
        
        # Calculate total bytes transferred
        total_bytes = sum(
            m.get('bytes_sent', 0) + m.get('bytes_received', 0) 
            for m in metrics_data
        )
        
        # Calculate method distribution
        methods = {}
        for m in metrics_data:
            method = m.get('method', 'UNKNOWN')
            methods[method] = methods.get(method, 0) + 1
        
        # Calculate unique IPs
        unique_ips = len(set(m.get('client_ip') for m in metrics_data if m.get('client_ip')))
        
        return {
            'total_requests': total_requests,
            'error_count': error_count,
            'error_rate_percent': round((error_count / total_requests) * 100, 2) if total_requests > 0 else 0,
            'average_duration_ms': round(avg_duration, 2),
            'total_bytes_transferred': total_bytes,
            'unique_client_ips': unique_ips,
            'method_distribution': methods,
            'calculation_timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error calculating summary metrics: {str(e)}")
        return {'error': str(e)}

def publish_metrics(metrics_data: List[Dict[str, Any]], processing_errors: int) -> None:
    """
    Publish custom metrics to CloudWatch.
    
    Args:
        metrics_data: List of extracted metrics
        processing_errors: Number of processing errors
    """
    if not metrics_data and processing_errors == 0:
        return
    
    try:
        metric_data = []
        
        if metrics_data:
            # Calculate key metrics
            error_count = sum(1 for m in metrics_data if m.get('response_code', 0) >= 400)
            durations = [m.get('duration', 0) for m in metrics_data if m.get('duration', 0) > 0]
            avg_duration = sum(durations) / len(durations) if durations else 0
            
            # Add standard metrics
            metric_data.extend([
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
                }
            ])
            
            if avg_duration > 0:
                metric_data.append({
                    'MetricName': 'AverageResponseTime',
                    'Value': avg_duration,
                    'Unit': 'Milliseconds',
                    'Timestamp': datetime.utcnow()
                })
        
        # Add processing error metric
        if processing_errors > 0:
            metric_data.append({
                'MetricName': 'ProcessingErrors',
                'Value': processing_errors,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            })
        
        # Publish metrics in batches (CloudWatch limit is 20 per call)
        for i in range(0, len(metric_data), 20):
            batch = metric_data[i:i+20]
            cloudwatch.put_metric_data(
                Namespace=METRICS_NAMESPACE,
                MetricData=batch
            )
        
        logger.info(f"Published {len(metric_data)} metrics to CloudWatch")
        
    except ClientError as e:
        logger.error(f"Failed to publish metrics to CloudWatch: {str(e)}")
    except Exception as e:
        logger.error(f"Error publishing metrics: {str(e)}")

def publish_error_metric(error_message: str) -> None:
    """
    Publish error metric to CloudWatch for monitoring.
    
    Args:
        error_message: Error message to include in metric
    """
    try:
        cloudwatch.put_metric_data(
            Namespace=METRICS_NAMESPACE,
            MetricData=[
                {
                    'MetricName': 'LambdaErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow(),
                    'Dimensions': [
                        {
                            'Name': 'ErrorType',
                            'Value': 'ProcessingError'
                        }
                    ]
                }
            ]
        )
        logger.info("Published error metric to CloudWatch")
    except Exception as e:
        logger.error(f"Failed to publish error metric: {str(e)}")