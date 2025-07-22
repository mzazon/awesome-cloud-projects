#!/usr/bin/env python3
"""
AWS Security Hub Threat Intelligence Lambda Function

This function enriches Security Hub findings with threat intelligence data,
providing additional context for security incidents. It extracts indicators
of compromise (IOCs) from findings and scores them based on threat intelligence feeds.

Features:
- Automatic IOC extraction from security findings
- Threat scoring based on multiple factors
- Security Hub finding enrichment
- Support for IP addresses, domains, and file hashes
- Extensible architecture for third-party threat intelligence integration

Environment Variables:
- AWS_REGION: AWS region for API calls

Note: This is a demonstration implementation. In production, integrate with
commercial threat intelligence feeds like VirusTotal, AlienVault OTX, or
enterprise threat intelligence platforms.
"""

import json
import boto3
import os
import re
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional, Set
from urllib.parse import urlparse

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
securityhub = boto3.client('securityhub')

# Threat intelligence configuration
THREAT_INTELLIGENCE_CONFIG = {
    'scoring': {
        'base_score': 10,
        'indicator_multiplier': 5,
        'severity_multiplier': {
            'CRITICAL': 3.0,
            'HIGH': 2.5,
            'MEDIUM': 2.0,
            'LOW': 1.5,
            'INFORMATIONAL': 1.0
        }
    },
    'thresholds': {
        'high_risk': 70,
        'medium_risk': 40,
        'low_risk': 20
    }
}

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for threat intelligence processing.
    
    Args:
        event: EventBridge event containing Security Hub finding
        context: Lambda runtime context
        
    Returns:
        Dict containing threat intelligence results
    """
    try:
        logger.info(f"Processing threat intelligence event: {json.dumps(event, default=str)}")
        
        # Extract finding from event
        finding = extract_finding_from_event(event)
        if not finding:
            logger.error("No valid finding found in event")
            return create_error_response("No valid finding found in event")
        
        # Extract threat indicators from finding
        threat_indicators = extract_threat_indicators(finding)
        logger.info(f"Extracted {len(threat_indicators)} threat indicators")
        
        # Perform threat intelligence lookup
        threat_analysis = perform_threat_analysis(threat_indicators, finding)
        
        # Enrich finding with threat intelligence
        enrichment_result = enrich_finding_with_threat_intelligence(finding, threat_analysis)
        
        # Create response
        response = create_success_response(finding, threat_analysis, enrichment_result)
        logger.info(f"Threat intelligence processing completed: {response}")
        
        return response
        
    except Exception as e:
        logger.error(f"Error processing threat intelligence: {str(e)}", exc_info=True)
        return create_error_response(str(e))

def extract_finding_from_event(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Extract Security Hub finding from EventBridge event.
    
    Args:
        event: EventBridge event
        
    Returns:
        Security Hub finding dictionary or None
    """
    try:
        # Handle different event types
        if 'detail' in event and 'findings' in event['detail']:
            findings = event['detail']['findings']
            if isinstance(findings, list) and len(findings) > 0:
                return findings[0]
        
        # Handle custom action events
        if 'detail' in event and 'finding' in event['detail']:
            return event['detail']['finding']
            
        return None
        
    except (KeyError, IndexError, TypeError) as e:
        logger.error(f"Error extracting finding from event: {str(e)}")
        return None

