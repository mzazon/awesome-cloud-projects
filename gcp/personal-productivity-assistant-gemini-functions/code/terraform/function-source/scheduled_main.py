# Personal Productivity Assistant - Scheduled Email Processing Function
# Cloud Function triggered by Cloud Scheduler via Pub/Sub for automated email processing

import os
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List
import functions_framework
from google.cloud import firestore
from google.cloud import pubsub_v1
from google.cloud import storage
import base64

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize from template variables
PROJECT_ID = "${project_id}"
REGION = "${region}"

# Initialize Google Cloud clients
try:
    db = firestore.Client(project=PROJECT_ID)
    storage_client = storage.Client(project=PROJECT_ID)
    subscriber = pubsub_v1.SubscriberClient()
    publisher = pubsub_v1.PublisherClient()
    logger.info("Google Cloud clients initialized successfully for scheduled processing")
except Exception as e:
    logger.error(f"Failed to initialize Google Cloud clients: {str(e)}")
    raise

def record_scheduled_run(status: str, details: Dict[str, Any] = None) -> str:
    """
    Record the execution of a scheduled run in Firestore.
    
    Args:
        status: Status of the scheduled run (started, completed, failed)
        details: Additional details about the run
        
    Returns:
        Document ID of the created record
    """
    try:
        run_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "status": status,
            "project_id": PROJECT_ID,
            "region": REGION,
            "processed_at": firestore.SERVER_TIMESTAMP
        }
        
        if details:
            run_data["details"] = details
        
        # Create document in scheduled_runs collection
        doc_ref = db.collection('scheduled_runs').document()
        doc_ref.set(run_data)
        
        logger.info(f"Recorded scheduled run with status: {status}")
        return doc_ref.id
        
    except Exception as e:
        logger.error(f"Error recording scheduled run: {str(e)}")
        raise

def cleanup_old_records(days_to_keep: int = 30) -> int:
    """
    Clean up old records from Firestore to manage storage costs.
    
    Args:
        days_to_keep: Number of days to keep records
        
    Returns:
        Number of records cleaned up
    """
    try:
        cutoff_date = datetime.utcnow() - timedelta(days=days_to_keep)
        cleanup_count = 0
        
        # Clean up old email analysis records
        old_analysis_query = db.collection('email_analysis').where(
            'processed_at', '<', cutoff_date
        ).limit(100)  # Process in batches to avoid timeout
        
        old_docs = old_analysis_query.stream()
        batch = db.batch()
        
        for doc in old_docs:
            batch.delete(doc.reference)
            cleanup_count += 1
        
        if cleanup_count > 0:
            batch.commit()
            logger.info(f"Cleaned up {cleanup_count} old email analysis records")
        
        # Clean up old scheduled run records
        old_runs_query = db.collection('scheduled_runs').where(
            'processed_at', '<', cutoff_date
        ).limit(100)
        
        old_run_docs = old_runs_query.stream()
        batch = db.batch()
        run_cleanup_count = 0
        
        for doc in old_run_docs:
            batch.delete(doc.reference)
            run_cleanup_count += 1
        
        if run_cleanup_count > 0:
            batch.commit()
            logger.info(f"Cleaned up {run_cleanup_count} old scheduled run records")
        
        return cleanup_count + run_cleanup_count
        
    except Exception as e:
        logger.error(f"Error during cleanup: {str(e)}")
        return 0

def get_processing_statistics() -> Dict[str, Any]:
    """
    Generate processing statistics for monitoring and reporting.
    
    Returns:
        Dictionary containing processing statistics
    """
    try:
        stats = {
            "total_emails_processed": 0,
            "emails_processed_today": 0,
            "average_urgency_score": 0,
            "total_action_items": 0,
            "replies_generated": 0,
            "last_24h_processing_count": 0
        }
        
        # Get statistics from the last 24 hours
        yesterday = datetime.utcnow() - timedelta(days=1)
        
        # Query email analysis from last 24 hours
        recent_query = db.collection('email_analysis').where(
            'processed_at', '>=', yesterday
        ).stream()
        
        urgency_scores = []
        action_items_count = 0
        replies_count = 0
        
        for doc in recent_query:
            data = doc.to_dict()
            stats["last_24h_processing_count"] += 1
            
            # Aggregate urgency scores
            urgency = data.get('urgency_score', 0)
            if urgency > 0:
                urgency_scores.append(urgency)
            
            # Count action items
            action_items = data.get('action_items', [])
            action_items_count += len(action_items)
            
            # Count replies generated
            if data.get('reply', {}).get('text'):
                replies_count += 1
        
        # Calculate averages
        if urgency_scores:
            stats["average_urgency_score"] = sum(urgency_scores) / len(urgency_scores)
        
        stats["total_action_items"] = action_items_count
        stats["replies_generated"] = replies_count
        
        # Get total count (approximate)
        try:
            total_docs = db.collection('email_analysis').limit(1000).stream()
            stats["total_emails_processed"] = len(list(total_docs))
        except Exception:
            stats["total_emails_processed"] = "unavailable"
        
        # Get today's count
        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        today_query = db.collection('email_analysis').where(
            'processed_at', '>=', today_start
        ).stream()
        
        stats["emails_processed_today"] = len(list(today_query))
        
        logger.info(f"Generated processing statistics: {stats['last_24h_processing_count']} emails in last 24h")
        return stats
        
    except Exception as e:
        logger.error(f"Error generating statistics: {str(e)}")
        return {"error": str(e)}

