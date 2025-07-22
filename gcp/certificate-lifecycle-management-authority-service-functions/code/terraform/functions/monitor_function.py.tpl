"""
Certificate Monitoring Cloud Function

This function monitors certificates stored in Secret Manager for expiration
and triggers renewal processes when certificates are approaching their
expiration dates.

Environment Variables:
- PROJECT_ID: Google Cloud project ID
- CA_POOL_NAME: Certificate Authority pool name
- REGION: Google Cloud region
- RENEWAL_THRESHOLD_DAYS: Days before expiration to trigger renewal
"""

import json
import datetime
import logging
import os
from typing import Dict, List, Any, Optional
from google.cloud import secretmanager
from google.cloud import privateca_v1
from google.cloud import monitoring_v3
import cryptography
from cryptography import x509
from cryptography.hazmat.backends import default_backend
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
PROJECT_ID = "${project_id}"
CA_POOL_NAME = "${ca_pool_name}"
REGION = "${region}"
RENEWAL_THRESHOLD_DAYS = int("${renewal_threshold_days}")

@functions_framework.http
def certificate_monitor(request) -> Dict[str, Any]:
    """
    Monitor certificates for expiration and trigger renewal processes.
    
    This function scans Secret Manager for stored certificates, analyzes
    their expiration dates, and identifies certificates that require renewal.
    
    Args:
        request: HTTP request object containing monitoring parameters
        
    Returns:
        Dict containing monitoring results and expiring certificate details
    """
    
    try:
        # Initialize Google Cloud clients
        secret_client = secretmanager.SecretManagerServiceClient()
        monitoring_client = monitoring_v3.MetricServiceClient()
        
        logger.info(f"Starting certificate monitoring for project: {PROJECT_ID}")
        logger.info(f"Using renewal threshold: {RENEWAL_THRESHOLD_DAYS} days")
        
        # Parse request data
        request_json = request.get_json(silent=True) or {}
        source = request_json.get('source', 'unknown')
        action = request_json.get('action', 'monitor')
        
        logger.info(f"Monitor request from: {source}, action: {action}")
        
        # List all secrets that contain certificates
        parent = f"projects/{PROJECT_ID}"
        secrets = secret_client.list_secrets(request={"parent": parent})
        
        expiring_certificates = []
        healthy_certificates = []
        error_certificates = []
        
        for secret in secrets:
            # Filter for certificate secrets (by naming convention)
            if 'certificate' in secret.name.lower() or 'cert-' in secret.name.lower():
                try:
                    cert_info = _analyze_certificate_secret(secret_client, secret)
                    
                    if cert_info is None:
                        continue
                        
                    days_until_expiry = cert_info['days_until_expiry']
                    
                    if days_until_expiry <= RENEWAL_THRESHOLD_DAYS:
                        expiring_certificates.append(cert_info)
                        logger.warning(
                            f"Certificate {cert_info['common_name']} expires in "
                            f"{days_until_expiry} days - RENEWAL REQUIRED"
                        )
                        
                        # Send custom metric for monitoring
                        _send_certificate_metric(
                            monitoring_client, 
                            cert_info['common_name'], 
                            days_until_expiry
                        )
                        
                    elif days_until_expiry <= 90:  # Warning zone
                        healthy_certificates.append(cert_info)
                        logger.info(
                            f"Certificate {cert_info['common_name']} expires in "
                            f"{days_until_expiry} days - monitoring"
                        )
                    else:
                        healthy_certificates.append(cert_info)
                        
                except Exception as e:
                    error_info = {
                        'secret_name': secret.name,
                        'error': str(e),
                        'timestamp': datetime.datetime.utcnow().isoformat()
                    }
                    error_certificates.append(error_info)
                    logger.error(f"Error processing secret {secret.name}: {str(e)}")
                    continue
        
        # Log summary
        total_certificates = len(expiring_certificates) + len(healthy_certificates)
        logger.info(f"Certificate monitoring summary:")
        logger.info(f"  Total certificates: {total_certificates}")
        logger.info(f"  Expiring certificates: {len(expiring_certificates)}")
        logger.info(f"  Healthy certificates: {len(healthy_certificates)}")
        logger.info(f"  Error certificates: {len(error_certificates)}")
        
        # Trigger renewal for expiring certificates if automated renewal is enabled
        renewal_results = []
        for cert in expiring_certificates:
            try:
                renewal_result = _trigger_certificate_renewal(cert)
                renewal_results.append(renewal_result)
            except Exception as e:
                logger.error(f"Failed to trigger renewal for {cert['common_name']}: {str(e)}")
                renewal_results.append({
                    'common_name': cert['common_name'],
                    'status': 'failed',
                    'error': str(e)
                })
        
        # Prepare response
        response = {
            'status': 'success',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'source': source,
            'monitoring_summary': {
                'total_certificates': total_certificates,
                'expiring_certificates': len(expiring_certificates),
                'healthy_certificates': len(healthy_certificates),
                'error_certificates': len(error_certificates),
                'renewal_threshold_days': RENEWAL_THRESHOLD_DAYS
            },
            'expiring_certificates': expiring_certificates,
            'renewal_results': renewal_results,
            'errors': error_certificates
        }
        
        logger.info("Certificate monitoring completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"Certificate monitoring failed: {str(e)}")
        return {
            'status': 'error',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'error': str(e),
            'source': source if 'source' in locals() else 'unknown'
        }


def _analyze_certificate_secret(secret_client: secretmanager.SecretManagerServiceClient, 
                               secret) -> Optional[Dict[str, Any]]:
    """
    Analyze a certificate secret to extract expiration information.
    
    Args:
        secret_client: Secret Manager client
        secret: Secret resource to analyze
        
    Returns:
        Dictionary with certificate information or None if not a valid certificate
    """
    try:
        # Get the latest version of the secret
        secret_version_name = f"{secret.name}/versions/latest"
        response = secret_client.access_secret_version(
            request={"name": secret_version_name}
        )
        
        secret_data = response.payload.data.decode('utf-8')
        
        # Try to parse as JSON (for certificate bundles)
        try:
            cert_bundle = json.loads(secret_data)
            if 'certificate' in cert_bundle:
                cert_pem = cert_bundle['certificate']
            else:
                cert_pem = secret_data
        except json.JSONDecodeError:
            # Assume it's a PEM certificate directly
            cert_pem = secret_data
        
        # Parse the certificate
        cert = x509.load_pem_x509_certificate(cert_pem.encode(), default_backend())
        
        # Extract certificate information
        common_name = "Unknown"
        try:
            cn_attributes = cert.subject.get_attributes_for_oid(x509.NameOID.COMMON_NAME)
            if cn_attributes:
                common_name = cn_attributes[0].value
        except Exception:
            pass
        
        # Calculate days until expiry
        now = datetime.datetime.utcnow()
        days_until_expiry = (cert.not_valid_after - now).days
        
        # Extract Subject Alternative Names
        san_list = []
        try:
            san_ext = cert.extensions.get_extension_for_oid(x509.oid.ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
            san_list = [san.value for san in san_ext.value]
        except x509.ExtensionNotFound:
            pass
        
        return {
            'secret_name': secret.name,
            'common_name': common_name,
            'subject': cert.subject.rfc4514_string(),
            'issuer': cert.issuer.rfc4514_string(),
            'serial_number': str(cert.serial_number),
            'not_valid_before': cert.not_valid_before.isoformat(),
            'not_valid_after': cert.not_valid_after.isoformat(),
            'days_until_expiry': days_until_expiry,
            'subject_alt_names': san_list,
            'key_algorithm': cert.public_key().key_size if hasattr(cert.public_key(), 'key_size') else 'Unknown',
            'signature_algorithm': cert.signature_algorithm_oid._name
        }
        
    except Exception as e:
        logger.debug(f"Could not parse secret {secret.name} as certificate: {str(e)}")
        return None


def _send_certificate_metric(monitoring_client: monitoring_v3.MetricServiceClient,
                           common_name: str, days_until_expiry: int) -> None:
    """
    Send custom metric for certificate expiration monitoring.
    
    Args:
        monitoring_client: Cloud Monitoring client
        common_name: Certificate common name
        days_until_expiry: Days until certificate expires
    """
    try:
        project_name = f"projects/{PROJECT_ID}"
        
        # Create time series data
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/certificate/days_until_expiry"
        series.metric.labels["certificate_cn"] = common_name
        series.metric.labels["ca_pool"] = CA_POOL_NAME
        
        series.resource.type = "global"
        series.resource.labels["project_id"] = PROJECT_ID
        
        # Create data point
        now = datetime.datetime.utcnow()
        seconds = int(now.timestamp())
        nanos = int((now.timestamp() - seconds) * 10**9)
        
        point = monitoring_v3.Point()
        point.interval.end_time.seconds = seconds
        point.interval.end_time.nanos = nanos
        point.value.int64_value = days_until_expiry
        
        series.points = [point]
        
        # Send metric
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logger.debug(f"Sent metric for certificate {common_name}: {days_until_expiry} days")
        
    except Exception as e:
        logger.warning(f"Failed to send monitoring metric: {str(e)}")


def _trigger_certificate_renewal(cert_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Trigger certificate renewal for an expiring certificate.
    
    Args:
        cert_info: Certificate information dictionary
        
    Returns:
        Dictionary with renewal trigger results
    """
    try:
        # In a real implementation, this would call the renewal function
        # or trigger a workflow for certificate renewal
        
        logger.info(f"Triggering renewal for certificate: {cert_info['common_name']}")
        
        # For now, just log the renewal requirement
        # In production, you would:
        # 1. Call the renewal Cloud Function
        # 2. Trigger a Cloud Workflow
        # 3. Send notifications to operations teams
        # 4. Create support tickets for manual intervention
        
        return {
            'common_name': cert_info['common_name'],
            'status': 'renewal_triggered',
            'days_until_expiry': cert_info['days_until_expiry'],
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'action': 'logged_for_manual_renewal'
        }
        
    except Exception as e:
        logger.error(f"Failed to trigger renewal for {cert_info['common_name']}: {str(e)}")
        return {
            'common_name': cert_info['common_name'],
            'status': 'renewal_failed',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat()
        }