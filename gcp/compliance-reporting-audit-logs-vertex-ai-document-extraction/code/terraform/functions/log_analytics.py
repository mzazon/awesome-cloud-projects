"""
Cloud Function for analyzing compliance logs and generating insights
Processes audit logs to identify compliance violations and security patterns
"""

import json
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from google.cloud import logging
from google.cloud import storage
import functions_framework


# Initialize clients
logging_client = logging.Client()
storage_client = storage.Client()
logger = logging_client.logger("compliance-log-analytics")

# Environment variables
COMPLIANCE_BUCKET = os.environ.get('COMPLIANCE_BUCKET', '${compliance_bucket}')


@functions_framework.http
def analyze_compliance_logs(request) -> Dict[str, Any]:
    """
    Analyze audit logs for compliance violations and patterns
    
    This function performs comprehensive analysis of Cloud Audit Logs to:
    - Identify potential compliance violations
    - Detect unusual access patterns
    - Generate security insights
    - Track administrative activities
    
    Args:
        request: HTTP request containing analysis parameters
        
    Returns:
        Dictionary with analysis results and insights
    """
    try:
        # Parse request parameters
        request_json = request.get_json(silent=True) or {}
        analysis_type = request_json.get('analysis_type', 'daily')
        
        logger.log_text(f"Starting compliance log analysis - Type: {analysis_type}")
        
        # Define analysis timeframe
        end_time = datetime.utcnow()
        if analysis_type == 'daily':
            start_time = end_time - timedelta(days=1)
        elif analysis_type == 'weekly':
            start_time = end_time - timedelta(days=7)
        elif analysis_type == 'monthly':
            start_time = end_time - timedelta(days=30)
        else:
            start_time = end_time - timedelta(hours=24)
        
        # Perform compliance analysis
        compliance_insights = _analyze_compliance_patterns(start_time, end_time)
        security_analysis = _analyze_security_events(start_time, end_time)
        access_patterns = _analyze_access_patterns(start_time, end_time)
        administrative_activity = _analyze_admin_activity(start_time, end_time)
        
        # Compile analysis results
        analysis_results = {
            "analysis_metadata": {
                "analysis_id": f"LOG-{end_time.strftime('%Y%m%d-%H%M%S')}",
                "analysis_date": end_time.isoformat() + "Z",
                "analysis_type": analysis_type,
                "time_range": {
                    "start_time": start_time.isoformat() + "Z",
                    "end_time": end_time.isoformat() + "Z"
                }
            },
            "compliance_insights": compliance_insights,
            "security_analysis": security_analysis,
            "access_patterns": access_patterns,
            "administrative_activity": administrative_activity,
            "overall_assessment": _generate_overall_assessment(
                compliance_insights, security_analysis, access_patterns, administrative_activity
            )
        }
        
        # Save analysis results
        results_path = _save_analysis_results(analysis_results)
        
        logger.log_text(f"Compliance log analysis completed successfully: {results_path}")
        
        return {
            "status": "success",
            "analysis_type": analysis_type,
            "results_path": results_path,
            "insights_generated": len(compliance_insights),
            "security_events": len(security_analysis.get("events", [])),
            "assessment": analysis_results["overall_assessment"]["compliance_status"]
        }
        
    except Exception as e:
        error_message = f"Error analyzing compliance logs: {str(e)}"
        logger.log_text(error_message, severity="ERROR")
        return {
            "status": "error",
            "message": error_message,
            "timestamp": datetime.utcnow().isoformat()
        }


