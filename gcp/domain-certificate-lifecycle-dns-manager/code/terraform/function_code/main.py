"""
Certificate and DNS Management Cloud Functions
Recipe: Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager

This module contains Cloud Functions for automated certificate monitoring and DNS management.
"""

import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

from google.cloud import certificatemanager_v1
from google.cloud import dns
from google.cloud import monitoring_v3
from google.cloud import secretmanager
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Project configuration from template variables
PROJECT_ID = "${project_id}"


@functions_framework.http
def check_certificates(request):
    """
    Monitor certificate status and handle lifecycle events.
    
    This function checks the status of all Certificate Manager certificates,
    writes metrics to Cloud Monitoring, and logs any issues.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with certificate status information
    """
    try:
        project_id = os.environ.get('GCP_PROJECT', PROJECT_ID)
        
        # Initialize clients
        cert_client = certificatemanager_v1.CertificateManagerClient()
        monitoring_client = monitoring_v3.MetricServiceClient()
        
        # List all certificates in the global location
        location = f"projects/{project_id}/locations/global"
        certificates = cert_client.list_certificates(parent=location)
        
        results = []
        healthy_certs = 0
        unhealthy_certs = 0
        
        for cert in certificates:
            cert_info = {
                'name': cert.name,
                'domains': list(cert.managed.domains) if cert.managed else [],
                'state': cert.managed.state.name if cert.managed else 'UNKNOWN',
                'provisioning_issue': None,
                'certificate_type': 'MANAGED' if cert.managed else 'SELF_MANAGED'
            }
            
            # Check for provisioning issues
            if cert.managed and cert.managed.provisioning_issue:
                cert_info['provisioning_issue'] = {
                    'reason': cert.managed.provisioning_issue.reason,
                    'details': cert.managed.provisioning_issue.details
                }
            
            # Determine certificate health
            is_healthy = False
            if cert.managed:
                if cert.managed.state == certificatemanager_v1.Certificate.ManagedCertificate.State.ACTIVE:
                    is_healthy = True
                    healthy_certs += 1
                    logger.info(f"Certificate {cert.name} is active and healthy")
                else:
                    unhealthy_certs += 1
                    logger.warning(f"Certificate {cert.name} state: {cert.managed.state.name}")
                    if cert.managed.provisioning_issue:
                        logger.error(f"Certificate {cert.name} provisioning issue: {cert.managed.provisioning_issue.reason}")
            
            # Write certificate status metric
            write_metric(
                monitoring_client, 
                project_id, 
                'certificate_status', 
                1 if is_healthy else 0, 
                cert.name,
                {'certificate_name': cert.name.split('/')[-1]}
            )
            
            cert_info['healthy'] = is_healthy
            results.append(cert_info)
        
        # Write summary metrics
        write_metric(monitoring_client, project_id, 'certificates_healthy_total', healthy_certs, 'summary')
        write_metric(monitoring_client, project_id, 'certificates_unhealthy_total', unhealthy_certs, 'summary')
        
        response_data = {
            'status': 'success',
            'timestamp': datetime.utcnow().isoformat(),
            'certificates_checked': len(results),
            'healthy_certificates': healthy_certs,
            'unhealthy_certificates': unhealthy_certs,
            'certificates': results
        }
        
        logger.info(f"Certificate check completed: {healthy_certs} healthy, {unhealthy_certs} unhealthy")
        return response_data
        
    except Exception as e:
        error_msg = f"Certificate check failed: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return {'status': 'error', 'message': error_msg, 'timestamp': datetime.utcnow().isoformat()}, 500


