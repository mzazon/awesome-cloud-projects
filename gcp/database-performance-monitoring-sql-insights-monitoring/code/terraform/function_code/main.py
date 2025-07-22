# Cloud Function for Database Performance Alert Processing
# This function processes database performance alerts from Cloud Monitoring
# and generates intelligent insights and recommendations

import json
import base64
import os
from google.cloud import storage
from google.cloud import monitoring_v3
from datetime import datetime, timezone
import logging

# Configure logging for Cloud Functions
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_db_alert(event, context):
    """
    Main entry point for processing database performance alerts.
    
    Args:
        event: Pub/Sub event containing alert data
        context: Cloud Functions context object
        
    Returns:
        dict: Status and processing results
    """
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message = base64.b64decode(event['data']).decode('utf-8')
            alert_data = json.loads(message)
        else:
            # Handle direct function invocation for testing
            alert_data = event
        
        logger.info(f"Processing database alert: {alert_data.get('incident', {}).get('condition_name', 'Unknown')}")
        
        # Extract alert information
        incident = alert_data.get('incident', {})
        alert_type = incident.get('condition_name', 'Unknown Alert Type')
        resource_name = incident.get('resource_display_name', 'Unknown Resource')
        state = incident.get('state', 'UNKNOWN')
        policy_name = incident.get('policy_name', 'Unknown Policy')
        started_at = incident.get('started_at', '')
        
        # Generate comprehensive performance report
        report = generate_performance_report(
            alert_type=alert_type,
            resource_name=resource_name,
            state=state,
            policy_name=policy_name,
            started_at=started_at,
            full_alert_data=alert_data
        )
        
        # Store report in Cloud Storage for analysis and auditing
        report_path = store_performance_report(report)
        
        # Log processing completion
        logger.info(f"Successfully processed {alert_type} alert for {resource_name}")
        logger.info(f"Performance report stored at: {report_path}")
        
        return {
            "status": "success",
            "alert_type": alert_type,
            "resource_name": resource_name,
            "report_path": report_path,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error processing database alert: {str(e)}")
        logger.error(f"Event data: {event}")
        return {
            "status": "error",
            "message": str(e),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

def generate_performance_report(alert_type, resource_name, state, policy_name, started_at, full_alert_data):
    """
    Generate detailed performance analysis report with intelligent recommendations.
    
    Args:
        alert_type: Type of the alert condition
        resource_name: Name of the affected resource
        state: Current state of the alert (OPEN, CLOSED)
        policy_name: Name of the alerting policy
        started_at: Timestamp when alert started
        full_alert_data: Complete alert payload for detailed analysis
        
    Returns:
        dict: Comprehensive performance report
    """
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # Generate intelligent recommendations based on alert type
    recommendations = get_intelligent_recommendations(alert_type, full_alert_data)
    
    # Analyze alert severity and impact
    severity_analysis = analyze_alert_severity(alert_type, state, full_alert_data)
    
    # Generate actionable next steps
    next_steps = get_actionable_next_steps(alert_type, state)
    
    report = {
        "timestamp": timestamp,
        "alert_metadata": {
            "alert_type": alert_type,
            "resource_name": resource_name,
            "state": state,
            "policy_name": policy_name,
            "started_at": started_at,
            "processed_at": timestamp
        },
        "severity_analysis": severity_analysis,
        "performance_insights": {
            "primary_cause": get_primary_cause_analysis(alert_type),
            "impact_assessment": get_impact_assessment(alert_type, state),
            "historical_context": get_historical_context(alert_type)
        },
        "recommendations": {
            "immediate_actions": recommendations.get("immediate", []),
            "short_term_optimizations": recommendations.get("short_term", []),
            "long_term_improvements": recommendations.get("long_term", [])
        },
        "next_steps": next_steps,
        "monitoring_links": generate_monitoring_links(resource_name),
        "raw_alert_data": full_alert_data
    }
    
    return report

def get_intelligent_recommendations(alert_type, alert_data):
    """
    Provide intelligent, context-aware recommendations based on alert type and data.
    
    Args:
        alert_type: Type of the alert
        alert_data: Full alert payload for context
        
    Returns:
        dict: Categorized recommendations
    """
    base_recommendations = {
        "CPU utilization is high": {
            "immediate": [
                "Review current active connections and terminate any unnecessary sessions",
                "Check Query Insights for expensive queries running during the alert timeframe",
                "Monitor for potential connection pooling issues or connection leaks"
            ],
            "short_term": [
                "Analyze top queries in Query Insights and optimize execution plans",
                "Review table indexes and add missing indexes for frequently queried columns",
                "Consider implementing query result caching for repeated expensive queries",
                "Evaluate read replica setup for read-heavy workloads"
            ],
            "long_term": [
                "Consider upgrading to a higher CPU tier or machine type",
                "Implement application-level query optimization and caching strategies",
                "Set up automated query performance monitoring and alerting",
                "Design database partitioning strategy for large tables"
            ]
        },
        "Query execution time is high": {
            "immediate": [
                "Identify the specific slow queries using Query Insights dashboard",
                "Check for table locks or deadlocks in the database logs",
                "Review current database connections for blocking queries"
            ],
            "short_term": [
                "Analyze query execution plans and optimize inefficient queries",
                "Review and create missing indexes based on Query Insights recommendations",
                "Implement query timeout policies to prevent runaway queries",
                "Optimize database statistics and consider manual ANALYZE operations"
            ],
            "long_term": [
                "Implement comprehensive query performance monitoring",
                "Design database schema optimizations and normalization improvements",
                "Set up automated index maintenance and statistics updates",
                "Implement query result caching and materialized views where appropriate"
            ]
        },
        "Memory utilization is high": {
            "immediate": [
                "Review current memory usage patterns in Cloud Monitoring",
                "Check for memory-intensive queries or operations",
                "Monitor for potential memory leaks in application connections"
            ],
            "short_term": [
                "Optimize query memory usage and reduce result set sizes",
                "Review and tune database configuration parameters",
                "Implement connection pooling to reduce memory overhead",
                "Analyze and optimize stored procedures and functions"
            ],
            "long_term": [
                "Consider upgrading to higher memory instance types",
                "Implement application-level memory optimization strategies",
                "Design data archiving strategies for historical data",
                "Set up predictive scaling based on memory usage patterns"
            ]
        }
    }
    
    # Return specific recommendations or default generic ones
    return base_recommendations.get(alert_type, {
        "immediate": ["Review the specific alert conditions in Cloud Monitoring"],
        "short_term": ["Analyze performance metrics and trends in Query Insights"],
        "long_term": ["Implement comprehensive database monitoring and optimization strategy"]
    })

def analyze_alert_severity(alert_type, state, alert_data):
    """
    Analyze the severity and business impact of the alert.
    
    Args:
        alert_type: Type of alert
        state: Current alert state
        alert_data: Full alert data for analysis
        
    Returns:
        dict: Severity analysis results
    """
    severity_mapping = {
        "CPU utilization is high": "HIGH",
        "Query execution time is high": "MEDIUM",
        "Memory utilization is high": "HIGH",
        "Disk utilization is high": "MEDIUM",
        "Connection count is high": "MEDIUM"
    }
    
    severity = severity_mapping.get(alert_type, "MEDIUM")
    
    business_impact = {
        "HIGH": "Potential user experience degradation and application slowdowns",
        "MEDIUM": "Performance issues that may affect some operations",
        "LOW": "Minor performance issues with minimal user impact"
    }
    
    return {
        "severity_level": severity,
        "business_impact": business_impact.get(severity, "Requires investigation"),
        "alert_state": state,
        "requires_immediate_attention": severity == "HIGH" and state == "OPEN"
    }

def get_primary_cause_analysis(alert_type):
    """
    Provide primary cause analysis for different alert types.
    
    Args:
        alert_type: Type of the alert
        
    Returns:
        str: Primary cause analysis
    """
    cause_analysis = {
        "CPU utilization is high": "High CPU usage typically indicates expensive query operations, insufficient indexing, or increased query volume. Review Query Insights for resource-intensive operations.",
        "Query execution time is high": "Slow queries often result from missing indexes, inefficient query plans, table locks, or large dataset operations without proper optimization.",
        "Memory utilization is high": "High memory usage may indicate large result sets, memory leaks in connections, or inefficient memory allocation in query operations.",
        "Disk utilization is high": "High disk usage could be due to large table scans, temporary file creation for sorting operations, or inadequate storage provisioning.",
        "Connection count is high": "High connection counts often indicate connection pooling issues, application connection leaks, or unexpected traffic spikes."
    }
    
    return cause_analysis.get(alert_type, "Requires detailed investigation to determine the root cause.")

def get_impact_assessment(alert_type, state):
    """
    Assess the potential impact of the alert on application performance.
    
    Args:
        alert_type: Type of alert
        state: Current alert state
        
    Returns:
        str: Impact assessment
    """
    if state == "CLOSED":
        return "Alert has been resolved. Monitor for recurrence and implement preventive measures."
    
    impact_assessments = {
        "CPU utilization is high": "May cause query timeouts, increased response times, and potential application instability if sustained.",
        "Query execution time is high": "Will result in slower application responses, potential user experience degradation, and increased resource consumption.",
        "Memory utilization is high": "Could lead to query failures, connection issues, and potential database instability.",
        "Disk utilization is high": "May cause slower I/O operations, increased query latency, and potential storage exhaustion.",
        "Connection count is high": "Could result in connection rejections, application errors, and degraded database performance."
    }
    
    return impact_assessments.get(alert_type, "Requires monitoring to assess full impact on application performance.")

def get_historical_context(alert_type):
    """
    Provide historical context and pattern analysis for the alert.
    
    Args:
        alert_type: Type of alert
        
    Returns:
        str: Historical context information
    """
    return f"Review historical patterns for {alert_type} alerts in Cloud Monitoring to identify trends, peak usage times, and correlation with application deployments or traffic patterns."

def get_actionable_next_steps(alert_type, state):
    """
    Generate specific, actionable next steps based on alert type and state.
    
    Args:
        alert_type: Type of alert
        state: Current alert state
        
    Returns:
        list: Actionable next steps
    """
    if state == "CLOSED":
        return [
            "Review the resolution timeline and identify what resolved the issue",
            "Implement monitoring to prevent recurrence",
            "Document lessons learned and update runbooks",
            "Consider implementing automated remediation for similar future alerts"
        ]
    
    next_steps_mapping = {
        "CPU utilization is high": [
            "Access Query Insights dashboard to identify top CPU-consuming queries",
            "Review active connections and query execution plans",
            "Check for any recent application deployments or traffic changes",
            "Consider temporary load balancing or read replica scaling if available"
        ],
        "Query execution time is high": [
            "Navigate to Query Insights to examine slow query details and execution plans",
            "Review recent query pattern changes and identify outliers",
            "Check database logs for any lock waits or deadlock information",
            "Analyze index usage and identify optimization opportunities"
        ]
    }
    
    return next_steps_mapping.get(alert_type, [
        "Review specific alert conditions in Cloud Monitoring",
        "Examine relevant performance metrics and trends",
        "Correlate with any recent changes or events",
        "Implement monitoring and preventive measures"
    ])

def generate_monitoring_links(resource_name):
    """
    Generate relevant monitoring and debugging links.
    
    Args:
        resource_name: Name of the affected resource
        
    Returns:
        dict: Monitoring and debugging links
    """
    project_id = os.environ.get('PROJECT_ID', 'your-project-id')
    
    return {
        "query_insights": f"https://console.cloud.google.com/sql/instances/{resource_name}/insights?project={project_id}",
        "cloud_monitoring": f"https://console.cloud.google.com/monitoring?project={project_id}",
        "database_overview": f"https://console.cloud.google.com/sql/instances/{resource_name}/overview?project={project_id}",
        "logs_explorer": f"https://console.cloud.google.com/logs/query?project={project_id}"
    }

def store_performance_report(report):
    """
    Store the performance report in Cloud Storage for analysis and auditing.
    
    Args:
        report: Performance report dictionary
        
    Returns:
        str: Storage path of the report
    """
    try:
        # Initialize Cloud Storage client
        storage_client = storage.Client()
        bucket_name = os.environ.get('BUCKET_NAME', '${bucket_name}')
        bucket = storage_client.bucket(bucket_name)
        
        # Generate filename with timestamp and alert type
        timestamp = report['timestamp'].replace(':', '-').replace('.', '-')
        alert_type_safe = report['alert_metadata']['alert_type'].replace(' ', '-').replace('/', '-')
        filename = f"performance-reports/{timestamp}-{alert_type_safe}.json"
        
        # Create blob and upload report
        blob = bucket.blob(filename)
        blob.upload_from_string(
            json.dumps(report, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        # Set metadata for better organization
        metadata = {
            'alert-type': report['alert_metadata']['alert_type'],
            'resource-name': report['alert_metadata']['resource_name'],
            'alert-state': report['alert_metadata']['state'],
            'generated-by': 'database-performance-monitor'
        }
        blob.metadata = metadata
        blob.patch()
        
        storage_path = f"gs://{bucket_name}/{filename}"
        logger.info(f"Performance report stored successfully: {storage_path}")
        
        return storage_path
        
    except Exception as e:
        logger.warning(f"Failed to store performance report: {str(e)}")
        # Don't fail the entire function if storage fails
        return "storage-failed"

# Additional helper functions for testing and debugging
def test_alert_processing():
    """
    Test function for local development and debugging.
    Can be called directly for testing alert processing logic.
    """
    sample_alert = {
        "incident": {
            "condition_name": "CPU utilization is high",
            "resource_display_name": "test-database",
            "state": "OPEN",
            "policy_name": "High CPU Alert Policy",
            "started_at": "2025-01-12T10:00:00Z"
        }
    }
    
    return process_db_alert(sample_alert, None)

if __name__ == "__main__":
    # Allow for local testing
    test_result = test_alert_processing()
    print(json.dumps(test_result, indent=2))