def extract_threat_indicators(finding: Dict[str, Any]) -> Dict[str, Set[str]]:
    """
    Extract threat indicators from Security Hub finding.
    
    Args:
        finding: Security Hub finding dictionary
        
    Returns:
        Dictionary of indicator types and their values
    """
    indicators = {
        'ip_addresses': set(),
        'domains': set(),
        'urls': set(),
        'file_hashes': set(),
        'email_addresses': set()
    }
    
    # Extract text fields for analysis
    text_fields = [
        finding.get('Title', ''),
        finding.get('Description', ''),
        json.dumps(finding.get('Resources', [])),
        json.dumps(finding.get('ProductFields', {})),
        json.dumps(finding.get('UserDefinedFields', {}))
    ]
    
    full_text = ' '.join(text_fields)
    
    # Extract IP addresses
    ip_pattern = r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b'
    ip_matches = re.findall(ip_pattern, full_text)
    for ip in ip_matches:
        if is_valid_ip(ip):
            indicators['ip_addresses'].add(ip)
    
    # Extract domains
    domain_pattern = r'\b[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z]{2,}\b'
    domain_matches = re.findall(domain_pattern, full_text)
    for match in domain_matches:
        domain = match[0] + '.' + match[1] if match[1] else match[0]
        if is_valid_domain(domain):
            indicators['domains'].add(domain)
    
    # Extract URLs
    url_pattern = r'https?://[^\s<>"{}|\\^`\[\]]+'
    url_matches = re.findall(url_pattern, full_text)
    for url in url_matches:
        if is_valid_url(url):
            indicators['urls'].add(url)
            # Also extract domain from URL
            parsed = urlparse(url)
            if parsed.netloc and is_valid_domain(parsed.netloc):
                indicators['domains'].add(parsed.netloc)
    
    # Extract file hashes (MD5, SHA1, SHA256)
    hash_patterns = {
        'md5': r'\b[a-fA-F0-9]{32}\b',
        'sha1': r'\b[a-fA-F0-9]{40}\b',
        'sha256': r'\b[a-fA-F0-9]{64}\b'
    }
    
    for hash_type, pattern in hash_patterns.items():
        hash_matches = re.findall(pattern, full_text)
        for hash_value in hash_matches:
            indicators['file_hashes'].add(hash_value.lower())
    
    # Extract email addresses
    email_pattern = r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b'
    email_matches = re.findall(email_pattern, full_text)
    for email in email_matches:
        if is_valid_email(email):
            indicators['email_addresses'].add(email.lower())
    
    # Convert sets to lists for JSON serialization and remove empty sets
    return {k: list(v) for k, v in indicators.items() if v}

def is_valid_ip(ip: str) -> bool:
    """
    Validate IP address and filter out private/reserved ranges.
    
    Args:
        ip: IP address string
        
    Returns:
        True if valid public IP address
    """
    try:
        parts = ip.split('.')
        if len(parts) != 4:
            return False
        
        octets = [int(part) for part in parts]
        
        # Check range validity
        if not all(0 <= octet <= 255 for octet in octets):
            return False
        
        # Filter out private and reserved ranges
        if (octets[0] == 10 or
            (octets[0] == 172 and 16 <= octets[1] <= 31) or
            (octets[0] == 192 and octets[1] == 168) or
            octets[0] == 127 or
            octets[0] >= 224):
            return False
        
        return True
        
    except (ValueError, IndexError):
        return False

def is_valid_domain(domain: str) -> bool:
    """
    Validate domain name and filter out common false positives.
    
    Args:
        domain: Domain name string
        
    Returns:
        True if valid domain
    """
    # Filter out common false positives
    false_positives = {
        'amazonaws.com', 'amazon.com', 'aws.com', 'microsoft.com',
        'google.com', 'github.com', 'stackoverflow.com', 'wikipedia.org'
    }
    
    if domain.lower() in false_positives:
        return False
    
    # Basic domain validation
    if len(domain) < 4 or len(domain) > 253:
        return False
    
    if domain.startswith('.') or domain.endswith('.'):
        return False
    
    return True

def is_valid_url(url: str) -> bool:
    """
    Validate URL and filter out common false positives.
    
    Args:
        url: URL string
        
    Returns:
        True if valid suspicious URL
    """
    try:
        parsed = urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            return False
        
        # Filter out common legitimate domains
        legitimate_domains = {
            'amazonaws.com', 'amazon.com', 'aws.com', 'microsoft.com',
            'google.com', 'github.com', 'stackoverflow.com'
        }
        
        domain = parsed.netloc.lower()
        for legit_domain in legitimate_domains:
            if domain.endswith(legit_domain):
                return False
        
        return True
        
    except Exception:
        return False

def is_valid_email(email: str) -> bool:
    """
    Validate email address and filter out common false positives.
    
    Args:
        email: Email address string
        
    Returns:
        True if valid email
    """
    # Filter out common legitimate domains
    legitimate_domains = {
        'amazon.com', 'aws.com', 'microsoft.com', 'google.com'
    }
    
    domain = email.split('@')[-1].lower()
    return domain not in legitimate_domains

