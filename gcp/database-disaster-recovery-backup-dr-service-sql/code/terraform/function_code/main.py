"""
Disaster Recovery Orchestration Functions for Cloud SQL
Handles automated disaster recovery procedures, health monitoring, and backup validation
"""

import functions_framework
import json
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List

# Import Google Cloud client libraries
try:
    from google.cloud import sql_v1
    from google.cloud import monitoring_v3
    from google.cloud import pubsub_v1
    from google.cloud import logging as cloud_logging
except ImportError as e:
    logging.error(f"Failed to import Google Cloud libraries: {e}")
    raise

# Initialize clients
sql_client = sql_v1.SqlInstancesServiceClient()
backup_client = sql_v1.SqlBackupRunsServiceClient()
monitoring_client = monitoring_v3.MetricServiceClient()
publisher = pubsub_v1.PublisherClient()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = "${project_id}"
PRIMARY_REGION = "${primary_region}"
SECONDARY_REGION = "${secondary_region}"

def get_env_var(var_name: str, default: str = None) -> str:
    """Get environment variable with fallback."""
    value = os.environ.get(var_name, default)
    if value is None:
        raise ValueError(f"Environment variable {var_name} is required")
    return value

@functions_framework.http
def orchestrate_disaster_recovery(request):
    """
    Main orchestration function for disaster recovery operations.
    
    Handles:
    - Health monitoring of primary instance
    - Automated failover procedures
    - Backup validation
    - Alert processing
    """
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {"error": "Invalid JSON in request"}, 400
        
        action = request_json.get("action", "health_check")
        source = request_json.get("source", "unknown")
        
        logger.info(f"Processing DR action: {action} from source: {source}")
        
        # Route to appropriate handler
        if action == "health_check":
            return handle_health_check()
        elif action == "initiate_failover":
            return handle_failover_initiation(request_json)
        elif action == "validate_backups":
            return handle_backup_validation()
        elif action == "process_alert":
            return handle_alert_processing(request_json)
        else:
            return {"error": f"Unknown action: {action}"}, 400
            
    except Exception as e:
        logger.error(f"Error in DR orchestration: {str(e)}")
        return {"error": str(e)}, 500

def handle_health_check() -> Dict[str, Any]:
    """
    Perform comprehensive health check of primary and replica instances.
    """
    
    try:
        project_id = get_env_var("PROJECT_ID")
        primary_instance = get_env_var("PRIMARY_INSTANCE")
        dr_replica = get_env_var("DR_REPLICA")
        
        # Check primary instance health
        primary_health = check_instance_health(project_id, primary_instance)
        
        # Check DR replica health
        replica_health = check_instance_health(project_id, dr_replica)
        
        # Check replication lag
        replication_status = check_replication_status(project_id, primary_instance, dr_replica)
        
        # Overall health assessment
        overall_healthy = (
            primary_health.get("healthy", False) and
            replica_health.get("healthy", False) and
            replication_status.get("healthy", False)
        )
        
        result = {
            "status": "health_check_complete",
            "timestamp": datetime.utcnow().isoformat(),
            "overall_healthy": overall_healthy,
            "primary_instance": primary_health,
            "dr_replica": replica_health,
            "replication": replication_status
        }
        
        # If unhealthy, consider triggering alerts
        if not overall_healthy:
            logger.warning("Health check detected issues - considering automated recovery")
            publish_alert(result, "health_check_failed")
        
        return result
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return {"error": f"Health check failed: {str(e)}"}, 500

