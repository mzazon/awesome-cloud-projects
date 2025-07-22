import json
import logging
from google.cloud import monitoring_v3
from google.cloud import pubsub_v1
from google.cloud import bigquery
from datetime import datetime
import os
import requests
import base64

def optimize_resources(event, context):
    """Automate resource optimization based on recommendations"""
    
    # Configure logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Initialize clients
    monitoring_client = monitoring_v3.MetricServiceClient()
    publisher = pubsub_v1.PublisherClient()
    bq_client = bigquery.Client()
    
    # Configuration from template variables
    project_id = "${project_id}"
    cost_threshold = float("${cost_threshold}")
    slack_webhook_url = "${slack_webhook_url}"
    alert_topic = f"projects/{project_id}/topics/optimization-alerts"
    
    try:
        # Parse incoming Pub/Sub message
        if 'data' in event:
            message_data = json.loads(base64.b64decode(event['data']).decode('utf-8'))
        else:
            message_data = {"trigger": "direct_call"}
        
        logger.info(f"Processing optimization for: {message_data}")
        
        target_project = message_data.get('project_id', 'unknown')
        potential_savings = float(message_data.get('potential_savings', 0))
        recommendations_count = int(message_data.get('recommendations_count', 0))
        
        actions_taken = []
        alerts_created = []
        
        # Check for high-value optimization opportunities
        if potential_savings > cost_threshold:
            logger.info(f"High-value optimization detected: ${potential_savings:.2f} for project {target_project}")
            
            # Create alert data
            alert_data = {
                'project_id': target_project,
                'savings_potential': potential_savings,
                'recommendations_count': recommendations_count,
                'timestamp': datetime.now().isoformat(),
                'alert_type': 'high_value_optimization',
                'threshold_exceeded': cost_threshold,
                'urgency': 'high' if potential_savings > cost_threshold * 2 else 'medium'
            }
            
            # Send Slack notification if webhook configured
            if slack_webhook_url and slack_webhook_url != "":
                try:
                    # Determine alert color based on savings amount
                    if potential_savings > cost_threshold * 3:
                        color = "danger"  # Red for very high savings
                    elif potential_savings > cost_threshold * 2:
                        color = "warning"  # Yellow for high savings
                    else:
                        color = "good"  # Green for moderate savings
                    
                    slack_message = {
                        'text': f"🚨 High-Value Cost Optimization Alert",
                        'username': 'Cost Optimization Bot',
                        'icon_emoji': ':money_with_wings:',
                        'attachments': [
                            {
                                'color': color,
                                'title': f'Cost Optimization Opportunity - {target_project}',
                                'fields': [
                                    {
                                        'title': 'Project',
                                        'value': target_project,
                                        'short': True
                                    },
                                    {
                                        'title': 'Potential Savings',
                                        'value': f"${potential_savings:.2f}",
                                        'short': True
                                    },
                                    {
                                        'title': 'Recommendations',
                                        'value': str(recommendations_count),
                                        'short': True
                                    },
                                    {
                                        'title': 'Priority',
                                        'value': alert_data['urgency'].upper(),
                                        'short': True
                                    }
                                ],
                                'footer': 'Google Cloud Cost Optimization',
                                'ts': int(datetime.now().timestamp())
                            }
                        ]
                    }
                    
                    response = requests.post(
                        slack_webhook_url, 
                        json=slack_message,
                        timeout=10
                    )
                    
                    if response.status_code == 200:
                        logger.info("Slack notification sent successfully")
                        actions_taken.append("slack_notification_sent")
                    else:
                        logger.error(f"Slack notification failed: {response.status_code} - {response.text}")
                        
                except Exception as slack_error:
                    logger.error(f"Slack notification error: {str(slack_error)}")
                    
            # Publish alert to monitoring topic
            try:
                alert_message = json.dumps(alert_data)
                future = publisher.publish(alert_topic, alert_message.encode('utf-8'))
                logger.info(f"Alert published to topic: {alert_topic}")
                actions_taken.append("monitoring_alert_published")
                alerts_created.append(alert_data)
                
            except Exception as pubsub_error:
                logger.error(f"Failed to publish alert: {str(pubsub_error)}")
            
            # Log high-value opportunity for audit trail
            logger.info(f"HIGH VALUE OPPORTUNITY: Project {target_project} - ${potential_savings:.2f} potential savings")
            
        # Check for automated optimization opportunities (low-risk actions)
        automated_actions = []
        
        # Example: Identify very safe optimizations that could be automated
        if recommendations_count > 0:
            # In a real implementation, you would analyze specific recommendation types
            # and automatically implement safe optimizations like:
            # - Deleting old snapshots
            # - Stopping idle instances outside business hours
            # - Cleaning up unattached disks
            
            # For this example, we'll log potential automated actions
            if potential_savings > 10:  # Only for meaningful savings
                automated_actions.extend([
                    "identified_idle_resources",
                    "scheduled_cleanup_review"
                ])
                
                logger.info(f"Identified {recommendations_count} optimization opportunities for project {target_project}")
        
        # Create optimization log entry
        optimization_log = {
            'project_id': target_project,
            'action': 'optimization_analysis_complete',
            'savings_potential': potential_savings,
            'recommendations_count': recommendations_count,
            'actions_taken': actions_taken,
            'automated_actions': automated_actions,
            'alerts_created': len(alerts_created),
            'threshold_exceeded': potential_savings > cost_threshold,
            'timestamp': datetime.now().isoformat(),
            'cost_threshold': cost_threshold
        }
        
        # Store optimization log for reporting and auditing
        # (In production, you might want to store this in BigQuery or Cloud Logging)
        logger.info(f"Optimization log: {optimization_log}")
        
        # Summary response
        response = {
            "status": "success",
            "message": "Optimization automation completed",
            "project_id": target_project,
            "potential_savings": potential_savings,
            "recommendations_count": recommendations_count,
            "actions_taken": actions_taken,
            "automated_actions": automated_actions,
            "alerts_created": len(alerts_created),
            "high_value_opportunity": potential_savings > cost_threshold
        }
        
        logger.info(f"Optimization automation complete: {response}")
        return response
        
    except Exception as e:
        error_msg = f"Optimization automation failed: {str(e)}"
        logger.error(error_msg)
        return {"status": "error", "message": error_msg}

# Entry point for Cloud Functions
def main(event, context):
    return optimize_resources(event, context)