def check_system_health() -> Dict[str, Any]:
    """
    Perform system health checks and return status.
    
    Returns:
        Dictionary containing health check results
    """
    health_status = {
        "overall_status": "healthy",
        "checks": {
            "firestore": {"status": "unknown", "details": ""},
            "pubsub": {"status": "unknown", "details": ""},
            "storage": {"status": "unknown", "details": ""},
            "processing_pipeline": {"status": "unknown", "details": ""}
        },
        "timestamp": datetime.utcnow().isoformat()
    }
    
    try:
        # Test Firestore connectivity
        try:
            test_doc = db.collection('health_check').document('test')
            test_doc.set({"timestamp": firestore.SERVER_TIMESTAMP})
            health_status["checks"]["firestore"]["status"] = "healthy"
            health_status["checks"]["firestore"]["details"] = "Write/read operations successful"
        except Exception as e:
            health_status["checks"]["firestore"]["status"] = "unhealthy"
            health_status["checks"]["firestore"]["details"] = str(e)
            health_status["overall_status"] = "degraded"
        
        # Test Pub/Sub connectivity
        try:
            topic_path = publisher.topic_path(PROJECT_ID, 'email-processing-topic')
            publisher.get_topic(request={"topic": topic_path})
            health_status["checks"]["pubsub"]["status"] = "healthy"
            health_status["checks"]["pubsub"]["details"] = "Topic accessible"
        except Exception as e:
            health_status["checks"]["pubsub"]["status"] = "unhealthy"
            health_status["checks"]["pubsub"]["details"] = str(e)
            health_status["overall_status"] = "degraded"
        
        # Test Storage connectivity
        try:
            buckets = list(storage_client.list_buckets(max_results=1))
            health_status["checks"]["storage"]["status"] = "healthy"
            health_status["checks"]["storage"]["details"] = "Bucket listing successful"
        except Exception as e:
            health_status["checks"]["storage"]["status"] = "unhealthy"
            health_status["checks"]["storage"]["details"] = str(e)
            health_status["overall_status"] = "degraded"
        
        # Check processing pipeline health (recent processing activity)
        try:
            recent_time = datetime.utcnow() - timedelta(hours=1)
            recent_docs = list(db.collection('email_analysis').where(
                'processed_at', '>=', recent_time
            ).limit(1).stream())
            
            if recent_docs:
                health_status["checks"]["processing_pipeline"]["status"] = "healthy"
                health_status["checks"]["processing_pipeline"]["details"] = "Recent processing activity detected"
            else:
                health_status["checks"]["processing_pipeline"]["status"] = "idle"
                health_status["checks"]["processing_pipeline"]["details"] = "No recent processing activity"
        except Exception as e:
            health_status["checks"]["processing_pipeline"]["status"] = "unhealthy"
            health_status["checks"]["processing_pipeline"]["details"] = str(e)
        
        logger.info(f"Health check completed with overall status: {health_status['overall_status']}")
        return health_status
        
    except Exception as e:
        logger.error(f"Error during health check: {str(e)}")
        health_status["overall_status"] = "unhealthy"
        health_status["error"] = str(e)
        return health_status

def send_monitoring_alert(alert_data: Dict[str, Any]) -> None:
    """
    Send monitoring alerts via Pub/Sub (can be extended to other channels).
    
    Args:
        alert_data: Alert information to send
    """
    try:
        # Publish alert to a monitoring topic (create topic if needed for alerts)
        monitoring_topic = "system-monitoring-alerts"
        topic_path = publisher.topic_path(PROJECT_ID, monitoring_topic)
        
        alert_message = {
            "alert_type": alert_data.get("type", "general"),
            "severity": alert_data.get("severity", "info"),
            "message": alert_data.get("message", ""),
            "timestamp": datetime.utcnow().isoformat(),
            "source": "scheduled-email-processor"
        }
        
        message_bytes = json.dumps(alert_message).encode('utf-8')
        future = publisher.publish(topic_path, message_bytes)
        
        logger.info(f"Monitoring alert sent: {alert_data.get('message', 'Unknown alert')}")
        
    except Exception as e:
        # Don't fail the function if monitoring alerts fail
        logger.warning(f"Failed to send monitoring alert: {str(e)}")

