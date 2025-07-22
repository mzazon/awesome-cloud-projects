"""
AWS Cost Optimization Lambda Function

This Lambda function processes Cost Optimization Hub recommendations and budget alerts,
providing automated responses to cost optimization opportunities and budget threshold breaches.
"""

import json
import boto3
import logging
import os
from datetime import datetime, timezone
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
cost_optimization_hub = boto3.client('cost-optimization-hub')
ce_client = boto3.client('ce')
sns_client = boto3.client('sns')

# Environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing cost optimization events and budget alerts.
    
    Args:
        event: AWS Lambda event object
        context: AWS Lambda context object
        
    Returns:
        Dictionary containing status code and response message
    """
    try:
        logger.info(f"Processing cost optimization event in {ENVIRONMENT} environment")
        logger.info(f"Event received: {json.dumps(event, default=str)}")
        
        # Process different types of events
        if 'Records' in event:
            # SNS message from budget alerts or anomaly detection
            return process_sns_records(event['Records'])
        elif 'source' in event and event['source'] == 'aws.budgets':
            # Direct budget alert event
            return process_budget_alert(event)
        elif 'source' in event and event['source'] == 'aws.ce':
            # Cost anomaly detection event
            return process_anomaly_event(event)
        else:
            # Manual trigger or scheduled execution
            return process_manual_trigger(event)
            
    except Exception as e:
        error_message = f"Error processing cost optimization event: {str(e)}"
        logger.error(error_message)
        
        # Send error notification
        if SNS_TOPIC_ARN:
            send_error_notification(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing cost optimization event',
                'error': str(e)
            })
        }


def process_sns_records(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Process SNS records from budget alerts and anomaly detection.
    
    Args:
        records: List of SNS record objects
        
    Returns:
        Dictionary containing processing results
    """
    processed_count = 0
    
    for record in records:
        if record.get('EventSource') == 'aws:sns':
            sns_message = json.loads(record['Sns']['Message'])
            logger.info(f"Processing SNS message: {sns_message}")
            
            # Determine message type and process accordingly
            if 'budgetName' in sns_message:
                process_budget_notification(sns_message)
            elif 'anomalyId' in sns_message:
                process_anomaly_notification(sns_message)
            else:
                logger.info("Unknown SNS message type, processing as general notification")
                
            processed_count += 1
    
    # Get and process cost optimization recommendations
    recommendations_processed = process_cost_optimization_recommendations()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Successfully processed cost optimization events',
            'sns_records_processed': processed_count,
            'recommendations_processed': recommendations_processed
        })
    }


def process_budget_notification(message: Dict[str, Any]) -> None:
    """
    Process budget alert notifications.
    
    Args:
        message: Budget notification message
    """
    budget_name = message.get('budgetName', 'Unknown')
    alert_type = message.get('notificationType', 'Unknown')
    threshold = message.get('threshold', 'Unknown')
    
    logger.info(f"Processing budget alert for: {budget_name}")
    logger.info(f"Alert type: {alert_type}, Threshold: {threshold}%")
    
    # Get current month's spending
    try:
        current_spending = get_current_month_spending()
        
        notification_message = f"""
        🚨 BUDGET ALERT: {budget_name}
        
        Alert Type: {alert_type}
        Threshold: {threshold}%
        Current Month Spending: ${current_spending:.2f}
        
        Recommended Actions:
        1. Review Cost Optimization Hub recommendations
        2. Identify unused or underutilized resources
        3. Consider Reserved Instance opportunities
        4. Implement cost allocation tags for better visibility
        
        Environment: {ENVIRONMENT}
        Timestamp: {datetime.now(timezone.utc).isoformat()}
        """
        
        if SNS_TOPIC_ARN:
            send_notification("Budget Alert - Action Required", notification_message)
            
    except Exception as e:
        logger.error(f"Error processing budget notification: {str(e)}")


