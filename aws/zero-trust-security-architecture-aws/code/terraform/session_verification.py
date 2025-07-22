"""
Zero Trust Session Verification Lambda Function

This function provides continuous session verification for zero trust architecture.
It monitors session integrity and can terminate sessions that violate security policies.
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
ssm_client = boto3.client('ssm')
cloudwatch_client = boto3.client('cloudwatch')
logs_client = boto3.client('logs')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for zero trust session verification
    
    Args:
        event: Lambda event containing session details
        context: Lambda context object
        
    Returns:
        Response dictionary with verification results
    """
    try:
        logger.info(f"Processing session verification event: {json.dumps(event, default=str)}")
        
        # Extract session details from event
        session_id = event.get('sessionId', '')
        user_id = event.get('userId', '')
        source_ip = event.get('sourceIp', '')
        session_start_time = event.get('sessionStartTime', '')
        user_agent = event.get('userAgent', '')
        
        # Perform comprehensive session verification
        verification_result = verify_session_integrity(
            session_id=session_id,
            user_id=user_id,
            source_ip=source_ip,
            session_start_time=session_start_time,
            user_agent=user_agent
        )
        
        # Take action based on verification result
        if not verification_result['is_valid']:
            logger.warning(f"Session integrity violation detected: {verification_result['violations']}")
            
            # Terminate session for security violation
            terminate_session(session_id)
            
            # Send security alert
            send_security_alert(
                session_id=session_id,
                user_id=user_id,
                violations=verification_result['violations']
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'action': 'terminated',
                    'sessionId': session_id,
                    'reason': 'session_integrity_violation',
                    'violations': verification_result['violations']
                })
            }
        
        # Session is valid - log success
        logger.info(f"Session {session_id} verified successfully")
        
        # Update session metrics
        update_session_metrics(session_id, user_id, 'verified')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'action': 'verified',
                'sessionId': session_id,
                'verificationTime': datetime.utcnow().isoformat(),
                'nextVerification': (datetime.utcnow() + timedelta(minutes=15)).isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Session verification failed: {str(e)}", exc_info=True)
        
        # In case of error, fail secure by terminating the session
        if 'sessionId' in event:
            terminate_session(event['sessionId'])
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'action': 'terminated_on_error',
                'sessionId': event.get('sessionId', 'unknown')
            })
        }

def verify_session_integrity(
    session_id: str,
    user_id: str,
    source_ip: str,
    session_start_time: str,
    user_agent: str
) -> Dict[str, Any]:
    """
    Verify session integrity based on zero trust principles
    
    Args:
        session_id: Unique session identifier
        user_id: User identifier
        source_ip: Source IP address of the session
        session_start_time: When the session started
        user_agent: User agent string
        
    Returns:
        Dictionary containing verification results
    """
    violations = []
    is_valid = True
    
    try:
        # Check 1: Verify session duration limits (max 8 hours)
        if session_start_time:
            start_time = datetime.fromisoformat(session_start_time.replace('Z', '+00:00'))
            session_duration = datetime.utcnow() - start_time.replace(tzinfo=None)
            
            if session_duration > timedelta(hours=8):
                violations.append('session_duration_exceeded')
                is_valid = False
                logger.warning(f"Session {session_id} duration exceeded: {session_duration}")
        
        # Check 2: Verify IP address consistency
        if source_ip:
            previous_ips = get_session_ips(session_id)
            if previous_ips and source_ip not in previous_ips:
                # Allow IP changes within trusted ranges only
                if not is_trusted_ip_range(source_ip):
                    violations.append('untrusted_ip_change')
                    is_valid = False
                    logger.warning(f"Untrusted IP change detected for session {session_id}: {source_ip}")
        
        # Check 3: Verify user agent consistency
        if user_agent:
            previous_agents = get_session_user_agents(session_id)
            if previous_agents and user_agent not in previous_agents:
                violations.append('user_agent_change')
                is_valid = False
                logger.warning(f"User agent change detected for session {session_id}")
        
        # Check 4: Check for concurrent sessions (zero trust principle)
        concurrent_sessions = get_concurrent_sessions(user_id)
        if len(concurrent_sessions) > 3:  # Allow max 3 concurrent sessions
            violations.append('excessive_concurrent_sessions')
            is_valid = False
            logger.warning(f"Excessive concurrent sessions for user {user_id}: {len(concurrent_sessions)}")
        
        # Check 5: Verify time-based access policies
        current_hour = datetime.utcnow().hour
        if current_hour < 6 or current_hour > 22:  # Outside business hours
            # Check if user has after-hours access
            if not has_after_hours_access(user_id):
                violations.append('outside_business_hours')
                is_valid = False
                logger.warning(f"After-hours access attempted by user {user_id}")
        
        # Check 6: Look for suspicious activity patterns
        if is_suspicious_activity(session_id, user_id):
            violations.append('suspicious_activity_pattern')
            is_valid = False
            logger.warning(f"Suspicious activity pattern detected for session {session_id}")
        
        logger.info(f"Session verification completed - Valid: {is_valid}, Violations: {violations}")
        
    except Exception as e:
        logger.error(f"Error during session verification: {str(e)}")
        violations.append('verification_error')
        is_valid = False
    
    return {
        'is_valid': is_valid,
        'violations': violations,
        'verification_time': datetime.utcnow().isoformat()
    }

