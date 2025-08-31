"""
Threat Intelligence Enrichment Function for Chronicle SOAR Integration
Processes security alerts from Security Command Center and enriches them with threat intelligence
"""

import json
import base64
import requests
import hashlib
import time
from typing import Dict, List, Any
from google.cloud import pubsub_v1
from google.cloud import logging
import os

# Initialize clients
publisher = pubsub_v1.PublisherClient()
logging_client = logging.Client()
logger = logging_client.logger('security-automation')

def threat_enrichment(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main entry point for threat enrichment function.
    Enriches security alerts with threat intelligence for Chronicle SOAR processing.
    
    Args:
        event: Pub/Sub event containing security alert data
        context: Cloud Function context (unused)
        
    Returns:
        Dict containing processing status and entity count
    """
    try:
        # Decode Pub/Sub message
        if 'data' not in event:
            logger.error("No data field in Pub/Sub event")
            return {'status': 'error', 'message': 'Invalid event format'}
            
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        alert_data = json.loads(pubsub_message)
        
        # Extract finding information
        finding = alert_data.get('finding', {})
        if not finding:
            logger.warning("No finding data in alert")
            return {'status': 'skipped', 'reason': 'No finding data'}
        
        # Log incoming alert for audit trail
        logger.info(f"Processing security alert: {finding.get('name', 'unknown')}")
        
        # Enrich alert with threat intelligence
        enriched_alert = enrich_security_alert(finding)
        
        # Publish enriched alert for Chronicle SOAR processing
        publish_enriched_alert(enriched_alert)
        
        logger.info(f"Successfully enriched alert with {len(enriched_alert['entity_list'])} entities")
        
        return {
            'status': 'enriched',
            'entities_found': len(enriched_alert['entity_list']),
            'severity_score': enriched_alert['severity_score'],
            'recommended_actions': len(enriched_alert['recommended_actions'])
        }
        
    except Exception as e:
        logger.error(f"Error processing security alert: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def enrich_security_alert(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enriches a security finding with threat intelligence and contextual information.
    
    Args:
        finding: Security Command Center finding data
        
    Returns:
        Dict containing enriched alert data
    """
    # Extract basic finding information
    source_properties = finding.get('sourceProperties', {})
    category = finding.get('category', '')
    severity = finding.get('severity', 'LOW')
    
    # Calculate dynamic severity score
    severity_score = calculate_severity_score(finding)
    
    # Extract security entities for loop processing
    entity_list = extract_security_entities(finding)
    
    # Generate recommended response actions
    recommended_actions = generate_response_actions(finding)
    
    # Add threat intelligence context
    threat_context = analyze_threat_context(finding, entity_list)
    
    # Create enriched alert structure
    enriched_alert = {
        'original_finding': finding,
        'finding_id': finding.get('name', ''),
        'category': category,
        'severity': severity,
        'severity_score': severity_score,
        'entity_list': entity_list,
        'recommended_actions': recommended_actions,
        'threat_context': threat_context,
        'timestamp': finding.get('eventTime', time.strftime('%Y-%m-%dT%H:%M:%S.%fZ')),
        'source': finding.get('category', 'unknown'),
        'resource_name': finding.get('resourceName', ''),
        'enrichment_metadata': {
            'enriched_at': time.strftime('%Y-%m-%dT%H:%M:%S.%fZ'),
            'enrichment_version': '1.0',
            'processor': 'threat-enrichment-function'
        }
    }
    
    return enriched_alert

def calculate_severity_score(finding: Dict[str, Any]) -> int:
    """
    Calculate dynamic severity score based on multiple factors.
    Score ranges from 1-10 with 10 being most critical.
    
    Args:
        finding: Security Command Center finding
        
    Returns:
        Integer severity score (1-10)
    """
    # Base score from finding severity
    severity_mapping = {
        'CRITICAL': 10,
        'HIGH': 8,
        'MEDIUM': 5,
        'LOW': 2
    }
    
    base_score = severity_mapping.get(finding.get('severity', 'LOW'), 2)
    
    # Adjust score based on resource context
    resource_name = finding.get('resourceName', '').lower()
    
    # Production environments get higher scores
    if any(keyword in resource_name for keyword in ['prod', 'production', 'live']):
        base_score += 2
    
    # Database and critical infrastructure adjustments
    if any(keyword in resource_name for keyword in ['database', 'db', 'sql', 'data']):
        base_score += 1
    
    # Network security issues get higher priority
    category = finding.get('category', '').lower()
    if any(keyword in category for keyword in ['network', 'firewall', 'intrusion']):
        base_score += 1
    
    # Malware and compromise indicators
    if any(keyword in category for keyword in ['malware', 'compromise', 'backdoor']):
        base_score += 2
    
    # Cap at maximum score
    return min(base_score, 10)

def extract_security_entities(finding: Dict[str, Any]) -> List[Dict[str, str]]:
    """
    Extract security entities (IPs, hashes, domains) for Chronicle SOAR loop processing.
    
    Args:
        finding: Security Command Center finding
        
    Returns:
        List of entity dictionaries with type and value
    """
    entities = []
    source_properties = finding.get('sourceProperties', {})
    
    # Extract IP addresses from connections
    connections = source_properties.get('connections', [])
    for conn in connections:
        if 'sourceIp' in conn:
            entities.append({
                'type': 'ip_address',
                'value': conn['sourceIp'],
                'context': 'source_connection'
            })
        if 'destinationIp' in conn:
            entities.append({
                'type': 'ip_address', 
                'value': conn['destinationIp'],
                'context': 'destination_connection'
            })
    
    # Extract file hashes
    files = source_properties.get('files', [])
    for file_info in files:
        if 'sha256' in file_info:
            entities.append({
                'type': 'file_hash',
                'value': file_info['sha256'],
                'context': 'file_sha256',
                'file_name': file_info.get('path', 'unknown')
            })
        if 'md5' in file_info:
            entities.append({
                'type': 'file_hash',
                'value': file_info['md5'],
                'context': 'file_md5',
                'file_name': file_info.get('path', 'unknown')
            })
    
    # Extract domains and URLs
    if 'urls' in source_properties:
        for url_info in source_properties['urls']:
            url = url_info.get('url', '')
            if url:
                entities.append({
                    'type': 'url',
                    'value': url,
                    'context': 'suspicious_url'
                })
                
                # Extract domain from URL
                try:
                    from urllib.parse import urlparse
                    domain = urlparse(url).netloc
                    if domain:
                        entities.append({
                            'type': 'domain',
                            'value': domain,
                            'context': 'extracted_from_url'
                        })
                except:
                    pass
    
    # Extract process information
    processes = source_properties.get('processes', [])
    for process in processes:
        if 'binary' in process and 'sha256' in process['binary']:
            entities.append({
                'type': 'file_hash',
                'value': process['binary']['sha256'],
                'context': 'process_binary',
                'process_name': process.get('name', 'unknown')
            })
    
    # Remove duplicates while preserving order
    seen = set()
    unique_entities = []
    for entity in entities:
        entity_key = f"{entity['type']}:{entity['value']}"
        if entity_key not in seen:
            seen.add(entity_key)
            unique_entities.append(entity)
    
    return unique_entities

def generate_response_actions(finding: Dict[str, Any]) -> List[str]:
    """
    Generate recommended response actions based on finding type and severity.
    
    Args:
        finding: Security Command Center finding
        
    Returns:
        List of recommended action strings
    """
    actions = []
    category = finding.get('category', '').lower()
    severity = finding.get('severity', 'LOW')
    
    # Actions based on threat category
    if 'malware' in category:
        actions.extend([
            'isolate_host',
            'scan_additional_files',
            'update_antimalware_signatures',
            'check_lateral_movement'
        ])
    
    elif 'network' in category or 'intrusion' in category:
        actions.extend([
            'block_source_ip',
            'analyze_network_traffic',
            'update_firewall_rules',
            'check_compromised_accounts'
        ])
    
    elif 'data' in category or 'exfiltration' in category:
        actions.extend([
            'restrict_data_access',
            'audit_data_access_logs',
            'notify_data_protection_team',
            'assess_data_exposure'
        ])
    
    elif 'privilege' in category or 'escalation' in category:
        actions.extend([
            'revoke_elevated_privileges',
            'audit_privilege_changes',
            'review_access_controls',
            'check_admin_accounts'
        ])
    
    # Severity-based actions
    if severity in ['HIGH', 'CRITICAL']:
        actions.extend([
            'notify_security_team',
            'create_high_priority_ticket',
            'initiate_incident_response'
        ])
    
    # Always include basic response actions
    actions.extend([
        'create_incident_ticket',
        'collect_forensic_evidence',
        'update_threat_intelligence'
    ])
    
    # Remove duplicates while preserving order
    return list(dict.fromkeys(actions))

def analyze_threat_context(finding: Dict[str, Any], entities: List[Dict[str, str]]) -> Dict[str, Any]:
    """
    Analyze threat context for better Chronicle SOAR decision making.
    
    Args:
        finding: Security Command Center finding
        entities: Extracted security entities
        
    Returns:
        Dict containing threat context analysis
    """
    context = {
        'entity_count': len(entities),
        'entity_types': list(set(entity['type'] for entity in entities)),
        'risk_indicators': [],
        'business_impact': 'unknown',
        'attack_stage': 'unknown'
    }
    
    # Analyze risk indicators
    category = finding.get('category', '').lower()
    
    if 'persistence' in category:
        context['risk_indicators'].append('persistence_mechanism')
        context['attack_stage'] = 'persistence'
    
    if 'lateral' in category or 'movement' in category:
        context['risk_indicators'].append('lateral_movement')
        context['attack_stage'] = 'lateral_movement'
    
    if 'exfiltration' in category or 'data' in category:
        context['risk_indicators'].append('data_exfiltration')
        context['attack_stage'] = 'exfiltration'
    
    if 'command' in category and 'control' in category:
        context['risk_indicators'].append('command_and_control')
        context['attack_stage'] = 'command_and_control'
    
    # Assess business impact based on resource
    resource_name = finding.get('resourceName', '').lower()
    if any(keyword in resource_name for keyword in ['prod', 'production', 'live']):
        context['business_impact'] = 'high'
    elif any(keyword in resource_name for keyword in ['staging', 'test']):
        context['business_impact'] = 'medium'
    else:
        context['business_impact'] = 'low'
    
    return context

def publish_enriched_alert(enriched_alert: Dict[str, Any]) -> None:
    """
    Publish enriched alert to Pub/Sub topic for Chronicle SOAR processing.
    
    Args:
        enriched_alert: Enriched security alert data
    """
    project_id = os.environ.get('GCP_PROJECT', '${project_id}')
    response_topic = os.environ.get('RESPONSE_TOPIC', '${response_topic}')
    
    topic_path = publisher.topic_path(project_id, response_topic)
    
    # Serialize alert data
    message_data = json.dumps(enriched_alert, indent=2).encode('utf-8')
    
    # Add message attributes for routing
    attributes = {
        'severity': enriched_alert['severity'],
        'category': enriched_alert['category'],
        'entity_count': str(len(enriched_alert['entity_list'])),
        'severity_score': str(enriched_alert['severity_score'])
    }
    
    # Publish message
    future = publisher.publish(topic_path, message_data, **attributes)
    message_id = future.result()
    
    logger.info(f"Published enriched alert to topic {response_topic}, message ID: {message_id}")

if __name__ == '__main__':
    # Test function locally
    test_event = {
        'data': base64.b64encode(json.dumps({
            'finding': {
                'name': 'test-finding',
                'category': 'MALWARE_DETECTION',
                'severity': 'HIGH',
                'eventTime': '2025-01-01T12:00:00Z',
                'resourceName': 'projects/test/instances/prod-web-server',
                'sourceProperties': {
                    'connections': [{'sourceIp': '192.168.1.100'}],
                    'files': [{'sha256': 'abc123def456', 'path': '/tmp/malware.exe'}]
                }
            }
        }).encode('utf-8')).decode('utf-8')
    }
    
    result = threat_enrichment(test_event, None)
    print(f"Test result: {result}")