def _analyze_compliance_patterns(start_time: datetime, end_time: datetime) -> List[Dict[str, Any]]:
    """Analyze logs for compliance-related patterns and violations"""
    compliance_queries = [
        {
            "name": "IAM Policy Changes",
            "filter": 'protoPayload.serviceName="iam.googleapis.com" AND protoPayload.methodName="SetIamPolicy"',
            "description": "IAM policy changes for access control compliance",
            "compliance_framework": ["SOC2", "ISO27001"],
            "severity": "HIGH"
        },
        {
            "name": "Data Access Events",
            "filter": 'protoPayload.serviceName="storage.googleapis.com" AND protoPayload.methodName="storage.objects.get"',
            "description": "Data access patterns for privacy compliance",
            "compliance_framework": ["HIPAA", "GDPR"],
            "severity": "MEDIUM"
        },
        {
            "name": "Failed Authentication Attempts",
            "filter": 'protoPayload.authenticationInfo.principalEmail!="" AND httpRequest.status>=400',
            "description": "Failed authentication attempts for security monitoring",
            "compliance_framework": ["SOC2", "ISO27001"],
            "severity": "HIGH"
        },
        {
            "name": "Administrative Actions",
            "filter": 'protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName:("insert" OR "delete" OR "update")',
            "description": "Administrative actions on compute resources",
            "compliance_framework": ["SOC2"],
            "severity": "MEDIUM"
        },
        {
            "name": "Document AI Processing",
            "filter": 'protoPayload.serviceName="documentai.googleapis.com"',
            "description": "Document AI processing activities for compliance tracking",
            "compliance_framework": ["HIPAA", "GDPR"],
            "severity": "LOW"
        },
        {
            "name": "KMS Key Usage",
            "filter": 'protoPayload.serviceName="cloudkms.googleapis.com" AND protoPayload.methodName:("Encrypt" OR "Decrypt")',
            "description": "Encryption key usage for data protection compliance",
            "compliance_framework": ["SOC2", "ISO27001", "HIPAA"],
            "severity": "MEDIUM"
        }
    ]
    
    insights = []
    
    for query in compliance_queries:
        try:
            # Add time filter to the query
            time_filter = f'timestamp>="{start_time.isoformat()}Z" AND timestamp<="{end_time.isoformat()}Z"'
            full_filter = f'{query["filter"]} AND {time_filter}'
            
            # Execute the query
            entries = list(logging_client.list_entries(
                filter_=full_filter,
                order_by=logging.DESCENDING,
                page_size=1000
            ))
            
            event_count = len(entries)
            
            # Analyze the events
            analysis = _analyze_query_results(query, entries)
            
            insight = {
                "category": query["name"],
                "description": query["description"],
                "compliance_frameworks": query["compliance_framework"],
                "severity": query["severity"],
                "event_count": event_count,
                "analysis": analysis,
                "compliance_status": _determine_compliance_status(query, event_count, analysis),
                "recommendations": _generate_query_recommendations(query, event_count, analysis)
            }
            
            insights.append(insight)
            
        except Exception as e:
            logger.log_text(f"Error analyzing query '{query['name']}': {str(e)}")
            insights.append({
                "category": query["name"],
                "error": str(e),
                "compliance_status": "ERROR"
            })
    
    return insights


def _analyze_query_results(query: Dict[str, Any], entries: List[Any]) -> Dict[str, Any]:
    """Analyze the results of a compliance query"""
    analysis = {
        "unique_users": set(),
        "unique_resources": set(),
        "time_distribution": {},
        "success_count": 0,
        "error_count": 0,
        "unusual_patterns": []
    }
    
    for entry in entries:
        try:
            # Extract user information
            if hasattr(entry, 'payload') and hasattr(entry.payload, 'authenticationInfo'):
                principal_email = getattr(entry.payload.authenticationInfo, 'principalEmail', '')
                if principal_email:
                    analysis["unique_users"].add(principal_email)
            
            # Extract resource information
            if hasattr(entry, 'payload') and hasattr(entry.payload, 'resourceName'):
                resource_name = getattr(entry.payload, 'resourceName', '')
                if resource_name:
                    analysis["unique_resources"].add(resource_name)
            
            # Analyze HTTP status codes
            if hasattr(entry, 'http_request') and hasattr(entry.http_request, 'status'):
                status = entry.http_request.status
                if 200 <= status < 300:
                    analysis["success_count"] += 1
                else:
                    analysis["error_count"] += 1
            else:
                analysis["success_count"] += 1  # Assume success if no HTTP status
            
            # Time distribution analysis
            if hasattr(entry, 'timestamp'):
                hour = entry.timestamp.hour
                analysis["time_distribution"][hour] = analysis["time_distribution"].get(hour, 0) + 1
        
        except Exception as e:
            logger.log_text(f"Error analyzing entry: {str(e)}")
            continue
    
    # Convert sets to counts for JSON serialization
    analysis["unique_users"] = len(analysis["unique_users"])
    analysis["unique_resources"] = len(analysis["unique_resources"])
    
    # Detect unusual patterns
    analysis["unusual_patterns"] = _detect_unusual_patterns(analysis, query)
    
    return analysis


