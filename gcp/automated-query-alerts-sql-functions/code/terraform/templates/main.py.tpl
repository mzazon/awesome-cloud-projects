import json
import logging
from datetime import datetime, timezone
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging
import functions_framework
import os

# Configure logging
cloud_logging.Client().setup_logging()

@functions_framework.http
def process_query_alert(request):
    """Process Cloud Monitoring alert for slow queries"""
    try:
        # Parse alert payload
        alert_data = request.get_json()
        if not alert_data:
            return "No alert data received", 400
        
        # Extract alert details
        incident = alert_data.get('incident', {})
        condition_name = incident.get('condition_name', 'Unknown')
        policy_name = incident.get('policy_name', 'Unknown')
        state = incident.get('state', 'UNKNOWN')
        
        # Log alert processing
        logging.info(f"Processing alert: {condition_name}, State: {state}")
        
        # Create enriched alert message
        alert_message = create_enriched_alert(incident, alert_data)
        
        # Send notifications
        send_alert_notification(alert_message, state)
        
        return f"Alert processed successfully: {condition_name}", 200
        
    except Exception as e:
        logging.error(f"Error processing alert: {str(e)}")
        return f"Error processing alert: {str(e)}", 500

def create_enriched_alert(incident, alert_data):
    """Create enriched alert message with query insights"""
    timestamp = datetime.now(timezone.utc).isoformat()
    project_id = os.environ.get('PROJECT_ID', '${project_id}')
    sql_instance = os.environ.get('SQL_INSTANCE', 'unknown')
    threshold = os.environ.get('ALERT_THRESHOLD', '5.0')
    
    message = {
        "timestamp": timestamp,
        "alert_type": "Database Query Performance",
        "severity": determine_severity(incident),
        "condition": incident.get('condition_name', 'Unknown'),
        "state": incident.get('state', 'UNKNOWN'),
        "summary": incident.get('summary', f'Query performance threshold ({threshold}s) exceeded'),
        "recommendations": generate_recommendations(incident),
        "resource_name": incident.get('resource_name', sql_instance),
        "project_id": project_id,
        "sql_instance": sql_instance,
        "threshold_seconds": threshold,
        "query_insights_url": f"https://console.cloud.google.com/sql/instances/{sql_instance}/insights?project={project_id}",
        "monitoring_url": f"https://console.cloud.google.com/monitoring/alerting/policies?project={project_id}",
        "documentation": "https://cloud.google.com/sql/docs/postgres/using-query-insights"
    }
    
    return message

def determine_severity(incident):
    """Determine alert severity based on incident data"""
    condition_name = incident.get('condition_name', '').lower()
    summary = incident.get('summary', '').lower()
    
    # Check for critical indicators
    if any(keyword in condition_name or keyword in summary for keyword in ['critical', 'error', 'failure']):
        return 'CRITICAL'
    elif any(keyword in condition_name or keyword in summary for keyword in ['warning', 'high']):
        return 'WARNING'
    else:
        return 'INFO'

def generate_recommendations(incident):
    """Generate actionable recommendations for query performance"""
    base_recommendations = [
        "Review Query Insights dashboard for slow query patterns and execution plans",
        "Check for missing indexes on frequently queried columns using EXPLAIN ANALYZE", 
        "Analyze query execution plans for optimization opportunities",
        "Consider connection pooling if high connection counts detected",
        "Monitor for lock contention and blocking queries in pg_stat_activity",
        "Review database statistics and consider running ANALYZE on frequently queried tables",
        "Check for full table scans and optimize with appropriate WHERE clauses",
        "Consider partitioning large tables if range queries are common"
    ]
    
    # Add context-specific recommendations based on incident data
    condition_name = incident.get('condition_name', '').lower()
    
    if 'execution_time' in condition_name:
        base_recommendations.insert(0, "Focus on query execution time optimization - check for complex JOINs and subqueries")
    
    return base_recommendations[:6]  # Return top 6 recommendations

def send_alert_notification(message, state):
    """Send alert notification via multiple channels"""
    try:
        # Log structured alert message for Cloud Logging
        alert_log_entry = {
            "severity": message["severity"],
            "alert_type": message["alert_type"],
            "timestamp": message["timestamp"],
            "state": state,
            "condition": message["condition"],
            "resource": message["resource_name"],
            "recommendations_count": len(message["recommendations"]),
            "query_insights_url": message["query_insights_url"]
        }
        
        logging.info(f"QUERY_PERFORMANCE_ALERT: {json.dumps(alert_log_entry)}")
        
        # Send different notifications based on alert state
        if state == 'OPEN':
            logging.warning(f"🚨 ALERT OPENED - {message['severity']}: {message['summary']}")
            logging.info(f"📊 Query Insights Dashboard: {message['query_insights_url']}")
            logging.info(f"🔧 Recommendations: {', '.join(message['recommendations'][:3])}")
            
        elif state == 'CLOSED':
            logging.info(f"✅ ALERT RESOLVED: {message['summary']}")
            logging.info(f"Duration: Alert was active and has now been resolved")
            
        else:
            logging.info(f"ℹ️ ALERT STATUS CHANGE - {state}: {message['summary']}")
        
        # In production environments, implement additional notification channels:
        # send_email_notification(message, state)
        # send_slack_notification(message, state) 
        # send_pagerduty_alert(message, state)
        # send_sms_notification(message, state)
        
    except Exception as e:
        logging.error(f"Error sending notification: {str(e)}")
        raise

def send_email_notification(message, state):
    """Send email notification (placeholder for production implementation)"""
    # Implementation would use SendGrid, Gmail API, or similar service
    logging.info("Email notification would be sent here in production")
    pass

def send_slack_notification(message, state):
    """Send Slack notification (placeholder for production implementation)"""
    # Implementation would use Slack webhook or Bot API
    logging.info("Slack notification would be sent here in production")
    pass

def send_pagerduty_alert(message, state):
    """Send PagerDuty alert (placeholder for production implementation)"""
    # Implementation would use PagerDuty Events API v2
    logging.info("PagerDuty alert would be sent here in production")
    pass

def send_sms_notification(message, state):
    """Send SMS notification (placeholder for production implementation)"""
    # Implementation would use Twilio or similar SMS service
    logging.info("SMS notification would be sent here in production")
    pass