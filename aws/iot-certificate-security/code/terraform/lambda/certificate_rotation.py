"""
AWS Lambda function for IoT certificate rotation monitoring
This function monitors certificate expiration and facilitates rotation workflows
"""

import json
import boto3
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
iot_client = boto3.client('iot')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Monitor IoT certificates and identify those requiring rotation
    
    Args:
        event: EventBridge trigger event or manual invocation
        context: Lambda execution context
        
    Returns:
        Response with rotation recommendations and actions taken
    """
    
    try:
        logger.info("Starting certificate rotation check")
        
        # Get configuration from environment or event
        expiry_threshold_days = int(event.get('expiryThresholdDays', 30))
        dry_run = event.get('dryRun', True)  # Default to dry run for safety
        
        # List all certificates
        certificates_data = list_all_certificates()
        
        # Analyze certificates for expiration
        rotation_candidates = analyze_certificate_expiration(certificates_data, expiry_threshold_days)
        
        # Generate rotation plan
        rotation_plan = generate_rotation_plan(rotation_candidates)
        
        # Execute rotation if not dry run
        rotation_results = []
        if not dry_run and rotation_candidates:
            rotation_results = execute_rotation_plan(rotation_plan)
        
        # Prepare response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Certificate rotation check completed',
                'certificatesChecked': len(certificates_data),
                'rotationCandidates': len(rotation_candidates),
                'rotationPlan': rotation_plan,
                'rotationResults': rotation_results,
                'dryRun': dry_run,
                'timestamp': datetime.utcnow().isoformat()
            }, default=str)
        }
        
        logger.info(f"Certificate rotation check completed. Found {len(rotation_candidates)} candidates for rotation")
        
        return response
        
    except Exception as e:
        logger.error(f"Certificate rotation check failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }


def list_all_certificates() -> List[Dict[str, Any]]:
    """
    List all IoT certificates in the account
    
    Returns:
        List of certificate information
    """
    
    certificates = []
    next_marker = None
    
    try:
        while True:
            if next_marker:
                response = iot_client.list_certificates(
                    pageSize=100,
                    marker=next_marker
                )
            else:
                response = iot_client.list_certificates(pageSize=100)
            
            certificates.extend(response.get('certificates', []))
            
            next_marker = response.get('nextMarker')
            if not next_marker:
                break
        
        logger.info(f"Found {len(certificates)} certificates")
        return certificates
        
    except Exception as e:
        logger.error(f"Failed to list certificates: {str(e)}")
        return []


def analyze_certificate_expiration(certificates: List[Dict[str, Any]], 
                                 threshold_days: int) -> List[Dict[str, Any]]:
    """
    Analyze certificates for expiration within the threshold period
    
    Args:
        certificates: List of certificate information
        threshold_days: Number of days before expiration to flag for rotation
        
    Returns:
        List of certificates requiring rotation
    """
    
    rotation_candidates = []
    threshold_date = datetime.utcnow() + timedelta(days=threshold_days)
    
    for cert in certificates:
        try:
            cert_id = cert['certificateId']
            cert_arn = cert['certificateArn']
            status = cert['status']
            
            # Only check active certificates
            if status != 'ACTIVE':
                continue
            
            # Get detailed certificate information
            cert_details = iot_client.describe_certificate(certificateId=cert_id)
            cert_description = cert_details['certificateDescription']
            
            creation_date = cert_description['creationDate']
            
            # For demonstration, we'll use creation date + 1 year as expiry
            # In production, parse the actual certificate to get expiry date
            estimated_expiry = creation_date + timedelta(days=365)
            
            if estimated_expiry <= threshold_date:
                # Get attached things and policies
                attached_things = get_attached_things(cert_arn)
                attached_policies = get_attached_policies(cert_arn)
                
                rotation_candidate = {
                    'certificateId': cert_id,
                    'certificateArn': cert_arn,
                    'creationDate': creation_date.isoformat(),
                    'estimatedExpiry': estimated_expiry.isoformat(),
                    'daysUntilExpiry': (estimated_expiry - datetime.utcnow()).days,
                    'attachedThings': attached_things,
                    'attachedPolicies': attached_policies,
                    'rotationPriority': calculate_rotation_priority(estimated_expiry, attached_things)
                }
                
                rotation_candidates.append(rotation_candidate)
                
        except Exception as e:
            logger.error(f"Failed to analyze certificate {cert.get('certificateId', 'unknown')}: {str(e)}")
            continue
    
    # Sort by priority (most urgent first)
    rotation_candidates.sort(key=lambda x: x['rotationPriority'], reverse=True)
    
    return rotation_candidates


def get_attached_things(certificate_arn: str) -> List[str]:
    """
    Get list of things attached to a certificate
    
    Args:
        certificate_arn: Certificate ARN
        
    Returns:
        List of attached thing names
    """
    
    try:
        response = iot_client.list_principal_things(principal=certificate_arn)
        return response.get('things', [])
    except Exception as e:
        logger.error(f"Failed to get attached things for {certificate_arn}: {str(e)}")
        return []


def get_attached_policies(certificate_arn: str) -> List[str]:
    """
    Get list of policies attached to a certificate
    
    Args:
        certificate_arn: Certificate ARN
        
    Returns:
        List of attached policy names
    """
    
    try:
        response = iot_client.list_attached_policies(target=certificate_arn)
        return [policy['policyName'] for policy in response.get('policies', [])]
    except Exception as e:
        logger.error(f"Failed to get attached policies for {certificate_arn}: {str(e)}")
        return []


def calculate_rotation_priority(expiry_date: datetime, attached_things: List[str]) -> int:
    """
    Calculate rotation priority based on expiry date and device importance
    
    Args:
        expiry_date: Certificate expiry date
        attached_things: List of attached thing names
        
    Returns:
        Priority score (higher = more urgent)
    """
    
    days_until_expiry = (expiry_date - datetime.utcnow()).days
    
    # Base priority on urgency
    if days_until_expiry <= 7:
        priority = 100
    elif days_until_expiry <= 14:
        priority = 80
    elif days_until_expiry <= 30:
        priority = 60
    else:
        priority = 40
    
    # Increase priority for certificates with multiple attached things
    priority += min(len(attached_things) * 5, 20)
    
    # Decrease priority if already expired (might be test certificates)
    if days_until_expiry < 0:
        priority = max(priority - 50, 10)
    
    return priority


def generate_rotation_plan(rotation_candidates: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Generate a rotation plan for the identified candidates
    
    Args:
        rotation_candidates: List of certificates requiring rotation
        
    Returns:
        Rotation plan with recommended actions
    """
    
    if not rotation_candidates:
        return {
            'totalCertificates': 0,
            'recommendedActions': [],
            'summary': 'No certificates require rotation at this time'
        }
    
    recommended_actions = []
    
    for candidate in rotation_candidates:
        action = {
            'certificateId': candidate['certificateId'],
            'priority': candidate['rotationPriority'],
            'daysUntilExpiry': candidate['daysUntilExpiry'],
            'attachedThings': candidate['attachedThings'],
            'recommendedSteps': generate_rotation_steps(candidate)
        }
        recommended_actions.append(action)
    
    plan = {
        'totalCertificates': len(rotation_candidates),
        'urgentRotations': len([c for c in rotation_candidates if c['daysUntilExpiry'] <= 7]),
        'soonRotations': len([c for c in rotation_candidates if 7 < c['daysUntilExpiry'] <= 30]),
        'recommendedActions': recommended_actions,
        'summary': f"Found {len(rotation_candidates)} certificates requiring rotation"
    }
    
    return plan