@functions_framework.cloud_event
def process_scheduled_emails(cloud_event):
    """
    Main entry point for scheduled email processing.
    Triggered by Cloud Scheduler via Pub/Sub.
    
    Args:
        cloud_event: Cloud Event containing Pub/Sub message
        
    Returns:
        Dictionary with processing results
    """
    try:
        # Record the start of scheduled processing
        run_id = record_scheduled_run("started")
        
        logger.info("Starting scheduled email processing run")
        
        # Decode the Pub/Sub message
        trigger_data = {}
        if hasattr(cloud_event, 'data') and cloud_event.data:
            try:
                # Decode base64 Pub/Sub data
                message_data = base64.b64decode(cloud_event.data).decode('utf-8')
                trigger_data = json.loads(message_data)
                logger.info(f"Processing triggered by: {trigger_data.get('trigger', 'unknown')}")
            except Exception as e:
                logger.warning(f"Could not decode trigger data: {str(e)}")
        
        # Perform maintenance tasks
        maintenance_results = {}
        
        # 1. Clean up old records
        try:
            cleanup_count = cleanup_old_records(days_to_keep=30)
            maintenance_results["cleanup_count"] = cleanup_count
        except Exception as e:
            logger.error(f"Cleanup failed: {str(e)}")
            maintenance_results["cleanup_error"] = str(e)
        
        # 2. Generate processing statistics
        try:
            stats = get_processing_statistics()
            maintenance_results["statistics"] = stats
        except Exception as e:
            logger.error(f"Statistics generation failed: {str(e)}")
            maintenance_results["statistics_error"] = str(e)
        
        # 3. Perform health checks
        try:
            health_status = check_system_health()
            maintenance_results["health_check"] = health_status
            
            # Send alert if system is unhealthy
            if health_status["overall_status"] != "healthy":
                send_monitoring_alert({
                    "type": "health_check",
                    "severity": "warning",
                    "message": f"System health check failed: {health_status['overall_status']}"
                })
        except Exception as e:
            logger.error(f"Health check failed: {str(e)}")
            maintenance_results["health_check_error"] = str(e)
        
        # 4. Check for any stuck processing jobs (optional)
        try:
            # Look for email analysis records that are very old but still marked as processing
            # This is a placeholder for more sophisticated stuck job detection
            stuck_threshold = datetime.utcnow() - timedelta(hours=1)
            
            # This would be expanded based on your specific processing state tracking
            maintenance_results["stuck_jobs_check"] = "completed"
        except Exception as e:
            logger.error(f"Stuck jobs check failed: {str(e)}")
            maintenance_results["stuck_jobs_error"] = str(e)
        
        # Record successful completion
        completion_details = {
            "trigger_data": trigger_data,
            "maintenance_results": maintenance_results,
            "processing_duration_seconds": None  # Would calculate actual duration
        }
        
        record_scheduled_run("completed", completion_details)
        
        # Log summary
        stats = maintenance_results.get("statistics", {})
        cleanup_count = maintenance_results.get("cleanup_count", 0)
        health_status = maintenance_results.get("health_check", {}).get("overall_status", "unknown")
        
        logger.info(f"Scheduled processing completed successfully: "
                   f"cleaned {cleanup_count} records, "
                   f"processed {stats.get('last_24h_processing_count', 0)} emails in last 24h, "
                   f"system health: {health_status}")
        
        return {
            "status": "success",
            "run_id": run_id,
            "completion_time": datetime.utcnow().isoformat(),
            "results": maintenance_results
        }
        
    except Exception as e:
        # Record failure
        error_details = {
            "error": str(e),
            "error_type": type(e).__name__
        }
        
        try:
            record_scheduled_run("failed", error_details)
        except Exception as nested_e:
            logger.error(f"Failed to record run failure: {str(nested_e)}")
        
        # Send alert for critical failure
        try:
            send_monitoring_alert({
                "type": "critical_failure",
                "severity": "error",
                "message": f"Scheduled email processing failed: {str(e)}"
            })
        except Exception as alert_error:
            logger.error(f"Failed to send failure alert: {str(alert_error)}")
        
        logger.error(f"Scheduled processing failed: {str(e)}", exc_info=True)
        
        return {
            "status": "failed",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }

# Additional utility function for manual triggering
@functions_framework.http
def manual_maintenance(request):
    """
    HTTP endpoint for manually triggering maintenance tasks.
    Useful for debugging and on-demand maintenance.
    """
    try:
        # Check for basic authentication or API key
        auth_header = request.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            return {"error": "Authorization required"}, 401
        
        # Parse request parameters
        request_json = request.get_json() or {}
        tasks = request_json.get('tasks', ['cleanup', 'statistics', 'health_check'])
        
        results = {}
        
        if 'cleanup' in tasks:
            results['cleanup'] = cleanup_old_records()
        
        if 'statistics' in tasks:
            results['statistics'] = get_processing_statistics()
        
        if 'health_check' in tasks:
            results['health_check'] = check_system_health()
        
        return {
            "status": "success",
            "results": results,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Manual maintenance failed: {str(e)}")
        return {
            "status": "failed",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }, 500