def handle_failover_initiation(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Initiate automated failover to disaster recovery replica.
    """
    
    try:
        project_id = get_env_var("PROJECT_ID")
        primary_instance = get_env_var("PRIMARY_INSTANCE")
        dr_replica = get_env_var("DR_REPLICA")
        
        # Verify failover conditions
        failover_conditions = verify_failover_conditions(project_id, primary_instance, dr_replica)
        
        if not failover_conditions["can_failover"]:
            return {
                "status": "failover_rejected",
                "reason": failover_conditions["reason"],
                "timestamp": datetime.utcnow().isoformat()
            }
        
        # Initiate failover
        logger.info(f"Initiating failover from {primary_instance} to {dr_replica}")
        
        failover_operation = sql_client.failover_replica(
            project=project_id,
            instance=dr_replica
        )
        
        # Publish notification
        publish_alert({
            "operation_id": failover_operation.name,
            "primary_instance": primary_instance,
            "dr_replica": dr_replica
        }, "failover_initiated")
        
        return {
            "status": "failover_initiated",
            "operation_id": failover_operation.name,
            "timestamp": datetime.utcnow().isoformat(),
            "estimated_completion": (datetime.utcnow() + timedelta(minutes=10)).isoformat()
        }
        
    except Exception as e:
        logger.error(f"Failover initiation failed: {str(e)}")
        return {"error": f"Failover failed: {str(e)}"}, 500

def handle_backup_validation() -> Dict[str, Any]:
    """
    Validate backup integrity and availability.
    """
    
    try:
        project_id = get_env_var("PROJECT_ID")
        primary_instance = get_env_var("PRIMARY_INSTANCE")
        
        # List recent backups
        backups = backup_client.list(
            project=project_id,
            instance=primary_instance,
            max_results=5
        )
        
        validation_results = []
        successful_backups = 0
        
        for backup in backups:
            backup_info = {
                "backup_id": backup.id,
                "status": backup.status.name if backup.status else "UNKNOWN",
                "type": backup.type_.name if backup.type_ else "UNKNOWN",
                "start_time": backup.start_time.isoformat() if backup.start_time else None,
                "end_time": backup.end_time.isoformat() if backup.end_time else None,
                "size_bytes": getattr(backup, 'size_bytes', 0)
            }
            
            # Check if backup is successful
            if backup.status and backup.status.name == "SUCCESSFUL":
                successful_backups += 1
                backup_info["validation_status"] = "VALID"
            else:
                backup_info["validation_status"] = "INVALID"
            
            validation_results.append(backup_info)
        
        # Calculate backup health score
        backup_health_score = (successful_backups / len(validation_results)) * 100 if validation_results else 0
        
        result = {
            "status": "backup_validation_complete",
            "timestamp": datetime.utcnow().isoformat(),
            "backup_count": len(validation_results),
            "successful_backups": successful_backups,
            "backup_health_score": backup_health_score,
            "backups": validation_results,
            "recommendations": generate_backup_recommendations(validation_results)
        }
        
        # Alert if backup health is poor
        if backup_health_score < 80:
            publish_alert(result, "backup_health_degraded")
        
        return result
        
    except Exception as e:
        logger.error(f"Backup validation failed: {str(e)}")
        return {"error": f"Backup validation failed: {str(e)}"}, 500

def handle_alert_processing(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process incoming alerts and determine appropriate response.
    """
    
    try:
        alert_type = request_data.get("alert_type", "unknown")
        alert_data = request_data.get("alert_data", {})
        
        logger.info(f"Processing alert type: {alert_type}")
        
        response_actions = []
        
        # Determine response based on alert type
        if alert_type == "instance_down":
            response_actions = handle_instance_down_alert(alert_data)
        elif alert_type == "backup_failed":
            response_actions = handle_backup_failure_alert(alert_data)
        elif alert_type == "replication_lag":
            response_actions = handle_replication_lag_alert(alert_data)
        else:
            response_actions = ["log_unknown_alert"]
        
        return {
            "status": "alert_processed",
            "alert_type": alert_type,
            "response_actions": response_actions,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Alert processing failed: {str(e)}")
        return {"error": f"Alert processing failed: {str(e)}"}, 500

def check_instance_health(project_id: str, instance_name: str) -> Dict[str, Any]:
    """Check the health status of a Cloud SQL instance."""
    
    try:
        instance = sql_client.get(project=project_id, instance=instance_name)
        
        health_info = {
            "instance_name": instance_name,
            "healthy": instance.state == sql_v1.SqlInstanceState.RUNNABLE,
            "state": instance.state.name if instance.state else "UNKNOWN",
            "backend_type": instance.backend_type.name if instance.backend_type else "UNKNOWN",
            "region": getattr(instance, 'region', 'unknown'),
            "availability_type": getattr(instance.settings, 'availability_type', 'UNKNOWN') if instance.settings else "UNKNOWN"
        }
        
        # Additional health checks
        if instance.state == sql_v1.SqlInstanceState.RUNNABLE:
            health_info["last_check"] = datetime.utcnow().isoformat()
            health_info["uptime_status"] = "operational"
        else:
            health_info["uptime_status"] = "degraded"
            health_info["issue_detected"] = True
        
        return health_info
        
    except Exception as e:
        logger.error(f"Failed to check instance health for {instance_name}: {str(e)}")
        return {
            "instance_name": instance_name,
            "healthy": False,
            "error": str(e),
            "uptime_status": "unknown"
        }

def check_replication_status(project_id: str, primary_instance: str, replica_instance: str) -> Dict[str, Any]:
    """Check replication status between primary and replica."""
    
    try:
        # Get replica instance details
        replica = sql_client.get(project=project_id, instance=replica_instance)
        
        replication_info = {
            "primary_instance": primary_instance,
            "replica_instance": replica_instance,
            "healthy": True,
            "status": "active"
        }
        
        # Check if replica is properly configured
        if hasattr(replica, 'master_instance_name') and replica.master_instance_name:
            if replica.master_instance_name.split(':')[-1] != primary_instance:
                replication_info["healthy"] = False
                replication_info["error"] = "Replica not pointing to correct master"
        
        # Check replica state
        if replica.state != sql_v1.SqlInstanceState.RUNNABLE:
            replication_info["healthy"] = False
            replication_info["status"] = "degraded"
            replication_info["replica_state"] = replica.state.name if replica.state else "UNKNOWN"
        
        return replication_info
        
    except Exception as e:
        logger.error(f"Failed to check replication status: {str(e)}")
        return {
            "primary_instance": primary_instance,
            "replica_instance": replica_instance,
            "healthy": False,
            "error": str(e)
        }

def verify_failover_conditions(project_id: str, primary_instance: str, dr_replica: str) -> Dict[str, Any]:
    """Verify that conditions are met for safe failover."""
    
    try:
        # Check primary instance state
        primary_health = check_instance_health(project_id, primary_instance)
        
        # Check replica readiness
        replica_health = check_instance_health(project_id, dr_replica)
        
        # Determine if failover is safe
        can_failover = True
        reasons = []
        
        if primary_health.get("healthy", False):
            can_failover = False
            reasons.append("Primary instance is still healthy")
        
        if not replica_health.get("healthy", False):
            can_failover = False
            reasons.append("DR replica is not healthy")
        
        return {
            "can_failover": can_failover,
            "reason": "; ".join(reasons) if reasons else "Conditions met for failover",
            "primary_health": primary_health,
            "replica_health": replica_health
        }
        
    except Exception as e:
        logger.error(f"Failed to verify failover conditions: {str(e)}")
        return {
            "can_failover": False,
            "reason": f"Verification failed: {str(e)}"
        }

def generate_backup_recommendations(backup_results: List[Dict[str, Any]]) -> List[str]:
    """Generate recommendations based on backup validation results."""
    
    recommendations = []
    
    if not backup_results:
        recommendations.append("No recent backups found - check backup configuration")
        return recommendations
    
    successful_count = sum(1 for backup in backup_results if backup.get("validation_status") == "VALID")
    total_count = len(backup_results)
    
    if successful_count < total_count:
        recommendations.append(f"Only {successful_count}/{total_count} recent backups are valid")
    
    if successful_count == 0:
        recommendations.append("CRITICAL: No successful backups found - immediate attention required")
    
    # Check backup frequency
    if total_count < 3:
        recommendations.append("Consider increasing backup frequency for better recovery options")
    
    return recommendations

def handle_instance_down_alert(alert_data: Dict[str, Any]) -> List[str]:
    """Handle instance down alert."""
    return [
        "verify_instance_status",
        "check_replica_health",
        "consider_automated_failover",
        "notify_operations_team"
    ]

def handle_backup_failure_alert(alert_data: Dict[str, Any]) -> List[str]:
    """Handle backup failure alert."""
    return [
        "investigate_backup_failure",
        "verify_backup_configuration",
        "attempt_manual_backup",
        "notify_database_team"
    ]

def handle_replication_lag_alert(alert_data: Dict[str, Any]) -> List[str]:
    """Handle replication lag alert."""
    return [
        "monitor_replication_lag",
        "check_network_connectivity",
        "verify_replica_resources",
        "consider_replica_scaling"
    ]

def publish_alert(alert_data: Dict[str, Any], alert_type: str) -> None:
    """Publish alert to Pub/Sub topic."""
    
    try:
        topic_name = get_env_var("PUBSUB_TOPIC")
        topic_path = publisher.topic_path(PROJECT_ID, topic_name)
        
        message_data = {
            "alert_type": alert_type,
            "timestamp": datetime.utcnow().isoformat(),
            "data": alert_data
        }
        
        # Publish message
        future = publisher.publish(topic_path, json.dumps(message_data).encode('utf-8'))
        logger.info(f"Published alert {alert_type} to topic {topic_name}")
        
    except Exception as e:
        logger.error(f"Failed to publish alert: {str(e)}")

@functions_framework.cloud_event
def validate_backups(cloud_event):
    """
    Cloud Event function for backup validation.
    Triggered by Pub/Sub messages or scheduled events.
    """
    
    try:
        logger.info("Starting backup validation process")
        
        # Call the main validation logic
        result = handle_backup_validation()
        
        logger.info(f"Backup validation completed: {result.get('status', 'unknown')}")
        return result
        
    except Exception as e:
        logger.error(f"Backup validation function failed: {str(e)}")
        return {"error": str(e)}

# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """Simple health check endpoint."""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "function": "disaster-recovery-orchestrator",
        "version": "1.0"
    }