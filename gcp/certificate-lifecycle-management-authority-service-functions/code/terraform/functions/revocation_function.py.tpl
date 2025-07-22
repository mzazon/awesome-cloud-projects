"""
Certificate Revocation Cloud Function

This function handles certificate revocation using Google Cloud Certificate
Authority Service, updating Certificate Revocation Lists (CRL), and
notifying dependent systems.

Environment Variables:
- PROJECT_ID: Google Cloud project ID
- CA_POOL_NAME: Certificate Authority pool name
- SUB_CA_NAME: Subordinate CA name for certificate operations
- REGION: Google Cloud region
"""

import json
import datetime
import logging
import os
from typing import Dict, Any, Optional, List
from google.cloud import secretmanager
from google.cloud import privateca_v1
from google.cloud import monitoring_v3
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
PROJECT_ID = "${project_id}"
CA_POOL_NAME = "${ca_pool_name}"
SUB_CA_NAME = "${sub_ca_name}"
REGION = "${region}"

# Revocation reason mapping
REVOCATION_REASONS = {
    'UNSPECIFIED': privateca_v1.RevocationReason.REVOCATION_REASON_UNSPECIFIED,
    'KEY_COMPROMISE': privateca_v1.RevocationReason.KEY_COMPROMISE,
    'CA_COMPROMISE': privateca_v1.RevocationReason.CERTIFICATE_AUTHORITY_COMPROMISE,
    'AFFILIATION_CHANGED': privateca_v1.RevocationReason.AFFILIATION_CHANGED,
    'SUPERSEDED': privateca_v1.RevocationReason.SUPERSEDED,
    'CESSATION_OF_OPERATION': privateca_v1.RevocationReason.CESSATION_OF_OPERATION,
    'CERTIFICATE_HOLD': privateca_v1.RevocationReason.CERTIFICATE_HOLD,
    'PRIVILEGE_WITHDRAWN': privateca_v1.RevocationReason.PRIVILEGE_WITHDRAWN,
    'ATTRIBUTE_AUTHORITY_COMPROMISE': privateca_v1.RevocationReason.ATTRIBUTE_AUTHORITY_COMPROMISE
}