def _detect_unusual_patterns(analysis: Dict[str, Any], query: Dict[str, Any]) -> List[str]:
    """Detect unusual patterns in the analysis results"""
    patterns = []
    
    # High error rate
    total_events = analysis["success_count"] + analysis["error_count"]
    if total_events > 0:
        error_rate = analysis["error_count"] / total_events
        if error_rate > 0.1:  # More than 10% errors
            patterns.append(f"High error rate detected: {error_rate:.1%}")
    
    # Unusual time distribution (activity outside business hours)
    time_dist = analysis["time_distribution"]
    if time_dist:
        # Check for activity during off-hours (assuming UTC, adjust as needed)
        off_hours_activity = sum(count for hour, count in time_dist.items() if hour < 6 or hour > 22)
        total_activity = sum(time_dist.values())
        if off_hours_activity > total_activity * 0.3:  # More than 30% off-hours
            patterns.append(f"Significant off-hours activity: {off_hours_activity/total_activity:.1%}")
    
    # High volume of events
    if total_events > 1000:
        patterns.append(f"High volume of events: {total_events}")
    
    # Single user responsible for many events
    if analysis["unique_users"] == 1 and total_events > 100:
        patterns.append("Single user responsible for high volume of events")
    
    return patterns


def _determine_compliance_status(query: Dict[str, Any], event_count: int, analysis: Dict[str, Any]) -> str:
    """Determine compliance status based on query results"""
    # If there are errors or unusual patterns, flag for review
    if analysis["error_count"] > 0 or analysis["unusual_patterns"]:
        return "REVIEW_REQUIRED"
    
    # Framework-specific thresholds
    if query["severity"] == "HIGH":
        if event_count > 100:
            return "REVIEW_REQUIRED"
        elif event_count > 0:
            return "MONITOR"
        else:
            return "NORMAL"
    else:
        if event_count > 1000:
            return "REVIEW_REQUIRED"
        else:
            return "NORMAL"


def _generate_query_recommendations(query: Dict[str, Any], event_count: int, analysis: Dict[str, Any]) -> List[str]:
    """Generate recommendations based on query analysis"""
    recommendations = []
    
    # Error-based recommendations
    if analysis["error_count"] > 0:
        recommendations.append(f"Investigate {analysis['error_count']} failed events")
    
    # Pattern-based recommendations
    for pattern in analysis["unusual_patterns"]:
        if "High error rate" in pattern:
            recommendations.append("Review authentication and authorization configurations")
        elif "off-hours activity" in pattern:
            recommendations.append("Review off-hours access policies and monitoring")
        elif "High volume" in pattern:
            recommendations.append("Verify if high activity volume is expected")
        elif "Single user" in pattern:
            recommendations.append("Review user permissions and activity patterns")
    
    # Query-specific recommendations
    if query["name"] == "IAM Policy Changes" and event_count > 0:
        recommendations.append("Review all IAM policy changes for appropriateness")
    elif query["name"] == "Failed Authentication Attempts" and event_count > 10:
        recommendations.append("Consider implementing additional security measures")
    
    return recommendations


def _analyze_security_events(start_time: datetime, end_time: datetime) -> Dict[str, Any]:
    """Analyze security-related events in the logs"""
    security_analysis = {
        "events": [],
        "threat_indicators": [],
        "security_metrics": {
            "failed_authentications": 0,
            "privilege_escalations": 0,
            "data_exfiltration_indicators": 0,
            "unusual_access_patterns": 0
        }
    }
    
    # Define security-focused queries
    security_queries = [
        {
            "name": "Multiple Failed Authentications",
            "filter": f'httpRequest.status>=400 AND timestamp>="{start_time.isoformat()}Z" AND timestamp<="{end_time.isoformat()}Z"',
            "threat_type": "BRUTE_FORCE"
        },
        {
            "name": "Privilege Escalation Attempts",
            "filter": f'protoPayload.methodName="SetIamPolicy" AND timestamp>="{start_time.isoformat()}Z" AND timestamp<="{end_time.isoformat()}Z"',
            "threat_type": "PRIVILEGE_ESCALATION"
        }
    ]
    
    for query in security_queries:
        try:
            entries = list(logging_client.list_entries(
                filter_=query["filter"],
                order_by=logging.DESCENDING,
                page_size=100
            ))
            
            for entry in entries:
                event = {
                    "timestamp": entry.timestamp.isoformat() if hasattr(entry, 'timestamp') else None,
                    "threat_type": query["threat_type"],
                    "source_ip": getattr(entry.http_request, 'remoteIp', 'Unknown') if hasattr(entry, 'http_request') else 'Unknown',
                    "user_agent": getattr(entry.http_request, 'userAgent', 'Unknown') if hasattr(entry, 'http_request') else 'Unknown',
                    "principal": getattr(entry.payload.authenticationInfo, 'principalEmail', 'Unknown') if hasattr(entry, 'payload') and hasattr(entry.payload, 'authenticationInfo') else 'Unknown'
                }
                security_analysis["events"].append(event)
                
                # Update security metrics
                if query["threat_type"] == "BRUTE_FORCE":
                    security_analysis["security_metrics"]["failed_authentications"] += 1
                elif query["threat_type"] == "PRIVILEGE_ESCALATION":
                    security_analysis["security_metrics"]["privilege_escalations"] += 1
        
        except Exception as e:
            logger.log_text(f"Error in security analysis for {query['name']}: {str(e)}")
    
    return security_analysis


