"""
Cloud Function for processing Workload Manager assessment results.

This function processes infrastructure health assessment reports from Cloud Workload Manager,
analyzes the results for critical issues and recommendations, and triggers appropriate
remediation workflows through Cloud Deploy pipelines.
"""

import json
import logging
import os
from typing import Dict, List, Any
from google.cloud import pubsub_v1
from google.cloud import storage
from google.cloud import monitoring_v3
import functions_framework
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Google Cloud clients
publisher = pubsub_v1.PublisherClient()
storage_client = storage.Client()
monitoring_client = monitoring_v3.MetricServiceClient()

# Environment configuration
PROJECT_ID = os.environ.get('PROJECT_ID')
HEALTH_EVENTS_TOPIC = os.environ.get('HEALTH_EVENTS_TOPIC')
MONITORING_ALERTS_TOPIC = os.environ.get('MONITORING_ALERTS_TOPIC')
CRITICAL_THRESHOLD = int(os.environ.get('CRITICAL_THRESHOLD', '1'))

def analyze_assessment_results(assessment_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze Workload Manager assessment results and categorize findings.
    
    Args:
        assessment_data: Raw assessment data from Workload Manager
        
    Returns:
        Dictionary containing analysis results with categorized issues
    """
    try:
        results = assessment_data.get('results', [])
        findings = assessment_data.get('findings', [])
        
        # Initialize counters and lists
        analysis = {
            'critical_issues': [],
            'high_issues': [],
            'medium_issues': [],
            'low_issues': [],
            'recommendations': [],
            'security_findings': [],
            'performance_findings': [],
            'cost_findings': [],
            'total_issues': 0,
            'severity_breakdown': {
                'CRITICAL': 0,
                'HIGH': 0,
                'MEDIUM': 0,
                'LOW': 0,
                'INFO': 0
            }
        }
        
        # Process results from assessment
        for result in results:
            severity = result.get('severity', 'UNKNOWN').upper()
            issue_type = result.get('type', 'general')
            
            # Update severity counters
            if severity in analysis['severity_breakdown']:
                analysis['severity_breakdown'][severity] += 1
            
            # Categorize by severity
            if severity == 'CRITICAL':
                analysis['critical_issues'].append(result)
            elif severity == 'HIGH':
                analysis['high_issues'].append(result)
            elif severity == 'MEDIUM':
                analysis['medium_issues'].append(result)
            elif severity == 'LOW':
                analysis['low_issues'].append(result)
            
            # Categorize by type
            if 'security' in issue_type.lower():
                analysis['security_findings'].append(result)
            elif 'performance' in issue_type.lower():
                analysis['performance_findings'].append(result)
            elif 'cost' in issue_type.lower():
                analysis['cost_findings'].append(result)
            
            # Check for recommendations
            if result.get('hasRecommendation', False):
                analysis['recommendations'].append(result)
        
        # Process findings (alternative format)
        for finding in findings:
            severity = finding.get('severity', 'UNKNOWN').upper()
            category = finding.get('category', 'general')
            
            if severity in analysis['severity_breakdown']:
                analysis['severity_breakdown'][severity] += 1
            
            if finding.get('remediation'):
                analysis['recommendations'].append(finding)
        
        # Calculate totals
        analysis['total_issues'] = sum(analysis['severity_breakdown'].values())
        
        logger.info(f"Assessment analysis completed: {analysis['total_issues']} total issues found")
        logger.info(f"Critical: {analysis['severity_breakdown']['CRITICAL']}, "
                   f"High: {analysis['severity_breakdown']['HIGH']}, "
                   f"Medium: {analysis['severity_breakdown']['MEDIUM']}")
        
        return analysis
        
    except Exception as e:
        logger.error(f"Error analyzing assessment results: {str(e)}")
        raise

def determine_remediation_actions(analysis: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Determine appropriate remediation actions based on assessment analysis.
    
    Args:
        analysis: Analysis results from analyze_assessment_results
        
    Returns:
        List of remediation actions to be triggered
    """
    actions = []
    
    try:
        # Critical and high severity issues require immediate action
        if analysis['severity_breakdown']['CRITICAL'] > 0:
            actions.append({
                'priority': 'CRITICAL',
                'action_type': 'immediate_remediation',
                'template': 'security-fixes.yaml',
                'approval_required': False,
                'issues_count': analysis['severity_breakdown']['CRITICAL']
            })
        
        if analysis['severity_breakdown']['HIGH'] >= CRITICAL_THRESHOLD:
            actions.append({
                'priority': 'HIGH',
                'action_type': 'scheduled_remediation',
                'template': 'performance-fixes.yaml',
                'approval_required': True,
                'issues_count': analysis['severity_breakdown']['HIGH']
            })
        
        # Security-specific actions
        if analysis['security_findings']:
            actions.append({
                'priority': 'HIGH',
                'action_type': 'security_remediation',
                'template': 'security-fixes.yaml',
                'approval_required': False,
                'issues_count': len(analysis['security_findings'])
            })
        
        # Performance optimization actions
        if analysis['performance_findings']:
            actions.append({
                'priority': 'MEDIUM',
                'action_type': 'performance_optimization',
                'template': 'performance-fixes.yaml',
                'approval_required': True,
                'issues_count': len(analysis['performance_findings'])
            })
        
        # Cost optimization actions
        if analysis['cost_findings']:
            actions.append({
                'priority': 'LOW',
                'action_type': 'cost_optimization',
                'template': 'cost-optimization.yaml',
                'approval_required': True,
                'issues_count': len(analysis['cost_findings'])
            })
        
        logger.info(f"Determined {len(actions)} remediation actions")
        return actions
        
    except Exception as e:
        logger.error(f"Error determining remediation actions: {str(e)}")
        raise

def publish_to_pubsub(topic_name: str, message_data: Dict[str, Any]) -> None:
    """
    Publish message to specified Pub/Sub topic.
    
    Args:
        topic_name: Name of the Pub/Sub topic
        message_data: Dictionary containing message data
    """
    try:
        topic_path = publisher.topic_path(PROJECT_ID, topic_name)
        message_json = json.dumps(message_data, default=str)
        message_bytes = message_json.encode('utf-8')
        
        # Add message attributes
        attributes = {
            'source': 'infrastructure-health-assessment',
            'timestamp': datetime.utcnow().isoformat(),
            'severity': message_data.get('severity', 'INFO')
        }
        
        future = publisher.publish(topic_path, message_bytes, **attributes)
        message_id = future.result()
        
        logger.info(f"Published message {message_id} to topic {topic_name}")
        
    except Exception as e:
        logger.error(f"Error publishing to Pub/Sub topic {topic_name}: {str(e)}")
        raise

def create_custom_metric(metric_name: str, value: int, labels: Dict[str, str] = None) -> None:
    """
    Create custom metric for monitoring dashboard.
    
    Args:
        metric_name: Name of the custom metric
        value: Metric value to record
        labels: Optional labels for the metric
    """
    try:
        project_name = f"projects/{PROJECT_ID}"
        series = monitoring_v3.TimeSeries()
        series.metric.type = f"custom.googleapis.com/{metric_name}"
        
        # Add labels if provided
        if labels:
            for key, val in labels.items():
                series.metric.labels[key] = val
        
        series.resource.type = "global"
        series.resource.labels["project_id"] = PROJECT_ID
        
        # Create data point
        now = datetime.utcnow()
        seconds = int(now.timestamp())
        nanos = int((now.timestamp() - seconds) * 10**9)
        interval = monitoring_v3.TimeInterval(
            {"end_time": {"seconds": seconds, "nanos": nanos}}
        )
        point = monitoring_v3.Point({
            "interval": interval,
            "value": {"int64_value": value}
        })
        series.points = [point]
        
        # Write time series data
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logger.info(f"Created custom metric {metric_name} with value {value}")
        
    except Exception as e:
        logger.error(f"Error creating custom metric {metric_name}: {str(e)}")
        # Don't raise here as this is not critical to the main workflow

@functions_framework.cloud_event
def process_health_assessment(cloud_event):
    """
    Main Cloud Function entry point for processing health assessment results.
    
    This function is triggered when new assessment reports are uploaded to Cloud Storage.
    It downloads and analyzes the reports, determines appropriate remediation actions,
    and triggers deployment workflows through Pub/Sub messaging.
    
    Args:
        cloud_event: CloudEvent containing Storage trigger data
    """
    try:
        # Extract event data
        data = cloud_event.data
        bucket_name = data.get('bucket')
        object_name = data.get('name')
        event_type = data.get('eventType')
        
        logger.info(f"Processing assessment report: {object_name} from bucket: {bucket_name}")
        logger.info(f"Event type: {event_type}")
        
        # Validate input data
        if not bucket_name or not object_name:
            logger.error("Missing bucket or object information in event data")
            return
        
        # Skip processing for non-assessment files
        if not (object_name.endswith('.json') or 'assessment' in object_name.lower()):
            logger.info(f"Skipping non-assessment file: {object_name}")
            return
        
        # Download assessment report from Cloud Storage
        try:
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            
            if not blob.exists():
                logger.error(f"Assessment report {object_name} does not exist in bucket {bucket_name}")
                return
            
            assessment_content = blob.download_as_text()
            assessment_data = json.loads(assessment_content)
            
            logger.info(f"Successfully downloaded and parsed assessment report: {object_name}")
            
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in assessment report {object_name}: {str(e)}")
            return
        except Exception as e:
            logger.error(f"Error downloading assessment report {object_name}: {str(e)}")
            return
        
        # Analyze assessment results
        analysis = analyze_assessment_results(assessment_data)
        
        # Determine remediation actions
        remediation_actions = determine_remediation_actions(analysis)
        
        # Create monitoring metrics
        create_custom_metric(
            "infrastructure_health_total_issues",
            analysis['total_issues'],
            {"assessment_id": assessment_data.get('id', 'unknown')}
        )
        
        create_custom_metric(
            "infrastructure_health_critical_issues",
            analysis['severity_breakdown']['CRITICAL'],
            {"assessment_id": assessment_data.get('id', 'unknown')}
        )
        
        # Prepare event message for deployment pipeline
        event_message = {
            'assessment_id': assessment_data.get('id', 'unknown'),
            'timestamp': datetime.utcnow().isoformat(),
            'bucket_name': bucket_name,
            'object_name': object_name,
            'analysis': {
                'total_issues': analysis['total_issues'],
                'critical_issues': analysis['severity_breakdown']['CRITICAL'],
                'high_issues': analysis['severity_breakdown']['HIGH'],
                'recommendations_count': len(analysis['recommendations']),
                'security_findings_count': len(analysis['security_findings']),
                'performance_findings_count': len(analysis['performance_findings']),
                'cost_findings_count': len(analysis['cost_findings'])
            },
            'remediation_actions': remediation_actions,
            'trigger_deployment': len(remediation_actions) > 0
        }
        
        # Publish to health assessment events topic
        if HEALTH_EVENTS_TOPIC:
            publish_to_pubsub(HEALTH_EVENTS_TOPIC, event_message)
        
        # Publish critical alerts if threshold exceeded
        if analysis['severity_breakdown']['CRITICAL'] >= CRITICAL_THRESHOLD:
            alert_message = {
                'alert_type': 'CRITICAL_INFRASTRUCTURE_ISSUES',
                'assessment_id': assessment_data.get('id', 'unknown'),
                'critical_issues_count': analysis['severity_breakdown']['CRITICAL'],
                'timestamp': datetime.utcnow().isoformat(),
                'requires_immediate_attention': True,
                'remediation_actions': [action for action in remediation_actions if action['priority'] == 'CRITICAL']
            }
            
            if MONITORING_ALERTS_TOPIC:
                publish_to_pubsub(MONITORING_ALERTS_TOPIC, alert_message)
        
        # Log summary
        logger.info(f"Assessment processing completed successfully:")
        logger.info(f"  - Total issues: {analysis['total_issues']}")
        logger.info(f"  - Critical issues: {analysis['severity_breakdown']['CRITICAL']}")
        logger.info(f"  - Remediation actions: {len(remediation_actions)}")
        logger.info(f"  - Deployment triggered: {len(remediation_actions) > 0}")
        
        # Mark processing as successful
        create_custom_metric(
            "infrastructure_health_processing_success",
            1,
            {"assessment_id": assessment_data.get('id', 'unknown')}
        )
        
    except Exception as e:
        logger.error(f"Error processing health assessment: {str(e)}")
        
        # Create failure metric
        create_custom_metric(
            "infrastructure_health_processing_failures",
            1,
            {"error_type": type(e).__name__}
        )
        
        # Publish failure alert
        if MONITORING_ALERTS_TOPIC:
            failure_message = {
                'alert_type': 'ASSESSMENT_PROCESSING_FAILURE',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat(),
                'requires_investigation': True
            }
            try:
                publish_to_pubsub(MONITORING_ALERTS_TOPIC, failure_message)
            except Exception as pub_error:
                logger.error(f"Failed to publish failure alert: {str(pub_error)}")
        
        raise