def perform_threat_analysis(indicators: Dict[str, List[str]], finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Perform threat intelligence analysis on extracted indicators.
    
    Args:
        indicators: Dictionary of threat indicators
        finding: Original Security Hub finding
        
    Returns:
        Threat analysis results
    """
    analysis_results = {
        'threat_score': 0,
        'risk_level': 'UNKNOWN',
        'indicator_analysis': {},
        'threat_categories': [],
        'confidence_score': 0,
        'recommended_actions': []
    }
    
    # Calculate base threat score
    base_score = THREAT_INTELLIGENCE_CONFIG['scoring']['base_score']
    indicator_count = sum(len(indicator_list) for indicator_list in indicators.values())
    indicator_bonus = indicator_count * THREAT_INTELLIGENCE_CONFIG['scoring']['indicator_multiplier']
    
    # Apply severity multiplier
    severity = finding.get('Severity', {}).get('Label', 'INFORMATIONAL')
    severity_multiplier = THREAT_INTELLIGENCE_CONFIG['scoring']['severity_multiplier'].get(severity, 1.0)
    
    threat_score = int((base_score + indicator_bonus) * severity_multiplier)
    threat_score = min(threat_score, 100)  # Cap at 100
    
    analysis_results['threat_score'] = threat_score
    analysis_results['risk_level'] = calculate_risk_level(threat_score)
    
    # Analyze individual indicators
    for indicator_type, indicator_list in indicators.items():
        analysis_results['indicator_analysis'][indicator_type] = analyze_indicator_type(
            indicator_type, indicator_list, finding
        )
    
    # Determine threat categories based on finding types and indicators
    analysis_results['threat_categories'] = determine_threat_categories(finding, indicators)
    
    # Calculate confidence score
    analysis_results['confidence_score'] = calculate_confidence_score(indicators, finding)
    
    # Generate recommended actions
    analysis_results['recommended_actions'] = generate_recommended_actions(
        analysis_results['risk_level'], 
        analysis_results['threat_categories'],
        indicators
    )
    
    return analysis_results

def calculate_risk_level(threat_score: int) -> str:
    """
    Calculate risk level based on threat score.
    
    Args:
        threat_score: Numerical threat score (0-100)
        
    Returns:
        Risk level string
    """
    thresholds = THREAT_INTELLIGENCE_CONFIG['thresholds']
    
    if threat_score >= thresholds['high_risk']:
        return 'HIGH'
    elif threat_score >= thresholds['medium_risk']:
        return 'MEDIUM'
    elif threat_score >= thresholds['low_risk']:
        return 'LOW'
    else:
        return 'MINIMAL'

def analyze_indicator_type(indicator_type: str, indicators: List[str], finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze specific type of threat indicators.
    
    Args:
        indicator_type: Type of indicator (ip_addresses, domains, etc.)
        indicators: List of indicators of this type
        finding: Original Security Hub finding
        
    Returns:
        Analysis results for this indicator type
    """
    analysis = {
        'count': len(indicators),
        'indicators': indicators,
        'risk_assessment': {},
        'notes': []
    }
    
    if indicator_type == 'ip_addresses':
        analysis['risk_assessment'] = assess_ip_addresses(indicators)
    elif indicator_type == 'domains':
        analysis['risk_assessment'] = assess_domains(indicators)
    elif indicator_type == 'file_hashes':
        analysis['risk_assessment'] = assess_file_hashes(indicators)
    elif indicator_type == 'urls':
        analysis['risk_assessment'] = assess_urls(indicators)
    elif indicator_type == 'email_addresses':
        analysis['risk_assessment'] = assess_email_addresses(indicators)
    
    return analysis

def assess_ip_addresses(ip_addresses: List[str]) -> Dict[str, Any]:
    """
    Assess risk of IP addresses.
    
    Args:
        ip_addresses: List of IP addresses
        
    Returns:
        Risk assessment for IP addresses
    """
    assessment = {
        'total_count': len(ip_addresses),
        'unique_subnets': len(set(ip.rsplit('.', 1)[0] for ip in ip_addresses)),
        'geographic_distribution': 'UNKNOWN',  # Would integrate with GeoIP
        'reputation_scores': {},  # Would integrate with reputation services
        'recommended_monitoring': True
    }
    
    return assessment

def assess_domains(domains: List[str]) -> Dict[str, Any]:
    """
    Assess risk of domains.
    
    Args:
        domains: List of domain names
        
    Returns:
        Risk assessment for domains
    """
    assessment = {
        'total_count': len(domains),
        'suspicious_tlds': [],
        'dga_likelihood': 'LOW',  # Domain Generation Algorithm likelihood
        'homograph_attacks': [],
        'recommended_blocking': []
    }
    
    # Check for suspicious TLDs
    suspicious_tlds = {'.tk', '.ml', '.ga', '.cf', '.bit'}
    for domain in domains:
        for tld in suspicious_tlds:
            if domain.endswith(tld):
                assessment['suspicious_tlds'].append(domain)
    
    # Simple DGA detection (length and character distribution)
    for domain in domains:
        domain_name = domain.split('.')[0]
        if len(domain_name) > 12 and has_random_pattern(domain_name):
            assessment['dga_likelihood'] = 'MEDIUM'
    
    return assessment

def assess_file_hashes(file_hashes: List[str]) -> Dict[str, Any]:
    """
    Assess risk of file hashes.
    
    Args:
        file_hashes: List of file hashes
        
    Returns:
        Risk assessment for file hashes
    """
    assessment = {
        'total_count': len(file_hashes),
        'hash_types': {},
        'malware_likelihood': 'UNKNOWN',
        'recommended_sandboxing': True
    }
    
    # Categorize hash types
    for hash_value in file_hashes:
        hash_length = len(hash_value)
        if hash_length == 32:
            hash_type = 'MD5'
        elif hash_length == 40:
            hash_type = 'SHA1'
        elif hash_length == 64:
            hash_type = 'SHA256'
        else:
            hash_type = 'UNKNOWN'
        
        assessment['hash_types'][hash_type] = assessment['hash_types'].get(hash_type, 0) + 1
    
    return assessment

def assess_urls(urls: List[str]) -> Dict[str, Any]:
    """
    Assess risk of URLs.
    
    Args:
        urls: List of URLs
        
    Returns:
        Risk assessment for URLs
    """
    assessment = {
        'total_count': len(urls),
        'suspicious_patterns': [],
        'url_shorteners': [],
        'phishing_likelihood': 'LOW'
    }
    
    # Check for URL shorteners and suspicious patterns
    shortener_domains = {'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'ow.ly'}
    
    for url in urls:
        parsed = urlparse(url)
        domain = parsed.netloc.lower()
        
        if any(shortener in domain for shortener in shortener_domains):
            assessment['url_shorteners'].append(url)
        
        # Check for suspicious patterns
        if any(pattern in url.lower() for pattern in ['login', 'verify', 'secure', 'account']):
            assessment['suspicious_patterns'].append(url)
            assessment['phishing_likelihood'] = 'MEDIUM'
    
    return assessment

def assess_email_addresses(email_addresses: List[str]) -> Dict[str, Any]:
    """
    Assess risk of email addresses.
    
    Args:
        email_addresses: List of email addresses
        
    Returns:
        Risk assessment for email addresses
    """
    assessment = {
        'total_count': len(email_addresses),
        'suspicious_domains': [],
        'typosquatting_likelihood': 'LOW',
        'recommended_monitoring': True
    }
    
    # Check for suspicious patterns
    for email in email_addresses:
        domain = email.split('@')[-1].lower()
        
        # Check for typosquatting attempts
        if any(legit in domain for legit in ['amaz0n', 'micr0soft', 'g00gle']):
            assessment['suspicious_domains'].append(domain)
            assessment['typosquatting_likelihood'] = 'HIGH'
    
    return assessment

def has_random_pattern(text: str) -> bool:
    """
    Check if text has a random pattern (simple heuristic).
    
    Args:
        text: Text to analyze
        
    Returns:
        True if text appears to have random pattern
    """
    vowels = set('aeiou')
    consonants = set('bcdfghjklmnpqrstvwxyz')
    
    vowel_count = sum(1 for char in text.lower() if char in vowels)
    consonant_count = sum(1 for char in text.lower() if char in consonants)
    
    if len(text) == 0:
        return False
    
    vowel_ratio = vowel_count / len(text)
    
    # If very few vowels or very many consonants in a row, likely random
    return vowel_ratio < 0.15 or has_long_consonant_sequences(text.lower())

def has_long_consonant_sequences(text: str) -> bool:
    """
    Check for long consonant sequences.
    
    Args:
        text: Text to analyze
        
    Returns:
        True if text has long consonant sequences
    """
    vowels = set('aeiou')
    consonant_streak = 0
    max_streak = 0
    
    for char in text:
        if char.isalpha():
            if char not in vowels:
                consonant_streak += 1
                max_streak = max(max_streak, consonant_streak)
            else:
                consonant_streak = 0
    
    return max_streak >= 4

def determine_threat_categories(finding: Dict[str, Any], indicators: Dict[str, List[str]]) -> List[str]:
    """
    Determine threat categories based on finding and indicators.
    
    Args:
        finding: Security Hub finding
        indicators: Extracted threat indicators
        
    Returns:
        List of threat categories
    """
    categories = []
    
    finding_types = finding.get('Types', [])
    finding_title = finding.get('Title', '').lower()
    finding_description = finding.get('Description', '').lower()
    
    # Malware indicators
    if (any('malware' in str(ftype).lower() for ftype in finding_types) or
        'malware' in finding_title or 'virus' in finding_title):
        categories.append('MALWARE')
    
    # Data exfiltration indicators
    if (any('exfiltration' in str(ftype).lower() for ftype in finding_types) or
        'exfiltration' in finding_title or 'data transfer' in finding_description):
        categories.append('DATA_EXFILTRATION')
    
    # Command and control indicators
    if (indicators.get('domains') or indicators.get('ip_addresses')):
        categories.append('COMMAND_AND_CONTROL')
    
    # Phishing indicators
    if (indicators.get('urls') or indicators.get('email_addresses') or
        'phishing' in finding_title):
        categories.append('PHISHING')
    
    # Backdoor indicators
    if 'backdoor' in finding_title or 'trojan' in finding_title:
        categories.append('BACKDOOR')
    
    # Cryptocurrency mining
    if 'cryptocurrency' in finding_title or 'mining' in finding_title:
        categories.append('CRYPTOCURRENCY_MINING')
    
    return categories if categories else ['UNKNOWN']

def calculate_confidence_score(indicators: Dict[str, List[str]], finding: Dict[str, Any]) -> int:
    """
    Calculate confidence score for threat analysis.
    
    Args:
        indicators: Extracted threat indicators
        finding: Security Hub finding
        
    Returns:
        Confidence score (0-100)
    """
    base_confidence = 30
    
    # Increase confidence based on number of indicators
    indicator_count = sum(len(indicator_list) for indicator_list in indicators.values())
    indicator_bonus = min(indicator_count * 10, 40)
    
    # Increase confidence based on finding severity
    severity = finding.get('Severity', {}).get('Label', 'INFORMATIONAL')
    severity_bonus = {
        'CRITICAL': 20,
        'HIGH': 15,
        'MEDIUM': 10,
        'LOW': 5,
        'INFORMATIONAL': 0
    }.get(severity, 0)
    
    # Increase confidence if multiple indicator types present
    type_diversity_bonus = min(len(indicators) * 5, 20)
    
    confidence = base_confidence + indicator_bonus + severity_bonus + type_diversity_bonus
    return min(confidence, 100)

def generate_recommended_actions(risk_level: str, threat_categories: List[str], indicators: Dict[str, List[str]]) -> List[str]:
    """
    Generate recommended actions based on threat analysis.
    
    Args:
        risk_level: Calculated risk level
        threat_categories: Identified threat categories
        indicators: Extracted threat indicators
        
    Returns:
        List of recommended actions
    """
    actions = []
    
    # Risk level based actions
    if risk_level == 'HIGH':
        actions.extend([
            'Immediately isolate affected systems',
            'Activate incident response team',
            'Begin forensic data collection',
            'Notify executive management'
        ])
    elif risk_level == 'MEDIUM':
        actions.extend([
            'Investigate affected systems',
            'Enhance monitoring on related resources',
            'Review network traffic patterns',
            'Update security controls'
        ])
    elif risk_level == 'LOW':
        actions.extend([
            'Monitor for additional indicators',
            'Review security configurations',
            'Update threat detection rules'
        ])
    
    # Category-specific actions
    if 'MALWARE' in threat_categories:
        actions.append('Run comprehensive malware scans')
    
    if 'DATA_EXFILTRATION' in threat_categories:
        actions.extend([
            'Review data access logs',
            'Check for unauthorized data transfers'
        ])
    
    if 'PHISHING' in threat_categories:
        actions.extend([
            'Block suspicious URLs and domains',
            'Alert users about phishing campaign'
        ])
    
    # Indicator-specific actions
    if indicators.get('ip_addresses'):
        actions.append('Block malicious IP addresses at network perimeter')
    
    if indicators.get('domains'):
        actions.append('Add malicious domains to DNS blocking lists')
    
    if indicators.get('file_hashes'):
        actions.append('Scan systems for malicious file hashes')
    
    return list(set(actions))  # Remove duplicates

def enrich_finding_with_threat_intelligence(finding: Dict[str, Any], threat_analysis: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enrich Security Hub finding with threat intelligence data.
    
    Args:
        finding: Original Security Hub finding
        threat_analysis: Threat intelligence analysis results
        
    Returns:
        Enrichment operation result
    """
    try:
        # Create note with threat intelligence summary
        note_text = create_threat_intelligence_note(threat_analysis)
        
        # Create user-defined fields with threat data
        user_defined_fields = {
            'ThreatScore': str(threat_analysis['threat_score']),
            'RiskLevel': threat_analysis['risk_level'],
            'ThreatCategories': ','.join(threat_analysis['threat_categories']),
            'ConfidenceScore': str(threat_analysis['confidence_score']),
            'IndicatorCount': str(sum(
                len(indicators) for indicators in threat_analysis['indicator_analysis'].values()
            )),
            'ThreatIntelligenceTimestamp': datetime.utcnow().isoformat()
        }
        
        # Update finding in Security Hub
        response = securityhub.batch_update_findings(
            FindingIdentifiers=[{
                'Id': finding['Id'],
                'ProductArn': finding['ProductArn']
            }],
            Note={
                'Text': note_text,
                'UpdatedBy': 'ThreatIntelligence'
            },
            UserDefinedFields=user_defined_fields
        )
        
        logger.info(f"Finding enriched with threat intelligence: {finding['Id']}")
        
        return {
            'success': True,
            'finding_id': finding['Id'],
            'threat_score': threat_analysis['threat_score'],
            'risk_level': threat_analysis['risk_level']
        }
        
    except Exception as e:
        logger.error(f"Error enriching finding with threat intelligence: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def create_threat_intelligence_note(threat_analysis: Dict[str, Any]) -> str:
    """
    Create formatted note with threat intelligence summary.
    
    Args:
        threat_analysis: Threat analysis results
        
    Returns:
        Formatted note text
    """
    note_lines = [
        f"THREAT INTELLIGENCE ANALYSIS",
        f"Threat Score: {threat_analysis['threat_score']}/100",
        f"Risk Level: {threat_analysis['risk_level']}",
        f"Confidence: {threat_analysis['confidence_score']}%",
        f"Categories: {', '.join(threat_analysis['threat_categories'])}",
        f""
    ]
    
    # Add indicator summary
    indicator_summary = []
    for indicator_type, analysis in threat_analysis['indicator_analysis'].items():
        if analysis['count'] > 0:
            indicator_summary.append(f"{indicator_type}: {analysis['count']}")
    
    if indicator_summary:
        note_lines.extend([
            f"Indicators Found:",
            f"- {'; '.join(indicator_summary)}"
        ])
    
    # Add recommended actions
    if threat_analysis['recommended_actions']:
        note_lines.extend([
            f"",
            f"Recommended Actions:",
            *[f"- {action}" for action in threat_analysis['recommended_actions'][:5]]  # Limit to 5
        ])
    
    note_lines.append(f"Analysis generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}")
    
    return '\n'.join(note_lines)

def create_success_response(finding: Dict[str, Any], threat_analysis: Dict[str, Any], enrichment_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create success response for Lambda function.
    
    Args:
        finding: Original Security Hub finding
        threat_analysis: Threat analysis results
        enrichment_result: Finding enrichment result
        
    Returns:
        Success response dictionary
    """
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Threat intelligence analysis completed',
            'finding_id': finding['Id'],
            'threat_intelligence': {
                'threat_score': threat_analysis['threat_score'],
                'risk_level': threat_analysis['risk_level'],
                'confidence_score': threat_analysis['confidence_score'],
                'threat_categories': threat_analysis['threat_categories'],
                'indicators_found': sum(
                    len(indicators) for indicators in threat_analysis['indicator_analysis'].values()
                )
            },
            'enrichment_success': enrichment_result['success'],
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def create_error_response(error_message: str) -> Dict[str, Any]:
    """
    Create error response for Lambda function.
    
    Args:
        error_message: Error description
        
    Returns:
        Error response dictionary
    """
    return {
        'statusCode': 500,
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.utcnow().isoformat()
        })
    }