def _analyze_access_patterns(start_time: datetime, end_time: datetime) -> Dict[str, Any]:
    """Analyze access patterns for compliance monitoring"""
    access_analysis = {
        "data_access_summary": {
            "total_access_events": 0,
            "unique_users": 0,
            "unique_resources": 0,
            "peak_access_hour": None
        },
        "compliance_relevant_access": [],
        "recommendations": []
    }
    
    try:
        # Query for data access events
        access_filter = f'protoPayload.serviceName="storage.googleapis.com" AND timestamp>="{start_time.isoformat()}Z" AND timestamp<="{end_time.isoformat()}Z"'
        
        entries = list(logging_client.list_entries(
            filter_=access_filter,
            order_by=logging.DESCENDING,
            page_size=1000
        ))
        
        users = set()
        resources = set()
        hourly_distribution = {}
        
        for entry in entries:
            # Extract user information
            if hasattr(entry, 'payload') and hasattr(entry.payload, 'authenticationInfo'):
                principal = getattr(entry.payload.authenticationInfo, 'principalEmail', '')
                if principal:
                    users.add(principal)
            
            # Extract resource information
            if hasattr(entry, 'payload') and hasattr(entry.payload, 'resourceName'):
                resource = getattr(entry.payload, 'resourceName', '')
                if resource:
                    resources.add(resource)
            
            # Time distribution
            if hasattr(entry, 'timestamp'):
                hour = entry.timestamp.hour
                hourly_distribution[hour] = hourly_distribution.get(hour, 0) + 1
        
        access_analysis["data_access_summary"].update({
            "total_access_events": len(entries),
            "unique_users": len(users),
            "unique_resources": len(resources),
            "peak_access_hour": max(hourly_distribution.items(), key=lambda x: x[1])[0] if hourly_distribution else None
        })
        
        # Generate recommendations based on access patterns
        if len(entries) > 10000:
            access_analysis["recommendations"].append("High volume of data access detected - review access policies")
        
        if len(users) > 100:
            access_analysis["recommendations"].append("Large number of users accessing data - verify access controls")
    
    except Exception as e:
        logger.log_text(f"Error in access pattern analysis: {str(e)}")
        access_analysis["error"] = str(e)
    
    return access_analysis


def _analyze_admin_activity(start_time: datetime, end_time: datetime) -> Dict[str, Any]:
    """Analyze administrative activity for compliance oversight"""
    admin_analysis = {
        "activity_summary": {
            "total_admin_actions": 0,
            "unique_administrators": 0,
            "services_modified": set(),
            "critical_changes": 0
        },
        "critical_activities": [],
        "compliance_notes": []
    }
    
    try:
        # Query for administrative activities
        admin_filter = f'protoPayload.methodName:("create" OR "delete" OR "update" OR "insert") AND timestamp>="{start_time.isoformat()}Z" AND timestamp<="{end_time.isoformat()}Z"'
        
        entries = list(logging_client.list_entries(
            filter_=admin_filter,
            order_by=logging.DESCENDING,
            page_size=500
        ))
        
        administrators = set()
        services = set()
        critical_actions = []
        
        for entry in entries:
            # Extract administrator information
            if hasattr(entry, 'payload') and hasattr(entry.payload, 'authenticationInfo'):
                principal = getattr(entry.payload.authenticationInfo, 'principalEmail', '')
                if principal:
                    administrators.add(principal)
            
            # Extract service information
            if hasattr(entry, 'payload') and hasattr(entry.payload, 'serviceName'):
                service = getattr(entry.payload, 'serviceName', '')
                if service:
                    services.add(service)
            
            # Identify critical activities
            if hasattr(entry, 'payload') and hasattr(entry.payload, 'methodName'):
                method = getattr(entry.payload, 'methodName', '')
                if any(critical in method.lower() for critical in ['delete', 'destroy', 'setiampolicy']):
                    critical_actions.append({
                        "timestamp": entry.timestamp.isoformat() if hasattr(entry, 'timestamp') else None,
                        "method": method,
                        "service": getattr(entry.payload, 'serviceName', 'Unknown'),
                        "principal": getattr(entry.payload.authenticationInfo, 'principalEmail', 'Unknown') if hasattr(entry.payload, 'authenticationInfo') else 'Unknown'
                    })
        
        admin_analysis["activity_summary"].update({
            "total_admin_actions": len(entries),
            "unique_administrators": len(administrators),
            "services_modified": list(services),
            "critical_changes": len(critical_actions)
        })
        
        admin_analysis["critical_activities"] = critical_actions
        
        # Generate compliance notes
        if len(critical_actions) > 0:
            admin_analysis["compliance_notes"].append(f"{len(critical_actions)} critical administrative actions require review")
        
        if len(administrators) > 20:
            admin_analysis["compliance_notes"].append("Large number of administrators active - review access controls")
    
    except Exception as e:
        logger.log_text(f"Error in admin activity analysis: {str(e)}")
        admin_analysis["error"] = str(e)
    
    return admin_analysis