def process_anomaly_notification(message: Dict[str, Any]) -> None:
    """
    Process cost anomaly detection notifications.
    
    Args:
        message: Anomaly notification message
    """
    anomaly_id = message.get('anomalyId', 'Unknown')
    service = message.get('service', 'Unknown')
    impact = message.get('impact', {})
    
    logger.info(f"Processing cost anomaly: {anomaly_id} for service: {service}")
    
    notification_message = f"""
    ⚠️ COST ANOMALY DETECTED
    
    Anomaly ID: {anomaly_id}
    Affected Service: {service}
    Cost Impact: ${impact.get('totalImpact', 'Unknown')}
    
    Recommended Actions:
    1. Investigate unusual usage patterns
    2. Check for unexpected resource provisioning
    3. Review recent configuration changes
    4. Consider implementing automated cost controls
    
    Environment: {ENVIRONMENT}
    Timestamp: {datetime.now(timezone.utc).isoformat()}
    """
    
    if SNS_TOPIC_ARN:
        send_notification("Cost Anomaly Detected", notification_message)


def process_budget_alert(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process direct budget alert events.
    
    Args:
        event: Budget alert event
        
    Returns:
        Dictionary containing processing results
    """
    logger.info("Processing direct budget alert event")
    
    # Process cost optimization recommendations
    recommendations_processed = process_cost_optimization_recommendations()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Successfully processed budget alert',
            'recommendations_processed': recommendations_processed
        })
    }


def process_anomaly_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process cost anomaly detection events.
    
    Args:
        event: Anomaly detection event
        
    Returns:
        Dictionary containing processing results
    """
    logger.info("Processing cost anomaly detection event")
    
    # Get recent anomalies
    try:
        anomalies = get_recent_anomalies()
        logger.info(f"Found {len(anomalies)} recent anomalies")
        
        for anomaly in anomalies[:5]:  # Process up to 5 most recent anomalies
            logger.info(f"Anomaly: {anomaly.get('AnomalyId')} - Impact: ${anomaly.get('Impact', {}).get('TotalImpact', 0)}")
    
    except Exception as e:
        logger.error(f"Error retrieving anomalies: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Successfully processed anomaly event',
            'anomalies_found': len(anomalies) if 'anomalies' in locals() else 0
        })
    }