def terminate_session(session_id: str) -> bool:
    """
    Terminate a session for security violation
    
    Args:
        session_id: Session ID to terminate
        
    Returns:
        True if session was terminated successfully
    """
    try:
        if not session_id:
            logger.warning("No session ID provided for termination")
            return False
        
        # Terminate SSM session
        response = ssm_client.terminate_session(SessionId=session_id)
        logger.info(f"Session {session_id} terminated successfully: {response}")
        
        # Log termination event
        log_security_event('session_terminated', {
            'sessionId': session_id,
            'reason': 'security_violation',
            'timestamp': datetime.utcnow().isoformat()
        })
        
        return True
        
    except ssm_client.exceptions.InvalidSessionId:
        logger.warning(f"Session {session_id} not found or already terminated")
        return True  # Session doesn't exist, so termination is effective
        
    except Exception as e:
        logger.error(f"Failed to terminate session {session_id}: {str(e)}")
        return False

def send_security_alert(session_id: str, user_id: str, violations: list) -> None:
    """
    Send security alert for session violations
    
    Args:
        session_id: Session ID that violated policy
        user_id: User ID associated with the session
        violations: List of violations detected
    """
    try:
        alert_message = {
            'event_type': 'zero_trust_session_violation',
            'session_id': session_id,
            'user_id': user_id,
            'violations': violations,
            'timestamp': datetime.utcnow().isoformat(),
            'action_taken': 'session_terminated'
        }
        
        # Log to CloudWatch for alerting
        log_security_event('security_alert', alert_message)
        
        logger.info(f"Security alert sent for session {session_id}")
        
    except Exception as e:
        logger.error(f"Failed to send security alert: {str(e)}")

def update_session_metrics(session_id: str, user_id: str, status: str) -> None:
    """
    Update CloudWatch metrics for session monitoring
    
    Args:
        session_id: Session ID
        user_id: User ID
        status: Session status (verified, terminated, etc.)
    """
    try:
        cloudwatch_client.put_metric_data(
            Namespace='ZeroTrust/Sessions',
            MetricData=[
                {
                    'MetricName': 'SessionVerifications',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Status',
                            'Value': status
                        },
                        {
                            'Name': 'UserId',
                            'Value': user_id[:50]  # Truncate for metric dimension
                        }
                    ]
                }
            ]
        )
        
    except Exception as e:
        logger.error(f"Failed to update session metrics: {str(e)}")

def log_security_event(event_type: str, event_data: Dict[str, Any]) -> None:
    """
    Log security events to CloudWatch Logs
    
    Args:
        event_type: Type of security event
        event_data: Event data to log
    """
    try:
        log_group_name = os.environ.get('LOG_GROUP', '/aws/lambda/zero-trust-session-verification')
        
        log_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'event_type': event_type,
            'data': event_data
        }
        
        logger.info(f"Security event logged: {json.dumps(log_entry, default=str)}")
        
    except Exception as e:
        logger.error(f"Failed to log security event: {str(e)}")

# Helper functions for session verification

def get_session_ips(session_id: str) -> list:
    """Get previous IP addresses for a session"""
    # In a real implementation, this would query a session tracking database
    # For this example, we'll return an empty list
    return []

def get_session_user_agents(session_id: str) -> list:
    """Get previous user agents for a session"""
    # In a real implementation, this would query a session tracking database
    return []

def get_concurrent_sessions(user_id: str) -> list:
    """Get concurrent sessions for a user"""
    # In a real implementation, this would query active sessions
    return []

def has_after_hours_access(user_id: str) -> bool:
    """Check if user has after-hours access privileges"""
    # In a real implementation, this would check user permissions
    # For this example, assume no after-hours access unless explicitly granted
    return False

def is_trusted_ip_range(ip_address: str) -> bool:
    """Check if IP address is in trusted ranges"""
    # Define trusted IP ranges (these should match your organization's ranges)
    trusted_ranges = [
        '203.0.113.0/24',
        '198.51.100.0/24',
        '10.0.0.0/8',
        '172.16.0.0/12',
        '192.168.0.0/16'
    ]
    
    try:
        import ipaddress
        ip = ipaddress.ip_address(ip_address)
        
        for range_str in trusted_ranges:
            if ip in ipaddress.ip_network(range_str):
                return True
                
        return False
        
    except Exception as e:
        logger.error(f"Error checking IP range: {str(e)}")
        return False

def is_suspicious_activity(session_id: str, user_id: str) -> bool:
    """Detect suspicious activity patterns"""
    # In a real implementation, this would use ML models or rule-based detection
    # to identify suspicious patterns like:
    # - Rapid API calls
    # - Access to unusual resources
    # - Geographic anomalies
    # - Behavioral anomalies
    
    # For this example, return False (no suspicious activity)
    return False