def _generate_overall_assessment(
    compliance_insights: List[Dict[str, Any]],
    security_analysis: Dict[str, Any],
    access_patterns: Dict[str, Any],
    admin_activity: Dict[str, Any]
) -> Dict[str, Any]:
    """Generate overall compliance assessment based on all analyses"""
    
    # Count issues by severity
    high_priority_issues = 0
    medium_priority_issues = 0
    
    for insight in compliance_insights:
        if insight.get("compliance_status") == "REVIEW_REQUIRED":
            if insight.get("severity") == "HIGH":
                high_priority_issues += 1
            else:
                medium_priority_issues += 1
    
    # Security assessment
    security_events_count = len(security_analysis.get("events", []))
    
    # Determine overall status
    if high_priority_issues > 5 or security_events_count > 10:
        compliance_status = "NON_COMPLIANT"
    elif high_priority_issues > 0 or medium_priority_issues > 3:
        compliance_status = "REQUIRES_ATTENTION"
    else:
        compliance_status = "COMPLIANT"
    
    assessment = {
        "compliance_status": compliance_status,
        "risk_level": _calculate_risk_level(high_priority_issues, security_events_count),
        "summary_statistics": {
            "high_priority_issues": high_priority_issues,
            "medium_priority_issues": medium_priority_issues,
            "security_events": security_events_count,
            "total_insights": len(compliance_insights)
        },
        "key_recommendations": _generate_key_recommendations(
            compliance_insights, security_analysis, access_patterns, admin_activity
        )
    }
    
    return assessment


def _calculate_risk_level(high_priority_issues: int, security_events: int) -> str:
    """Calculate overall risk level based on issues found"""
    risk_score = (high_priority_issues * 3) + (security_events * 2)
    
    if risk_score >= 20:
        return "HIGH"
    elif risk_score >= 10:
        return "MEDIUM"
    else:
        return "LOW"


def _generate_key_recommendations(
    compliance_insights: List[Dict[str, Any]],
    security_analysis: Dict[str, Any],
    access_patterns: Dict[str, Any],
    admin_activity: Dict[str, Any]
) -> List[str]:
    """Generate top recommendations based on all analyses"""
    recommendations = []
    
    # From compliance insights
    for insight in compliance_insights:
        if insight.get("compliance_status") == "REVIEW_REQUIRED":
            recommendations.extend(insight.get("recommendations", []))
    
    # From security analysis
    if len(security_analysis.get("events", [])) > 0:
        recommendations.append("Review security events and implement additional monitoring")
    
    # From access patterns
    recommendations.extend(access_patterns.get("recommendations", []))
    
    # From admin activity
    recommendations.extend(admin_activity.get("compliance_notes", []))
    
    # Return top 10 unique recommendations
    unique_recommendations = list(set(recommendations))
    return unique_recommendations[:10]


def _save_analysis_results(analysis_results: Dict[str, Any]) -> str:
    """Save analysis results to storage for compliance reporting"""
    try:
        bucket = storage_client.bucket(COMPLIANCE_BUCKET)
        
        # Create filename with timestamp
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        filename = f"analytics/compliance-analytics-{timestamp}.json"
        
        # Save results
        blob = bucket.blob(filename)
        blob.upload_from_string(
            json.dumps(analysis_results, indent=2, ensure_ascii=False, default=str),
            content_type='application/json'
        )
        
        logger.log_text(f"Saved analysis results to: {filename}")
        return filename
        
    except Exception as e:
        logger.log_text(f"Error saving analysis results: {str(e)}", severity="ERROR")
        raise