import base64
import json
import logging
import os
from google.cloud import monitoring_v3
from google.cloud import securitycenter
from google.cloud import pubsub_v1
from datetime import datetime

def main(event, context):
    """Security triage function for automated threat analysis."""
    
    # Decode Pub/Sub message
    message_data = base64.b64decode(event['data']).decode('utf-8')
    security_finding = json.loads(message_data)
    
    # Extract key finding information
    finding_name = security_finding.get('name', 'Unknown')
    severity = security_finding.get('severity', 'MEDIUM')
    category = security_finding.get('category', 'Unknown')
    source_properties = security_finding.get('sourceProperties', {})
    
    logging.info(f"Processing security finding: {finding_name}")
    logging.info(f"Severity: {severity}, Category: {category}")
    
    # Triage logic based on severity and category
    if severity in ['HIGH', 'CRITICAL']:
        # Route to immediate remediation
        route_to_remediation(security_finding)
    elif category in ['MALWARE', 'PRIVILEGE_ESCALATION', 'DATA_EXFILTRATION']:
        # Route high-priority categories regardless of severity
        route_to_remediation(security_finding)
    else:
        # Route to notification for human review
        route_to_notification(security_finding)
    
    # Create monitoring metric
    create_security_metric(finding_name, severity, category)
    
    return f"Processed security finding: {finding_name}"

def route_to_remediation(finding):
    """Route high-priority findings to remediation function."""
    project_id = "${project_id}"
    topic_name = os.environ.get('REMEDIATION_TOPIC', 'threat-remediation-topic')
    
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name.split('/')[-1])
    
    message_data = json.dumps(finding).encode('utf-8')
    publisher.publish(topic_path, message_data)
    logging.info("Routed to remediation function")

def route_to_notification(finding):
    """Route lower-priority findings to notification function."""
    project_id = "${project_id}"
    topic_name = os.environ.get('NOTIFICATION_TOPIC', 'threat-notification-topic')
    
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name.split('/')[-1])
    
    message_data = json.dumps(finding).encode('utf-8')
    publisher.publish(topic_path, message_data)
    logging.info("Routed to notification function")

def create_security_metric(finding_name, severity, category):
    """Create custom monitoring metrics for security findings."""
    project_id = "${project_id}"
    deployment_id = os.environ.get('DEPLOYMENT_ID', 'default')
    
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{project_id}"
        
        # Create metric point
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/security/findings_processed"
        series.resource.type = "global"
        series.metric.labels["severity"] = severity
        series.metric.labels["category"] = category
        series.metric.labels["deployment_id"] = deployment_id
        
        # Create data point
        now = datetime.utcnow()
        seconds = int(now.timestamp())
        nanos = int((now.timestamp() - seconds) * 10**9)
        interval = monitoring_v3.TimeInterval(
            {"end_time": {"seconds": seconds, "nanos": nanos}}
        )
        point = monitoring_v3.Point({
            "interval": interval,
            "value": {"int64_value": 1},
        })
        series.points = [point]
        
        client.create_time_series(name=project_name, time_series=[series])
        logging.info(f"Created monitoring metric for finding: {finding_name}")
    except Exception as e:
        logging.error(f"Failed to create monitoring metric: {str(e)}")