@functions_framework.http
def certificate_revocation(request) -> Dict[str, Any]:
    """
    Revoke certificates and update Certificate Revocation Lists.
    
    This function revokes compromised or invalid certificates using
    Certificate Authority Service and ensures CRL updates are propagated.
    
    Args:
        request: HTTP request containing revocation parameters
        
    Returns:
        Dict containing revocation results and CRL update status
    """
    
    try:
        # Initialize Google Cloud clients
        ca_client = privateca_v1.CertificateAuthorityServiceClient()
        secret_client = secretmanager.SecretManagerServiceClient()
        monitoring_client = monitoring_v3.MetricServiceClient()
        
        logger.info(f"Starting certificate revocation for project: {PROJECT_ID}")
        
        # Parse and validate request
        request_json = request.get_json(silent=True)
        if not request_json:
            raise ValueError("Request body must contain JSON data")
        
        revocation_params = _validate_revocation_request(request_json)
        
        logger.info(f"Revoking certificate: {revocation_params.get('certificate_name', 'unknown')}")
        logger.info(f"Revocation reason: {revocation_params['revocation_reason']}")
        
        # Revoke the certificate
        revocation_result = _revoke_certificate(ca_client, revocation_params)
        
        # Update certificate status in Secret Manager
        secret_update_result = _update_certificate_status(
            secret_client, 
            revocation_params, 
            revocation_result
        )
        
        # Send monitoring metrics
        _send_revocation_metrics(monitoring_client, revocation_params, revocation_result)
        
        # Trigger CRL refresh (Enterprise CA pools automatically update CRL)
        crl_status = _check_crl_status(ca_client)
        
        # Prepare success response
        response = {
            'status': 'success',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'revocation_info': revocation_result,
            'secret_update': secret_update_result,
            'crl_status': crl_status,
            'ca_info': {
                'ca_pool': CA_POOL_NAME,
                'issuing_ca': SUB_CA_NAME,
                'region': REGION
            }
        }
        
        logger.info(f"Certificate revocation completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"Certificate revocation failed: {str(e)}")
        return {
            'status': 'error',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'error': str(e),
            'error_type': type(e).__name__
        }


def _validate_revocation_request(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and normalize certificate revocation request parameters.
    
    Args:
        request_data: Raw request data from HTTP request
        
    Returns:
        Validated and normalized revocation parameters
        
    Raises:
        ValueError: If required parameters are missing or invalid
    """
    
    # Certificate identification - accept multiple methods
    certificate_name = request_data.get('certificate_name')
    common_name = request_data.get('common_name')
    serial_number = request_data.get('serial_number')
    
    if not any([certificate_name, common_name, serial_number]):
        raise ValueError(
            "Must provide at least one of: certificate_name, common_name, or serial_number"
        )
    
    # Revocation reason
    revocation_reason = request_data.get('revocation_reason', 'UNSPECIFIED')
    if revocation_reason not in REVOCATION_REASONS:
        raise ValueError(
            f"Invalid revocation_reason. Must be one of: {list(REVOCATION_REASONS.keys())}"
        )
    
    # Optional parameters
    notify_systems = request_data.get('notify_systems', True)
    emergency_revocation = request_data.get('emergency_revocation', False)
    revocation_note = request_data.get('revocation_note', '')
    
    return {
        'certificate_name': certificate_name,
        'common_name': common_name,
        'serial_number': serial_number,
        'revocation_reason': revocation_reason,
        'notify_systems': notify_systems,
        'emergency_revocation': emergency_revocation,
        'revocation_note': revocation_note
    }


def _revoke_certificate(ca_client: privateca_v1.CertificateAuthorityServiceClient,
                       revocation_params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Revoke a certificate using Certificate Authority Service.
    
    Args:
        ca_client: Certificate Authority Service client
        revocation_params: Revocation parameters
        
    Returns:
        Dictionary with revocation results
    """
    
    # If we have certificate_name, use it directly
    if revocation_params['certificate_name']:
        certificate_name = revocation_params['certificate_name']
    else:
        # Find certificate by common name or serial number
        certificate_name = _find_certificate(ca_client, revocation_params)
    
    if not certificate_name:
        raise ValueError("Could not find certificate to revoke")
    
    # Create revocation request
    revocation_reason = REVOCATION_REASONS[revocation_params['revocation_reason']]
    
    request = privateca_v1.RevokeCertificateRequest(
        name=certificate_name,
        reason=revocation_reason
    )
    
    # Revoke the certificate
    logger.info(f"Revoking certificate: {certificate_name}")
    revoked_certificate = ca_client.revoke_certificate(request=request)
    
    logger.info(f"Certificate revoked successfully: {certificate_name}")
    
    return {
        'certificate_name': certificate_name,
        'revocation_reason': revocation_params['revocation_reason'],
        'revocation_time': datetime.datetime.utcnow().isoformat(),
        'revoked_certificate_info': {
            'name': revoked_certificate.name,
            'revocation_details': str(revoked_certificate.revocation_details) if revoked_certificate.revocation_details else None
        },
        'emergency_revocation': revocation_params['emergency_revocation'],
        'revocation_note': revocation_params['revocation_note']
    }


def _find_certificate(ca_client: privateca_v1.CertificateAuthorityServiceClient,
                     revocation_params: Dict[str, Any]) -> Optional[str]:
    """
    Find a certificate by common name or serial number.
    
    Args:
        ca_client: Certificate Authority Service client
        revocation_params: Revocation parameters containing search criteria
        
    Returns:
        Certificate name if found, None otherwise
    """
    
    try:
        # Build CA pool path
        ca_pool_path = f"projects/{PROJECT_ID}/locations/{REGION}/caPools/{CA_POOL_NAME}"
        
        # List certificates in the CA pool
        request = privateca_v1.ListCertificatesRequest(parent=ca_pool_path)
        page_result = ca_client.list_certificates(request=request)
        
        for certificate in page_result:
            # Check serial number match
            if revocation_params['serial_number']:
                if str(certificate.name).endswith(revocation_params['serial_number']):
                    return certificate.name
            
            # Check common name match (requires parsing certificate)
            if revocation_params['common_name']:
                try:
                    # This is simplified - in production you'd parse the certificate
                    # to extract the common name from the subject
                    if revocation_params['common_name'] in certificate.name:
                        return certificate.name
                except Exception:
                    continue
        
        return None
        
    except Exception as e:
        logger.error(f"Error finding certificate: {str(e)}")
        return None


def _update_certificate_status(secret_client: secretmanager.SecretManagerServiceClient,
                              revocation_params: Dict[str, Any],
                              revocation_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Update certificate status in Secret Manager to mark as revoked.
    
    Args:
        secret_client: Secret Manager client
        revocation_params: Revocation parameters
        revocation_result: Results from certificate revocation
        
    Returns:
        Dictionary with secret update information
    """
    
    try:
        # Find the secret containing the revoked certificate
        secret_name = None
        
        if revocation_params['common_name']:
            secret_name = f"cert-{revocation_params['common_name'].replace('.', '-')}"
        
        if not secret_name:
            logger.warning("Could not determine secret name for certificate status update")
            return {'status': 'skipped', 'reason': 'unknown_secret_name'}
        
        # Get current secret version
        secret_path = f"projects/{PROJECT_ID}/secrets/{secret_name}/versions/latest"
        
        try:
            response = secret_client.access_secret_version(request={"name": secret_path})
            current_bundle = json.loads(response.payload.data.decode('utf-8'))
        except Exception as e:
            logger.warning(f"Could not access secret {secret_name}: {str(e)}")
            return {'status': 'skipped', 'reason': 'secret_access_failed'}
        
        # Update bundle with revocation information
        current_bundle['revoked'] = True
        current_bundle['revocation_time'] = revocation_result['revocation_time']
        current_bundle['revocation_reason'] = revocation_result['revocation_reason']
        current_bundle['revocation_note'] = revocation_result['revocation_note']
        
        # Store updated bundle
        updated_bundle_json = json.dumps(current_bundle, indent=2)
        
        secret_parent = f"projects/{PROJECT_ID}/secrets/{secret_name}"
        version_response = secret_client.add_secret_version(
            request={
                "parent": secret_parent,
                "payload": {"data": updated_bundle_json.encode('utf-8')}
            }
        )
        
        logger.info(f"Updated certificate status in secret: {version_response.name}")
        
        return {
            'status': 'updated',
            'secret_name': secret_name,
            'new_version': version_response.name,
            'updated_timestamp': datetime.datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Failed to update certificate status in Secret Manager: {str(e)}")
        return {
            'status': 'failed',
            'error': str(e)
        }


def _send_revocation_metrics(monitoring_client: monitoring_v3.MetricServiceClient,
                           revocation_params: Dict[str, Any],
                           revocation_result: Dict[str, Any]) -> None:
    """
    Send custom metrics for certificate revocation monitoring.
    
    Args:
        monitoring_client: Cloud Monitoring client
        revocation_params: Revocation parameters
        revocation_result: Revocation results
    """
    
    try:
        project_name = f"projects/{PROJECT_ID}"
        
        # Create time series for revocation count
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/certificate/revocation_count"
        series.metric.labels["ca_pool"] = CA_POOL_NAME
        series.metric.labels["revocation_reason"] = revocation_params['revocation_reason']
        series.metric.labels["emergency"] = str(revocation_params['emergency_revocation']).lower()
        
        series.resource.type = "global"
        series.resource.labels["project_id"] = PROJECT_ID
        
        # Create data point
        now = datetime.datetime.utcnow()
        seconds = int(now.timestamp())
        nanos = int((now.timestamp() - seconds) * 10**9)
        
        point = monitoring_v3.Point()
        point.interval.end_time.seconds = seconds
        point.interval.end_time.nanos = nanos
        point.value.int64_value = 1  # Count of revocations
        
        series.points = [point]
        
        # Send metric
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logger.debug(f"Sent revocation metric for reason: {revocation_params['revocation_reason']}")
        
    except Exception as e:
        logger.warning(f"Failed to send revocation monitoring metric: {str(e)}")


def _check_crl_status(ca_client: privateca_v1.CertificateAuthorityServiceClient) -> Dict[str, Any]:
    """
    Check Certificate Revocation List status after revocation.
    
    Args:
        ca_client: Certificate Authority Service client
        
    Returns:
        Dictionary with CRL status information
    """
    
    try:
        # Build CA pool path
        ca_pool_path = f"projects/{PROJECT_ID}/locations/{REGION}/caPools/{CA_POOL_NAME}"
        
        # List CRLs for the CA pool
        request = privateca_v1.ListCertificateRevocationListsRequest(parent=ca_pool_path)
        page_result = ca_client.list_certificate_revocation_lists(request=request)
        
        crl_info = []
        for crl in page_result:
            crl_info.append({
                'name': crl.name,
                'state': str(crl.state),
                'create_time': crl.create_time.isoformat() if crl.create_time else None,
                'update_time': crl.update_time.isoformat() if crl.update_time else None,
                'revision_id': crl.revision_id,
                'revoked_certificates_count': len(crl.revoked_certificates) if crl.revoked_certificates else 0
            })
        
        return {
            'status': 'checked',
            'crl_count': len(crl_info),
            'crls': crl_info,
            'check_timestamp': datetime.datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Failed to check CRL status: {str(e)}")
        return {
            'status': 'failed',
            'error': str(e),
            'check_timestamp': datetime.datetime.utcnow().isoformat()
        }