@functions_framework.http
def update_dns_record(request):
    """
    Update DNS records for certificate validation or domain changes.
    
    This function creates or updates DNS records in Cloud DNS zones.
    
    Args:
        request: HTTP request object with JSON payload containing:
            - zone_name: Name of the DNS zone
            - record_name: Full DNS record name (with trailing dot)
            - record_type: DNS record type (A, AAAA, CNAME, TXT, etc.)
            - record_data: Record data (IP address, domain name, etc.)
            - ttl: Time to live in seconds (optional, default 300)
            
    Returns:
        JSON response with DNS update status
    """
    try:
        # Parse request JSON
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Invalid JSON payload', 'timestamp': datetime.utcnow().isoformat()}, 400
            
        project_id = os.environ.get('GCP_PROJECT', PROJECT_ID)
        zone_name = request_json.get('zone_name')
        record_name = request_json.get('record_name')
        record_type = request_json.get('record_type', 'A').upper()
        record_data = request_json.get('record_data')
        ttl = request_json.get('ttl', 300)
        
        # Validate required parameters
        if not all([zone_name, record_name, record_data]):
            return {
                'error': 'Missing required parameters: zone_name, record_name, record_data',
                'timestamp': datetime.utcnow().isoformat()
            }, 400
        
        # Ensure record_name ends with a dot
        if not record_name.endswith('.'):
            record_name += '.'
        
        # Validate TTL
        if not isinstance(ttl, int) or ttl < 30 or ttl > 86400:
            return {
                'error': 'TTL must be an integer between 30 and 86400 seconds',
                'timestamp': datetime.utcnow().isoformat()
            }, 400
        
        # Initialize DNS client and get zone
        dns_client = dns.Client(project=project_id)
        
        try:
            zone = dns_client.zone(zone_name)
            zone.reload()  # Ensure zone exists
        except Exception as e:
            return {
                'error': f'DNS zone not found: {zone_name}',
                'details': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }, 404
        
        # Prepare record data as list
        if isinstance(record_data, str):
            record_data_list = [record_data]
        elif isinstance(record_data, list):
            record_data_list = record_data
        else:
            return {
                'error': 'record_data must be a string or list of strings',
                'timestamp': datetime.utcnow().isoformat()
            }, 400
        
        # Create DNS changes batch
        changes = zone.changes()
        
        # Check if record already exists and remove it
        existing_records = list(zone.list_resource_record_sets(name=record_name, type_=record_type))
        if existing_records:
            for existing_record in existing_records:
                changes.delete_record_set(existing_record)
            logger.info(f"Existing record found, updating: {record_name} {record_type}")
        else:
            logger.info(f"Creating new record: {record_name} {record_type}")
        
        # Create new record
        record_set = zone.resource_record_set(record_name, record_type, ttl, record_data_list)
        changes.add_record_set(record_set)
        
        # Apply changes
        changes.create()
        
        # Wait for changes to complete
        max_wait_time = 60  # Maximum wait time in seconds
        wait_start = datetime.utcnow()
        
        while changes.status != 'done':
            if (datetime.utcnow() - wait_start).total_seconds() > max_wait_time:
                logger.warning(f"DNS change still in progress after {max_wait_time} seconds")
                break
            
            changes.reload()
            if changes.status != 'done':
                import time
                time.sleep(2)
        
        response_data = {
            'status': 'success',
            'message': f'DNS record {record_name} {record_type} updated successfully',
            'record_name': record_name,
            'record_type': record_type,
            'record_data': record_data_list,
            'ttl': ttl,
            'change_status': changes.status,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        logger.info(f"DNS record updated: {record_name} {record_type} -> {record_data_list}")
        return response_data
        
    except Exception as e:
        error_msg = f"DNS update failed: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return {
            'status': 'error', 
            'message': error_msg,
            'timestamp': datetime.utcnow().isoformat()
        }, 500


def write_metric(client: monitoring_v3.MetricServiceClient, 
                project_id: str, 
                metric_type: str, 
                value: int, 
                resource_name: str,
                additional_labels: Optional[Dict[str, str]] = None) -> None:
    """
    Write custom metric to Cloud Monitoring.
    
    Args:
        client: Cloud Monitoring client
        project_id: GCP project ID
        metric_type: Type of metric to write
        value: Metric value
        resource_name: Name of the resource being monitored
        additional_labels: Additional labels for the metric
    """
    try:
        project_name = f"projects/{project_id}"
        
        # Create time series
        series = monitoring_v3.TimeSeries()
        series.metric.type = f"custom.googleapis.com/certificate_automation/{metric_type}"
        series.resource.type = "global"
        series.resource.labels["project_id"] = project_id
        
        # Add metric labels
        if additional_labels:
            for key, label_value in additional_labels.items():
                series.metric.labels[key] = label_value
        
        series.metric.labels["resource_name"] = resource_name
        
        # Create data point
        point = monitoring_v3.Point()
        point.value.int64_value = value
        point.interval.end_time.seconds = int(datetime.utcnow().timestamp())
        series.points = [point]
        
        # Write to Cloud Monitoring
        client.create_time_series(name=project_name, time_series=[series])
        logger.debug(f"Metric written: {metric_type} = {value} for {resource_name}")
        
    except Exception as e:
        logger.error(f"Failed to write metric {metric_type}: {str(e)}")


def get_certificate_expiry_days(cert_info: Dict[str, Any]) -> Optional[int]:
    """
    Calculate days until certificate expiration.
    
    Args:
        cert_info: Certificate information dictionary
        
    Returns:
        Number of days until expiration, or None if not available
    """
    try:
        # This would require additional Certificate Manager API calls
        # to get detailed certificate information including expiry
        # For now, return None as this is a placeholder for future enhancement
        return None
    except Exception as e:
        logger.error(f"Failed to calculate certificate expiry: {str(e)}")
        return None


def validate_domain_ownership(domain: str) -> bool:
    """
    Validate domain ownership through DNS challenges.
    
    Args:
        domain: Domain name to validate
        
    Returns:
        True if domain ownership is validated, False otherwise
    """
    try:
        # This is a placeholder for domain ownership validation logic
        # In a real implementation, this would check for specific DNS records
        # or use Certificate Manager's domain validation status
        logger.info(f"Domain ownership validation for {domain} - placeholder implementation")
        return True
    except Exception as e:
        logger.error(f"Domain ownership validation failed for {domain}: {str(e)}")
        return False