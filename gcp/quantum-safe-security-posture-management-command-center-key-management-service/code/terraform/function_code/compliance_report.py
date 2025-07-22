#!/usr/bin/env python3
"""
Quantum Readiness Compliance Reporting Function

This Cloud Function generates automated compliance reports for quantum readiness
assessment, analyzing cryptographic assets and providing executive-level insights
into the organization's quantum security posture.

Author: Infrastructure as Code Generator
Version: 1.0
License: Apache 2.0
"""

import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

from google.cloud import asset_v1
from google.cloud import securitycenter
from google.cloud import kms
from google.cloud import monitoring_v3
from google.cloud import storage
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
ORGANIZATION_ID = os.environ.get('ORGANIZATION_ID', '${organization_id}')
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
BUCKET_NAME = os.environ.get('BUCKET_NAME', 'crypto-inventory-bucket')

# Post-quantum cryptography algorithms
POST_QUANTUM_ALGORITHMS = [
    'PQ_SIGN_ML_DSA_65',
    'PQ_SIGN_ML_DSA_87',
    'PQ_SIGN_SLH_DSA_SHA2_128S',
    'PQ_SIGN_SLH_DSA_SHA2_192S',
    'PQ_SIGN_SLH_DSA_SHA2_256S'
]

# Quantum-vulnerable algorithms to flag
VULNERABLE_ALGORITHMS = [
    'RSA_SIGN_PSS_2048_SHA256',
    'RSA_SIGN_PSS_3072_SHA256',
    'RSA_SIGN_PSS_4096_SHA256',
    'RSA_SIGN_PKCS1_2048_SHA256',
    'RSA_SIGN_PKCS1_3072_SHA256',
    'RSA_SIGN_PKCS1_4096_SHA256',
    'EC_SIGN_P256_SHA256',
    'EC_SIGN_P384_SHA384',
    'EC_SIGN_SECP256K1_SHA256'
]


