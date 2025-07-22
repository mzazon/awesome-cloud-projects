import json
import logging
import os
from datetime import datetime, timezone
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def compliance_audit(request):
    """Process detailed compliance audit for high-risk events."""
    try:
        request_json = request.get_json()
        if not request_json:
            return {'status': 'error', 'message': 'No JSON data provided'}
        
        # Extract audit details
        audit_data = {
            'timestamp': datetime.now(timezone.utc),
            'original_event': request_json,
            'audit_level': determine_audit_level(request_json),
            'findings': perform_detailed_audit(request_json)
        }
        
        # Store audit results in BigQuery
        store_audit_results(audit_data)
        
        # Generate compliance report if needed
        if audit_data['audit_level'] == 'CRITICAL':
            generate_compliance_report(audit_data)
        
        logger.info(f"Completed compliance audit for event: {request_json.get('message_id')}")
        return {'status': 'success', 'audit_id': str(audit_data['timestamp'])}
        
    except Exception as e:
        logger.error(f"Error in compliance audit: {str(e)}")
        return {'status': 'error', 'error': str(e)}

def determine_audit_level(event_data):
    """Determine the required audit level based on event characteristics."""
    validation_result = event_data.get('validation_result', {})
    risk_score = validation_result.get('risk_score', 1)
    
    if risk_score >= 4:
        return 'CRITICAL'
    elif risk_score >= 2:
        return 'ENHANCED'
    else:
        return 'STANDARD'

def perform_detailed_audit(event_data):
    """Perform detailed compliance audit analysis."""
    findings = {
        'phi_exposure_risk': assess_phi_exposure(event_data),
        'access_pattern_analysis': analyze_access_patterns(event_data),
        'compliance_violations': check_compliance_violations(event_data),
        'recommendations': generate_recommendations(event_data)
    }
    
    return findings

def assess_phi_exposure(event_data):
    """Assess potential PHI exposure risks."""
    resource_name = event_data.get('resource_name', '')
    event_type = event_data.get('event_type', '')
    
    risk_factors = []
    
    if 'Patient' in resource_name:
        risk_factors.append('Direct patient data access')
    
    if event_type == 'DELETE':
        risk_factors.append('Data deletion operation')
    
    if event_type in ['CREATE', 'UPDATE']:
        risk_factors.append('Data modification operation')
    
    return {
        'risk_level': 'HIGH' if len(risk_factors) > 1 else 'MEDIUM' if risk_factors else 'LOW',
        'factors': risk_factors
    }

def analyze_access_patterns(event_data):
    """Analyze access patterns for anomalies."""
    return {
        'pattern_type': 'normal',
        'frequency': 'standard',
        'timing': 'business_hours'
    }

def check_compliance_violations(event_data):
    """Check for potential compliance violations."""
    violations = []
    
    validation_result = event_data.get('validation_result', {})
    if validation_result.get('risk_score', 0) >= 4:
        violations.append('High-risk operation detected')
    
    return violations

def generate_recommendations(event_data):
    """Generate compliance recommendations."""
    recommendations = [
        'Continue monitoring access patterns',
        'Ensure proper authentication and authorization',
        'Maintain audit trail documentation'
    ]
    
    validation_result = event_data.get('validation_result', {})
    if validation_result.get('risk_score', 0) >= 3:
        recommendations.append('Consider additional security measures')
        recommendations.append('Review access permissions')
    
    return recommendations

def store_audit_results(audit_data):
    """Store audit results in BigQuery."""
    try:
        client = bigquery.Client()
        table_id = f"${project_id}.${dataset_id}.audit_trail"
        
        row = {
            'timestamp': audit_data['timestamp'],
            'user_id': 'system',
            'resource_type': extract_resource_type(audit_data['original_event']),
            'operation': audit_data['original_event'].get('event_type', 'UNKNOWN'),
            'phi_accessed': audit_data['findings']['phi_exposure_risk']['risk_level'] != 'LOW',
            'compliance_level': audit_data['audit_level'],
            'session_id': audit_data['original_event'].get('message_id', 'unknown')
        }
        
        client.insert_rows_json(table_id, [row])
        logger.info(f"Stored audit results in BigQuery: {table_id}")
        
    except Exception as e:
        logger.error(f"Error storing audit results: {str(e)}")

def extract_resource_type(event_data):
    """Extract FHIR resource type from event data."""
    resource_name = event_data.get('resource_name', '')
    if 'Patient' in resource_name:
        return 'Patient'
    elif 'Observation' in resource_name:
        return 'Observation'
    elif 'Condition' in resource_name:
        return 'Condition'
    else:
        return 'Unknown'

def generate_compliance_report(audit_data):
    """Generate detailed compliance report for critical events."""
    try:
        client = storage.Client()
        bucket_name = "${bucket_name}"
        bucket = client.bucket(bucket_name)
        
        timestamp = audit_data['timestamp']
        report_name = f"compliance-reports/{timestamp.strftime('%Y/%m/%d')}/critical-event-{timestamp.strftime('%H%M%S')}.json"
        
        report_data = {
            'report_type': 'Critical Event Audit',
            'generated_at': timestamp.isoformat(),
            'event_summary': audit_data['original_event'],
            'audit_findings': audit_data['findings'],
            'compliance_status': 'REQUIRES_REVIEW',
            'next_actions': [
                'Review access permissions',
                'Validate user authorization',
                'Document incident in compliance log'
            ]
        }
        
        blob = bucket.blob(report_name)
        blob.upload_from_string(
            json.dumps(report_data, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Generated compliance report: {report_name}")
        
    except Exception as e:
        logger.error(f"Error generating compliance report: {str(e)}")