def generate_rotation_steps(candidate: Dict[str, Any]) -> List[str]:
    """
    Generate specific rotation steps for a certificate
    
    Args:
        candidate: Certificate rotation candidate
        
    Returns:
        List of recommended rotation steps
    """
    
    steps = [
        "1. Create new certificate and private key",
        "2. Update device with new certificate (coordinate with device team)",
        "3. Test device connectivity with new certificate",
        "4. Attach policies to new certificate",
        "5. Attach new certificate to IoT things",
        "6. Verify device functionality",
        "7. Deactivate old certificate",
        "8. Monitor for any connectivity issues",
        "9. Delete old certificate after grace period"
    ]
    
    if candidate['daysUntilExpiry'] <= 7:
        steps.insert(0, "URGENT: This certificate expires within 7 days!")
    
    if len(candidate['attachedThings']) > 1:
        steps.insert(-3, "CAUTION: Multiple devices use this certificate - coordinate rotation")
    
    return steps


def execute_rotation_plan(rotation_plan: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Execute the rotation plan (production implementation would be more complex)
    
    Args:
        rotation_plan: Generated rotation plan
        
    Returns:
        Results of rotation actions
    """
    
    results = []
    
    # In a production environment, this would:
    # 1. Integrate with device management systems
    # 2. Create new certificates
    # 3. Coordinate with device firmware update mechanisms
    # 4. Implement staged rollout
    # 5. Monitor for connectivity issues
    
    for action in rotation_plan.get('recommendedActions', []):
        result = {
            'certificateId': action['certificateId'],
            'status': 'planned',
            'message': 'Rotation workflow initiated - manual intervention required',
            'timestamp': datetime.utcnow().isoformat()
        }
        results.append(result)
        
        # Log the planned action
        logger.info(f"Rotation planned for certificate: {action['certificateId']}")
    
    return results


def create_new_certificate_for_rotation(old_cert_id: str) -> Dict[str, Any]:
    """
    Create a new certificate for rotation (production helper function)
    
    Args:
        old_cert_id: ID of the certificate being rotated
        
    Returns:
        New certificate information
    """
    
    try:
        # Create new certificate
        response = iot_client.create_keys_and_certificate(setAsActive=False)
        
        new_cert_data = {
            'certificateId': response['certificateId'],
            'certificateArn': response['certificateArn'],
            'certificatePem': response['certificatePem'],
            'privateKey': response['keyPair']['PrivateKey'],
            'publicKey': response['keyPair']['PublicKey']
        }
        
        logger.info(f"Created new certificate {response['certificateId']} for rotation of {old_cert_id}")
        
        return new_cert_data
        
    except Exception as e:
        logger.error(f"Failed to create new certificate for rotation: {str(e)}")
        raise


def send_rotation_notification(rotation_plan: Dict[str, Any]) -> None:
    """
    Send notification about required certificate rotations
    
    Args:
        rotation_plan: Generated rotation plan
    """
    
    try:
        if rotation_plan['totalCertificates'] == 0:
            return
        
        # In production, integrate with:
        # - SNS for alerts
        # - Email notifications
        # - Ticketing systems
        # - Monitoring dashboards
        
        logger.info(f"Certificate rotation notification: {rotation_plan['summary']}")
        
        urgent_count = rotation_plan.get('urgentRotations', 0)
        if urgent_count > 0:
            logger.warning(f"URGENT: {urgent_count} certificates expire within 7 days!")
            
    except Exception as e:
        logger.error(f"Failed to send rotation notification: {str(e)}")


def validate_certificate_health(cert_id: str) -> Dict[str, Any]:
    """
    Validate the health and usage of a certificate
    
    Args:
        cert_id: Certificate ID to validate
        
    Returns:
        Certificate health information
    """
    
    try:
        # Get certificate details
        cert_details = iot_client.describe_certificate(certificateId=cert_id)
        
        # Check for recent activity (would require CloudWatch integration)
        # Check for policy compliance
        # Validate certificate chain
        
        health_status = {
            'certificateId': cert_id,
            'status': cert_details['certificateDescription']['status'],
            'healthy': True,
            'lastActivity': 'unknown',  # Would be populated from CloudWatch
            'recommendations': []
        }
        
        return health_status
        
    except Exception as e:
        logger.error(f"Failed to validate certificate health for {cert_id}: {str(e)}")
        return {'certificateId': cert_id, 'healthy': False, 'error': str(e)}