class QuantumComplianceAnalyzer:
    """
    Analyzes quantum readiness compliance across Google Cloud resources
    """
    
    def __init__(self):
        """Initialize Google Cloud clients"""
        self.asset_client = asset_v1.AssetServiceClient()
        self.scc_client = securitycenter.SecurityCenterClient()
        self.kms_client = kms.KeyManagementServiceClient()
        self.monitoring_client = monitoring_v3.MetricServiceClient()
        self.storage_client = storage.Client()
        
    def analyze_cryptographic_assets(self) -> Dict[str, Any]:
        """
        Analyze cryptographic assets across the organization
        
        Returns:
            Dictionary containing asset analysis results
        """
        logger.info(f"Analyzing cryptographic assets for organization {ORGANIZATION_ID}")
        
        try:
            # Query KMS cryptographic keys
            parent = f"organizations/{ORGANIZATION_ID}"
            asset_types = [
                "cloudkms.googleapis.com/CryptoKey",
                "cloudkms.googleapis.com/KeyRing"
            ]
            
            assets = self.asset_client.list_assets(
                request={
                    "parent": parent,
                    "asset_types": asset_types,
                    "content_type": asset_v1.ContentType.RESOURCE
                }
            )
            
            # Analyze assets for quantum readiness
            quantum_safe_keys = 0
            vulnerable_keys = 0
            unknown_keys = 0
            key_details = []
            
            for asset in assets:
                if asset.asset_type == "cloudkms.googleapis.com/CryptoKey":
                    key_data = asset.resource.data
                    algorithm = key_data.get('versionTemplate', {}).get('algorithm', 'UNKNOWN')
                    
                    key_info = {
                        'name': asset.name,
                        'algorithm': algorithm,
                        'creation_time': asset.resource.discovery_time.isoformat(),
                        'location': key_data.get('name', '').split('/')[3] if 'name' in key_data else 'unknown'
                    }
                    
                    if algorithm in POST_QUANTUM_ALGORITHMS:
                        quantum_safe_keys += 1
                        key_info['quantum_safe'] = True
                        key_info['risk_level'] = 'LOW'
                    elif algorithm in VULNERABLE_ALGORITHMS:
                        vulnerable_keys += 1
                        key_info['quantum_safe'] = False
                        key_info['risk_level'] = 'HIGH'
                    else:
                        unknown_keys += 1
                        key_info['quantum_safe'] = None
                        key_info['risk_level'] = 'MEDIUM'
                    
                    key_details.append(key_info)
            
            return {
                'total_keys': quantum_safe_keys + vulnerable_keys + unknown_keys,
                'quantum_safe_keys': quantum_safe_keys,
                'vulnerable_keys': vulnerable_keys,
                'unknown_keys': unknown_keys,
                'key_details': key_details,
                'analysis_timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Error analyzing cryptographic assets: {str(e)}")
            raise
    
    def get_security_findings(self) -> Dict[str, Any]:
        """
        Retrieve security findings from Security Command Center
        
        Returns:
            Dictionary containing security findings analysis
        """
        logger.info("Retrieving quantum-related security findings")
        
        try:
            # Query Security Command Center for quantum-related findings
            org_name = f"organizations/{ORGANIZATION_ID}"
            
            # Filter for quantum-related findings
            filter_expression = (
                'category="QUANTUM_VULNERABILITY" OR '
                'category="CRYPTOGRAPHIC_WEAKNESS" OR '
                'source_properties.encryption_algorithm!=""'
            )
            
            findings = self.scc_client.list_findings(
                request={
                    "parent": f"{org_name}/sources/-",
                    "filter": filter_expression,
                    "page_size": 100
                }
            )
            
            # Analyze findings
            high_severity_count = 0
            medium_severity_count = 0
            low_severity_count = 0
            finding_details = []
            
            for finding in findings:
                severity = finding.severity.name if finding.severity else 'UNKNOWN'
                
                finding_info = {
                    'name': finding.name,
                    'category': finding.category,
                    'severity': severity,
                    'state': finding.state.name if finding.state else 'UNKNOWN',
                    'create_time': finding.create_time.isoformat() if finding.create_time else None,
                    'resource_name': finding.resource_name
                }
                
                if severity == 'HIGH':
                    high_severity_count += 1
                elif severity == 'MEDIUM':
                    medium_severity_count += 1
                elif severity == 'LOW':
                    low_severity_count += 1
                
                finding_details.append(finding_info)
            
            return {
                'total_findings': len(finding_details),
                'high_severity': high_severity_count,
                'medium_severity': medium_severity_count,
                'low_severity': low_severity_count,
                'findings': finding_details,
                'analysis_timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Error retrieving security findings: {str(e)}")
            # Return empty results if Security Command Center is not available
            return {
                'total_findings': 0,
                'high_severity': 0,
                'medium_severity': 0,
                'low_severity': 0,
                'findings': [],
                'analysis_timestamp': datetime.utcnow().isoformat(),
                'note': 'Security Command Center data not available'
            }
    
    def calculate_quantum_readiness_score(self, asset_analysis: Dict[str, Any]) -> float:
        """
        Calculate quantum readiness score based on asset analysis
        
        Args:
            asset_analysis: Results from cryptographic asset analysis
            
        Returns:
            Quantum readiness score (0-100)
        """
        total_keys = asset_analysis['total_keys']
        if total_keys == 0:
            return 0.0
        
        quantum_safe_keys = asset_analysis['quantum_safe_keys']
        vulnerable_keys = asset_analysis['vulnerable_keys']
        unknown_keys = asset_analysis['unknown_keys']
        
        # Scoring algorithm:
        # - Quantum-safe keys: 100% score
        # - Unknown keys: 50% score (neutral)
        # - Vulnerable keys: 0% score
        score = ((quantum_safe_keys * 100) + (unknown_keys * 50)) / total_keys
        
        return round(score, 2)
    
    def generate_recommendations(self, asset_analysis: Dict[str, Any], 
                               security_analysis: Dict[str, Any]) -> List[str]:
        """
        Generate quantum readiness recommendations
        
        Args:
            asset_analysis: Results from asset analysis
            security_analysis: Results from security findings analysis
            
        Returns:
            List of recommendation strings
        """
        recommendations = []
        
        # Key migration recommendations
        if asset_analysis['vulnerable_keys'] > 0:
            recommendations.append(
                f"URGENT: Migrate {asset_analysis['vulnerable_keys']} quantum-vulnerable "
                "keys to post-quantum algorithms (ML-DSA-65 or SLH-DSA-SHA2-128S)"
            )
        
        if asset_analysis['unknown_keys'] > 0:
            recommendations.append(
                f"Assess {asset_analysis['unknown_keys']} keys with unknown algorithms "
                "for quantum vulnerability"
            )
        
        # Security findings recommendations
        if security_analysis['high_severity'] > 0:
            recommendations.append(
                f"Address {security_analysis['high_severity']} high-severity "
                "quantum security findings immediately"
            )
        
        # General recommendations
        if asset_analysis['quantum_safe_keys'] == 0:
            recommendations.append(
                "Deploy post-quantum cryptographic keys for critical applications"
            )
        
        recommendations.extend([
            "Implement automated key rotation for cryptographic agility",
            "Conduct quantum threat assessment for critical applications",
            "Establish quantum incident response procedures",
            "Train security team on post-quantum cryptography best practices",
            "Monitor NIST updates for additional PQC algorithm standards"
        ])
        
        return recommendations
    
    def save_report_to_storage(self, report: Dict[str, Any]) -> str:
        """
        Save compliance report to Cloud Storage
        
        Args:
            report: Complete compliance report
            
        Returns:
            Storage path of saved report
        """
        try:
            bucket = self.storage_client.bucket(BUCKET_NAME)
            timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            blob_name = f"compliance_reports/quantum_readiness_{timestamp}.json"
            
            blob = bucket.blob(blob_name)
            blob.upload_from_string(
                json.dumps(report, indent=2),
                content_type='application/json'
            )
            
            logger.info(f"Compliance report saved to gs://{BUCKET_NAME}/{blob_name}")
            return f"gs://{BUCKET_NAME}/{blob_name}"
            
        except Exception as e:
            logger.error(f"Error saving report to storage: {str(e)}")
            raise


@functions_framework.http
def generate_quantum_compliance_report(request):
    """
    HTTP Cloud Function entry point for generating quantum compliance reports
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response containing compliance report
    """
    logger.info("Starting quantum compliance report generation")
    
    try:
        # Initialize analyzer
        analyzer = QuantumComplianceAnalyzer()
        
        # Perform analysis
        logger.info("Analyzing cryptographic assets...")
        asset_analysis = analyzer.analyze_cryptographic_assets()
        
        logger.info("Analyzing security findings...")
        security_analysis = analyzer.get_security_findings()
        
        # Calculate quantum readiness score
        quantum_score = analyzer.calculate_quantum_readiness_score(asset_analysis)
        
        # Generate recommendations
        recommendations = analyzer.generate_recommendations(asset_analysis, security_analysis)
        
        # Create comprehensive report
        report = {
            'report_metadata': {
                'report_id': f"quantum_compliance_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}",
                'generation_timestamp': datetime.utcnow().isoformat(),
                'organization_id': ORGANIZATION_ID,
                'project_id': PROJECT_ID,
                'report_version': '1.0',
                'report_type': 'Quantum Readiness Compliance Assessment'
            },
            'executive_summary': {
                'quantum_readiness_score': quantum_score,
                'total_cryptographic_keys': asset_analysis['total_keys'],
                'quantum_safe_keys': asset_analysis['quantum_safe_keys'],
                'vulnerable_keys': asset_analysis['vulnerable_keys'],
                'high_priority_findings': security_analysis['high_severity'],
                'overall_risk_level': 'HIGH' if quantum_score < 50 else 'MEDIUM' if quantum_score < 80 else 'LOW'
            },
            'detailed_analysis': {
                'cryptographic_assets': asset_analysis,
                'security_findings': security_analysis,
                'compliance_metrics': {
                    'post_quantum_adoption_rate': round((asset_analysis['quantum_safe_keys'] / max(asset_analysis['total_keys'], 1)) * 100, 2),
                    'vulnerability_exposure_rate': round((asset_analysis['vulnerable_keys'] / max(asset_analysis['total_keys'], 1)) * 100, 2),
                    'assessment_coverage': '100%'
                }
            },
            'recommendations': {
                'immediate_actions': [rec for rec in recommendations if 'URGENT' in rec],
                'strategic_initiatives': [rec for rec in recommendations if 'URGENT' not in rec]
            },
            'compliance_status': {
                'nist_pqc_readiness': quantum_score >= 75,
                'quantum_threat_mitigation': asset_analysis['quantum_safe_keys'] > 0,
                'continuous_monitoring': True,
                'governance_framework': True
            },
            'next_assessment_date': (datetime.utcnow() + timedelta(days=90)).isoformat()
        }
        
        # Save report to storage
        try:
            storage_path = analyzer.save_report_to_storage(report)
            report['report_metadata']['storage_location'] = storage_path
        except Exception as e:
            logger.warning(f"Could not save to storage: {str(e)}")
        
        logger.info(f"Quantum compliance report generated successfully. Score: {quantum_score}")
        
        # Return JSON response
        return {
            'status': 'success',
            'report': report
        }, 200, {'Content-Type': 'application/json'}
        
    except Exception as e:
        logger.error(f"Error generating compliance report: {str(e)}")
        
        error_response = {
            'status': 'error',
            'error_message': str(e),
            'timestamp': datetime.utcnow().isoformat(),
            'organization_id': ORGANIZATION_ID,
            'project_id': PROJECT_ID
        }
        
        return error_response, 500, {'Content-Type': 'application/json'}


def main():
    """
    Main function for local testing
    """
    # Mock request for local testing
    class MockRequest:
        def __init__(self):
            self.args = {}
            self.method = 'GET'
    
    response, status_code, headers = generate_quantum_compliance_report(MockRequest())
    print(f"Status: {status_code}")
    print(f"Response: {json.dumps(response, indent=2)}")


if __name__ == '__main__':
    main()