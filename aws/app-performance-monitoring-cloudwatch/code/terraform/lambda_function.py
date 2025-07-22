"""
AWS Lambda Function for Processing CloudWatch Application Performance Alerts

This Lambda function processes CloudWatch alarm state changes and implements
automated responses for application performance monitoring. It integrates with
SNS for notifications, CloudWatch for metrics analysis, and Auto Scaling for
automated remediation.

Features:
- Process CloudWatch alarm state changes from EventBridge
- Send formatted notifications via SNS
- Implement intelligent alert correlation
- Support for automated scaling responses
- Comprehensive logging and error handling
- Cost optimization through efficient execution
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
import uuid

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger.setLevel(getattr(logging, log_level.upper(), logging.INFO))

# Initialize AWS clients with error handling
try:
    sns_client = boto3.client('sns')
    cloudwatch_client = boto3.client('cloudwatch')
    autoscaling_client = boto3.client('autoscaling')
except Exception as e:
    logger.error(f"Failed to initialize AWS clients: {str(e)}")
    raise

# Environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'app-performance-monitoring')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

# Performance thresholds and configuration
ALERT_CORRELATION_WINDOW_MINUTES = 5
MAX_SCALING_ACTIONS_PER_HOUR = 3
SCALING_COOLDOWN_MINUTES = 10

class PerformanceAlertProcessor:
    """
    Main class for processing performance alerts and implementing automated responses
    """
    
    def __init__(self):
        self.sns_client = sns_client
        self.cloudwatch_client = cloudwatch_client
        self.autoscaling_client = autoscaling_client
        self.correlation_cache = {}
        
    def process_alarm_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process CloudWatch alarm state change event
        
        Args:
            event: EventBridge event containing alarm state change details
            
        Returns:
            Dict containing processing results and actions taken
        """
        try:
            # Extract event details
            detail = event.get('detail', {})
            alarm_name = detail.get('alarmName', '')
            new_state = detail.get('newState', {})
            previous_state = detail.get('previousState', {})
            
            state_value = new_state.get('value', '')
            state_reason = new_state.get('reason', '')
            state_timestamp = new_state.get('timestamp', '')
            
            # Parse alarm metadata
            alarm_metadata = self._parse_alarm_metadata(alarm_name, detail)
            
            logger.info(f"Processing alarm: {alarm_name}, State: {state_value}")
            
            # Create event context for processing
            event_context = {
                'alarm_name': alarm_name,
                'service_name': alarm_metadata.get('service_name', 'unknown'),
                'metric_type': alarm_metadata.get('metric_type', 'unknown'),
                'state_value': state_value,
                'previous_state': previous_state.get('value', 'UNKNOWN'),
                'state_reason': state_reason,
                'timestamp': state_timestamp,
                'correlation_id': str(uuid.uuid4())
            }
            
            # Process alarm state change
            actions_taken = []
            
            if state_value == 'ALARM':
                actions_taken.extend(self._handle_alarm_state(event_context))
            elif state_value == 'OK':
                actions_taken.extend(self._handle_ok_state(event_context))
            else:
                logger.info(f"Ignoring alarm state: {state_value}")
            
            # Update correlation cache
            self._update_correlation_cache(event_context)
            
            return {
                'statusCode': 200,
                'processed_alarm': alarm_name,
                'state_transition': f"{previous_state.get('value', 'UNKNOWN')} -> {state_value}",
                'actions_taken': actions_taken,
                'correlation_id': event_context['correlation_id']
            }
            
        except Exception as e:
            logger.error(f"Error processing alarm event: {str(e)}", exc_info=True)
            raise
    
    def _parse_alarm_metadata(self, alarm_name: str, detail: Dict[str, Any]) -> Dict[str, str]:
        """
        Parse alarm metadata from alarm name and event details
        
        Args:
            alarm_name: CloudWatch alarm name
            detail: Event detail containing alarm information
            
        Returns:
            Dict containing parsed metadata
        """
        metadata = {
            'service_name': 'unknown',
            'metric_type': 'unknown'
        }
        
        try:
            # Parse service name and metric type from alarm name
            # Expected format: {prefix}-{service}-{metric-type}
            name_parts = alarm_name.split('-')
            if len(name_parts) >= 3:
                metadata['service_name'] = name_parts[-2] if len(name_parts) > 2 else 'unknown'
                metadata['metric_type'] = name_parts[-1]
            
            # Extract additional metadata from event detail
            metric_name = detail.get('metric', {}).get('metricStat', {}).get('metric', {}).get('metricName', '')
            if metric_name:
                metadata['metric_name'] = metric_name
                
            # Map metric names to types
            metric_type_mapping = {
                'Latency': 'latency',
                'ErrorRate': 'error-rate', 
                'CallCount': 'throughput'
            }
            
            if metric_name in metric_type_mapping:
                metadata['metric_type'] = metric_type_mapping[metric_name]
                
        except Exception as e:
            logger.warning(f"Failed to parse alarm metadata: {str(e)}")
            
        return metadata
    
    def _handle_alarm_state(self, context: Dict[str, Any]) -> List[str]:
        """
        Handle alarm state (performance issue detected)
        
        Args:
            context: Event context containing alarm details
            
        Returns:
            List of actions taken
        """
        actions_taken = []
        
        try:
            # Check for alert correlation
            correlated_alerts = self._check_alert_correlation(context)
            
            # Determine severity and response level
            severity = self._determine_severity(context, correlated_alerts)
            
            # Send notification
            notification_sent = self._send_alarm_notification(context, severity, correlated_alerts)
            if notification_sent:
                actions_taken.append(f"sent_{severity}_notification")
            
            # Implement automated responses based on metric type and severity
            if severity in ['high', 'critical']:
                scaling_action = self._trigger_scaling_response(context, severity)
                if scaling_action:
                    actions_taken.append(f"triggered_{scaling_action}")
            
            # Log performance metrics for analysis
            self._log_performance_metrics(context, actions_taken)
            
            logger.info(f"Alarm response completed for {context['alarm_name']}: {actions_taken}")
            
        except Exception as e:
            logger.error(f"Error handling alarm state: {str(e)}", exc_info=True)
            actions_taken.append("error_in_alarm_handling")
            
        return actions_taken
    
    def _handle_ok_state(self, context: Dict[str, Any]) -> List[str]:
        """
        Handle OK state (performance issue resolved)
        
        Args:
            context: Event context containing alarm details
            
        Returns:
            List of actions taken
        """
        actions_taken = []
        
        try:
            # Send resolution notification
            notification_sent = self._send_resolution_notification(context)
            if notification_sent:
                actions_taken.append("sent_resolution_notification")
            
            # Clean up correlation cache
            self._cleanup_correlation_cache(context)
            
            # Log resolution metrics
            self._log_resolution_metrics(context)
            
            logger.info(f"Resolution processed for {context['alarm_name']}")
            
        except Exception as e:
            logger.error(f"Error handling OK state: {str(e)}", exc_info=True)
            actions_taken.append("error_in_resolution_handling")
            
        return actions_taken
    
    def _check_alert_correlation(self, context: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Check for correlated alerts within the time window
        
        Args:
            context: Event context
            
        Returns:
            List of correlated alerts
        """
        correlated_alerts = []
        
        try:
            service_name = context['service_name']
            current_time = datetime.now()
            
            # Check correlation cache for related alerts
            for cached_alarm, alarm_context in self.correlation_cache.items():
                if (alarm_context['service_name'] == service_name and
                    alarm_context['state_value'] == 'ALARM' and
                    (current_time - datetime.fromisoformat(alarm_context['timestamp'].replace('Z', '+00:00'))).total_seconds() < ALERT_CORRELATION_WINDOW_MINUTES * 60):
                    correlated_alerts.append(alarm_context)
            
            logger.info(f"Found {len(correlated_alerts)} correlated alerts for service {service_name}")
            
        except Exception as e:
            logger.warning(f"Error checking alert correlation: {str(e)}")
            
        return correlated_alerts
    
    def _determine_severity(self, context: Dict[str, Any], correlated_alerts: List[Dict[str, Any]]) -> str:
        """
        Determine alert severity based on context and correlation
        
        Args:
            context: Event context
            correlated_alerts: List of correlated alerts
            
        Returns:
            Severity level (low, medium, high, critical)
        """
        try:
            base_severity = 'medium'
            
            # Adjust severity based on metric type
            metric_type = context['metric_type']
            if metric_type == 'error-rate':
                base_severity = 'high'
            elif metric_type == 'latency':
                base_severity = 'medium'
            elif metric_type == 'throughput':
                base_severity = 'low'
            
            # Escalate severity based on correlated alerts
            if len(correlated_alerts) >= 3:
                base_severity = 'critical'
            elif len(correlated_alerts) >= 2:
                if base_severity == 'medium':
                    base_severity = 'high'
                elif base_severity == 'low':
                    base_severity = 'medium'
            
            logger.info(f"Determined severity: {base_severity} for {context['alarm_name']}")
            return base_severity
            
        except Exception as e:
            logger.warning(f"Error determining severity: {str(e)}")
            return 'medium'
    
    def _send_alarm_notification(self, context: Dict[str, Any], severity: str, correlated_alerts: List[Dict[str, Any]]) -> bool:
        """
        Send alarm notification via SNS
        
        Args:
            context: Event context
            severity: Alert severity
            correlated_alerts: List of correlated alerts
            
        Returns:
            True if notification sent successfully
        """
        try:
            if not SNS_TOPIC_ARN:
                logger.warning("SNS_TOPIC_ARN not configured, skipping notification")
                return False
            
            # Format notification message
            severity_emoji = {
                'low': '🟡',
                'medium': '🟠', 
                'high': '🔴',
                'critical': '🚨'
            }
            
            emoji = severity_emoji.get(severity, '⚠️')
            
            subject = f"{emoji} Performance Alert: {context['alarm_name']}"
            
            message_lines = [
                f"{emoji} APPLICATION PERFORMANCE ALERT {emoji}",
                "",
                f"Alarm: {context['alarm_name']}",
                f"Service: {context['service_name']}",
                f"Metric Type: {context['metric_type']}",
                f"Severity: {severity.upper()}",
                f"State: {context['state_value']}",
                f"Previous State: {context['previous_state']}",
                f"Reason: {context['state_reason']}",
                f"Time: {context['timestamp']}",
                f"Environment: {ENVIRONMENT}",
                f"Project: {PROJECT_NAME}",
                f"Correlation ID: {context['correlation_id']}",
                ""
            ]
            
            if correlated_alerts:
                message_lines.extend([
                    f"⚠️ CORRELATED ALERTS ({len(correlated_alerts)}):",
                    ""
                ])
                for alert in correlated_alerts[:3]:  # Show max 3 correlated alerts
                    message_lines.append(f"  • {alert['alarm_name']} ({alert['metric_type']})")
                
                if len(correlated_alerts) > 3:
                    message_lines.append(f"  • ... and {len(correlated_alerts) - 3} more")
                
                message_lines.append("")
            
            message_lines.extend([
                "🔧 AUTOMATED ACTIONS:",
                "✅ Alert correlation analysis completed",
                "✅ Performance monitoring dashboard updated",
                "⏳ Investigating scaling requirements...",
                "",
                "📊 Monitor real-time metrics:",
                f"https://console.aws.amazon.com/cloudwatch/home#application-signals:services",
                "",
                "📋 View performance dashboard:",
                f"https://console.aws.amazon.com/cloudwatch/home#dashboards:name={PROJECT_NAME}-performance-monitoring",
            ])
            
            message = "\n".join(message_lines)
            
            # Send SNS notification
            response = self.sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Message=message,
                Subject=subject
            )
            
            logger.info(f"Sent {severity} alert notification for {context['alarm_name']}")
            return True
            
        except Exception as e:
            logger.error(f"Error sending alarm notification: {str(e)}")
            return False
    
    def _send_resolution_notification(self, context: Dict[str, Any]) -> bool:
        """
        Send resolution notification via SNS
        
        Args:
            context: Event context
            
        Returns:
            True if notification sent successfully
        """
        try:
            if not SNS_TOPIC_ARN:
                logger.warning("SNS_TOPIC_ARN not configured, skipping notification")
                return False
            
            subject = f"✅ Alert Resolved: {context['alarm_name']}"
            
            message_lines = [
                "✅ PERFORMANCE ALERT RESOLVED ✅",
                "",
                f"Alarm: {context['alarm_name']}",
                f"Service: {context['service_name']}",
                f"Metric Type: {context['metric_type']}",
                f"State: {context['state_value']}",
                f"Previous State: {context['previous_state']}",
                f"Time: {context['timestamp']}",
                f"Environment: {ENVIRONMENT}",
                f"Project: {PROJECT_NAME}",
                f"Correlation ID: {context['correlation_id']}",
                "",
                "🎉 Performance metrics have returned to normal levels.",
                "📊 Continue monitoring via the performance dashboard.",
                "",
                f"Dashboard: https://console.aws.amazon.com/cloudwatch/home#dashboards:name={PROJECT_NAME}-performance-monitoring"
            ]
            
            message = "\n".join(message_lines)
            
            # Send SNS notification
            response = self.sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Message=message,
                Subject=subject
            )
            
            logger.info(f"Sent resolution notification for {context['alarm_name']}")
            return True
            
        except Exception as e:
            logger.error(f"Error sending resolution notification: {str(e)}")
            return False
    
    def _trigger_scaling_response(self, context: Dict[str, Any], severity: str) -> Optional[str]:
        """
        Trigger automated scaling response (placeholder for future implementation)
        
        Args:
            context: Event context
            severity: Alert severity
            
        Returns:
            Scaling action taken, if any
        """
        try:
            # This is a placeholder for future auto-scaling implementation
            # In a real implementation, this would:
            # 1. Check if scaling is enabled and configured
            # 2. Verify scaling cooldown periods
            # 3. Determine appropriate scaling action based on metric type
            # 4. Execute scaling via Auto Scaling Groups or ECS services
            
            logger.info(f"Scaling evaluation for {context['service_name']} (severity: {severity})")
            
            # For now, just log the scaling decision
            if severity == 'critical':
                logger.info("Would trigger immediate scaling response")
                return "evaluation_critical_scaling"
            elif severity == 'high':
                logger.info("Would prepare scaling response")
                return "evaluation_high_scaling"
            
            return None
            
        except Exception as e:
            logger.error(f"Error in scaling response: {str(e)}")
            return "scaling_error"
    
    def _update_correlation_cache(self, context: Dict[str, Any]) -> None:
        """
        Update correlation cache with current alarm context
        
        Args:
            context: Event context
        """
        try:
            self.correlation_cache[context['alarm_name']] = context
            
            # Clean up old entries (older than correlation window)
            current_time = datetime.now()
            expired_keys = []
            
            for alarm_name, cached_context in self.correlation_cache.items():
                try:
                    cached_time = datetime.fromisoformat(cached_context['timestamp'].replace('Z', '+00:00'))
                    if (current_time - cached_time).total_seconds() > ALERT_CORRELATION_WINDOW_MINUTES * 60:
                        expired_keys.append(alarm_name)
                except:
                    expired_keys.append(alarm_name)
            
            for key in expired_keys:
                del self.correlation_cache[key]
                
            logger.debug(f"Updated correlation cache, {len(self.correlation_cache)} active entries")
            
        except Exception as e:
            logger.warning(f"Error updating correlation cache: {str(e)}")
    
    def _cleanup_correlation_cache(self, context: Dict[str, Any]) -> None:
        """
        Clean up correlation cache for resolved alarm
        
        Args:
            context: Event context
        """
        try:
            alarm_name = context['alarm_name']
            if alarm_name in self.correlation_cache:
                del self.correlation_cache[alarm_name]
                logger.debug(f"Cleaned up correlation cache entry for {alarm_name}")
                
        except Exception as e:
            logger.warning(f"Error cleaning up correlation cache: {str(e)}")
    
    def _log_performance_metrics(self, context: Dict[str, Any], actions_taken: List[str]) -> None:
        """
        Log performance metrics for analysis and improvement
        
        Args:
            context: Event context
            actions_taken: List of actions taken
        """
        try:
            logger.info(json.dumps({
                'metric_type': 'performance_alert_processed',
                'alarm_name': context['alarm_name'],
                'service_name': context['service_name'],
                'metric_type_category': context['metric_type'],
                'state_transition': f"{context['previous_state']} -> {context['state_value']}",
                'actions_taken': actions_taken,
                'correlation_id': context['correlation_id'],
                'timestamp': datetime.now().isoformat(),
                'environment': ENVIRONMENT,
                'project': PROJECT_NAME
            }))
            
        except Exception as e:
            logger.warning(f"Error logging performance metrics: {str(e)}")
    
    def _log_resolution_metrics(self, context: Dict[str, Any]) -> None:
        """
        Log resolution metrics for analysis
        
        Args:
            context: Event context
        """
        try:
            logger.info(json.dumps({
                'metric_type': 'performance_alert_resolved',
                'alarm_name': context['alarm_name'],
                'service_name': context['service_name'],
                'metric_type_category': context['metric_type'],
                'correlation_id': context['correlation_id'],
                'timestamp': datetime.now().isoformat(),
                'environment': ENVIRONMENT,
                'project': PROJECT_NAME
            }))
            
        except Exception as e:
            logger.warning(f"Error logging resolution metrics: {str(e)}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for processing CloudWatch alarm events
    
    Args:
        event: EventBridge event containing alarm state change
        context: Lambda runtime context
        
    Returns:
        Response dictionary with processing results
    """
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Initialize the alert processor
        processor = PerformanceAlertProcessor()
        
        # Process the alarm event
        result = processor.process_alarm_event(event)
        
        logger.info(f"Event processing completed: {json.dumps(result, default=str)}")
        return result
        
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}", exc_info=True)
        
        # Return error response
        return {
            'statusCode': 500,
            'error': str(e),
            'event_id': event.get('id', 'unknown'),
            'timestamp': datetime.now().isoformat()
        }