def process_manual_trigger(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process manual trigger or scheduled execution.
    
    Args:
        event: Manual trigger event
        
    Returns:
        Dictionary containing processing results
    """
    logger.info("Processing manual trigger or scheduled execution")
    
    # Process cost optimization recommendations
    recommendations_processed = process_cost_optimization_recommendations()
    
    # Generate summary report
    summary = generate_cost_optimization_summary()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Successfully completed cost optimization processing',
            'recommendations_processed': recommendations_processed,
            'summary': summary
        })
    }


def process_cost_optimization_recommendations() -> int:
    """
    Retrieve and process Cost Optimization Hub recommendations.
    
    Returns:
        Number of recommendations processed
    """
    try:
        logger.info("Retrieving Cost Optimization Hub recommendations")
        
        response = cost_optimization_hub.list_recommendations(
            includeAllRecommendations=True,
            maxResults=50
        )
        
        recommendations = response.get('items', [])
        logger.info(f"Found {len(recommendations)} cost optimization recommendations")
        
        high_impact_recommendations = []
        
        for rec in recommendations:
            recommendation_id = rec.get('recommendationId', 'Unknown')
            action_type = rec.get('actionType', 'Unknown')
            estimated_savings = rec.get('estimatedMonthlySavings', 0)
            
            logger.info(f"Recommendation: {recommendation_id}")
            logger.info(f"Action Type: {action_type}")
            logger.info(f"Estimated Monthly Savings: ${estimated_savings}")
            
            # Track high-impact recommendations (>$50/month savings)
            if float(estimated_savings) > 50:
                high_impact_recommendations.append({
                    'id': recommendation_id,
                    'action': action_type,
                    'savings': estimated_savings
                })
        
        # Send notification for high-impact recommendations
        if high_impact_recommendations and SNS_TOPIC_ARN:
            send_high_impact_recommendations_notification(high_impact_recommendations)
        
        return len(recommendations)
        
    except Exception as e:
        logger.error(f"Error processing Cost Optimization Hub recommendations: {str(e)}")
        return 0


def get_current_month_spending() -> float:
    """
    Get current month's spending using Cost Explorer API.
    
    Returns:
        Current month spending amount
    """
    try:
        # Calculate start and end dates for current month
        now = datetime.now(timezone.utc)
        start_date = now.replace(day=1).strftime('%Y-%m-%d')
        end_date = now.strftime('%Y-%m-%d')
        
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost']
        )
        
        results = response.get('ResultsByTime', [])
        if results:
            amount = results[0].get('Total', {}).get('BlendedCost', {}).get('Amount', '0')
            return float(amount)
        
        return 0.0
        
    except Exception as e:
        logger.error(f"Error retrieving current month spending: {str(e)}")
        return 0.0


def get_recent_anomalies() -> List[Dict[str, Any]]:
    """
    Get recent cost anomalies from Cost Explorer.
    
    Returns:
        List of recent anomalies
    """
    try:
        # Get anomalies from the last 7 days
        end_date = datetime.now(timezone.utc)
        start_date = end_date.replace(day=end_date.day - 7)
        
        response = ce_client.get_anomalies(
            DateInterval={
                'StartDate': start_date.strftime('%Y-%m-%d'),
                'EndDate': end_date.strftime('%Y-%m-%d')
            },
            MaxResults=10
        )
        
        return response.get('Anomalies', [])
        
    except Exception as e:
        logger.error(f"Error retrieving recent anomalies: {str(e)}")
        return []


def generate_cost_optimization_summary() -> Dict[str, Any]:
    """
    Generate a summary of cost optimization status.
    
    Returns:
        Dictionary containing summary information
    """
    try:
        current_spending = get_current_month_spending()
        recent_anomalies = get_recent_anomalies()
        
        return {
            'current_month_spending': current_spending,
            'recent_anomalies_count': len(recent_anomalies),
            'last_processed': datetime.now(timezone.utc).isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error generating summary: {str(e)}")
        return {}


def send_notification(subject: str, message: str) -> None:
    """
    Send notification via SNS.
    
    Args:
        subject: Notification subject
        message: Notification message
    """
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        logger.info(f"Sent notification: {subject}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")


def send_high_impact_recommendations_notification(recommendations: List[Dict[str, Any]]) -> None:
    """
    Send notification for high-impact cost optimization recommendations.
    
    Args:
        recommendations: List of high-impact recommendations
    """
    message = f"""
    💰 HIGH-IMPACT COST OPTIMIZATION OPPORTUNITIES FOUND
    
    We've identified {len(recommendations)} high-impact cost optimization recommendations:
    
    """
    
    total_potential_savings = 0
    for i, rec in enumerate(recommendations[:5], 1):  # Show top 5
        savings = float(rec['savings'])
        total_potential_savings += savings
        message += f"{i}. {rec['action']}\n"
        message += f"   Potential Monthly Savings: ${savings:.2f}\n\n"
    
    message += f"""
    Total Potential Monthly Savings: ${total_potential_savings:.2f}
    Annual Savings Potential: ${total_potential_savings * 12:.2f}
    
    Next Steps:
    1. Review recommendations in the Cost Optimization Hub console
    2. Prioritize implementations based on business impact
    3. Monitor savings after implementation
    
    Environment: {ENVIRONMENT}
    Timestamp: {datetime.now(timezone.utc).isoformat()}
    """
    
    send_notification("High-Impact Cost Optimization Opportunities", message)


def send_error_notification(error_message: str) -> None:
    """
    Send error notification via SNS.
    
    Args:
        error_message: Error message to send
    """
    try:
        if SNS_TOPIC_ARN:
            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject="Cost Optimization Lambda Function Error",
                Message=f"""
                ❌ ERROR in Cost Optimization Lambda Function
                
                Environment: {ENVIRONMENT}
                Error: {error_message}
                Timestamp: {datetime.now(timezone.utc).isoformat()}
                
                Please check CloudWatch logs for more details.
                """
            )
            
    except Exception as e:
        logger.error(f"Error sending error notification: {str(e)}")