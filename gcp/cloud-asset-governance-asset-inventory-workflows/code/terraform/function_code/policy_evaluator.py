# Cloud Asset Governance Policy Evaluator Function
# This function evaluates Google Cloud assets against governance policies
# and records violations in BigQuery for compliance monitoring and remediation.

import json
import logging
import hashlib
import os
from datetime import datetime
from typing import Dict, List, Any, Optional
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import monitoring_v3
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
GOVERNANCE_SUFFIX = os.environ.get('GOVERNANCE_SUFFIX', '${governance_suffix}')
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
DATASET_ID = os.environ.get('DATASET_ID', '${dataset_id}')
REGION = os.environ.get('REGION', 'us-central1')

# Initialize clients
bq_client = bigquery.Client(project=PROJECT_ID)
storage_client = storage.Client(project=PROJECT_ID)
monitoring_client = monitoring_v3.MetricServiceClient()

class GovernancePolicyEvaluator:
    """
    Evaluates Google Cloud assets against governance policies.
    
    This class implements various governance policies including:
    - Encryption requirements
    - Security configurations
    - Network access controls
    - Resource tagging compliance
    - Cost optimization policies
    """
    
    def __init__(self):
        self.violations = []
        self.metrics_data = []
    
    def evaluate_storage_bucket_policies(self, asset: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Evaluate Cloud Storage bucket against governance policies."""
        violations = []
        resource_data = asset.get('resource', {}).get('data', {})
        bucket_name = resource_data.get('name', '')
        
        # Policy 1: Encryption at rest requirement
        encryption = resource_data.get('encryption', {})
        default_kms_key = encryption.get('defaultKmsKeyName', '')
        
        if not default_kms_key:
            violations.append({
                'policy': 'storage_encryption_required',
                'severity': 'HIGH',
                'description': 'Storage bucket lacks customer-managed encryption (CMEK)',
                'recommendation': 'Configure bucket with customer-managed encryption key',
                'remediation_actions': ['enable_cmek_encryption']
            })
        
        # Policy 2: Public access prevention
        iam_config = resource_data.get('iamConfiguration', {})
        uniform_bucket_access = iam_config.get('uniformBucketLevelAccess', {}).get('enabled', False)
        public_access_prevention = iam_config.get('publicAccessPrevention', '')
        
        if not uniform_bucket_access:
            violations.append({
                'policy': 'uniform_bucket_access_required',
                'severity': 'MEDIUM',
                'description': 'Bucket lacks uniform bucket-level access controls',
                'recommendation': 'Enable uniform bucket-level access for consistent security',
                'remediation_actions': ['enable_uniform_bucket_access']
            })
        
        if public_access_prevention != 'enforced':
            violations.append({
                'policy': 'public_access_prevention_required',
                'severity': 'HIGH',
                'description': 'Bucket allows potential public access',
                'recommendation': 'Enforce public access prevention',
                'remediation_actions': ['enforce_public_access_prevention']
            })
        
        # Policy 3: Lifecycle management requirement
        lifecycle_rules = resource_data.get('lifecycle', {}).get('rule', [])
        if not lifecycle_rules:
            violations.append({
                'policy': 'lifecycle_management_required',
                'severity': 'LOW',
                'description': 'Bucket lacks lifecycle management for cost optimization',
                'recommendation': 'Configure lifecycle rules for automated cost management',
                'remediation_actions': ['configure_lifecycle_rules']
            })
        
        # Policy 4: Versioning configuration
        versioning = resource_data.get('versioning', {}).get('enabled', False)
        if not versioning:
            violations.append({
                'policy': 'versioning_recommended',
                'severity': 'LOW',
                'description': 'Bucket versioning not enabled for data protection',
                'recommendation': 'Enable versioning for data recovery capabilities',
                'remediation_actions': ['enable_versioning']
            })
        
        # Policy 5: Required labels compliance
        labels = resource_data.get('labels', {})
        required_labels = ['environment', 'owner', 'purpose']
        missing_labels = [label for label in required_labels if label not in labels]
        
        if missing_labels:
            violations.append({
                'policy': 'required_labels_missing',
                'severity': 'MEDIUM',
                'description': f'Bucket missing required labels: {", ".join(missing_labels)}',
                'recommendation': 'Add all required labels for governance and billing',
                'remediation_actions': ['add_required_labels']
            })
        
        return violations
    
    def evaluate_compute_instance_policies(self, asset: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Evaluate Compute Engine instance against governance policies."""
        violations = []
        resource_data = asset.get('resource', {}).get('data', {})
        
        # Policy 1: Secure boot requirement
        shielded_config = resource_data.get('shieldedInstanceConfig', {})
        secure_boot = shielded_config.get('enableSecureBoot', False)
        vtpm = shielded_config.get('enableVtpm', False)
        integrity_monitoring = shielded_config.get('enableIntegrityMonitoring', False)
        
        if not secure_boot:
            violations.append({
                'policy': 'secure_boot_required',
                'severity': 'HIGH',
                'description': 'Compute instance lacks secure boot configuration',
                'recommendation': 'Enable secure boot for enhanced security',
                'remediation_actions': ['enable_secure_boot']
            })
        
        if not vtpm:
            violations.append({
                'policy': 'vtpm_required',
                'severity': 'MEDIUM',
                'description': 'Compute instance lacks virtual TPM',
                'recommendation': 'Enable vTPM for hardware-based security',
                'remediation_actions': ['enable_vtpm']
            })
        
        # Policy 2: Public IP restriction
        network_interfaces = resource_data.get('networkInterfaces', [])
        has_public_ip = False
        
        for interface in network_interfaces:
            access_configs = interface.get('accessConfigs', [])
            if access_configs:
                has_public_ip = True
                break
        
        if has_public_ip:
            violations.append({
                'policy': 'no_public_ip_required',
                'severity': 'HIGH',
                'description': 'Compute instance has public IP assignment',
                'recommendation': 'Remove public IP and use Cloud NAT or IAP for access',
                'remediation_actions': ['remove_public_ip', 'configure_private_access']
            })
        
        # Policy 3: OS patch management
        metadata = resource_data.get('metadata', {})
        os_login_enabled = False
        
        for item in metadata.get('items', []):
            if item.get('key') == 'enable-oslogin' and item.get('value') == 'TRUE':
                os_login_enabled = True
                break
        
        if not os_login_enabled:
            violations.append({
                'policy': 'os_login_required',
                'severity': 'MEDIUM',
                'description': 'Compute instance lacks OS Login configuration',
                'recommendation': 'Enable OS Login for centralized access management',
                'remediation_actions': ['enable_os_login']
            })
        
        # Policy 4: Disk encryption
        disks = resource_data.get('disks', [])
        for disk in disks:
            disk_encryption = disk.get('diskEncryptionKey', {})
            if not disk_encryption.get('kmsKeyName'):
                violations.append({
                    'policy': 'disk_encryption_required',
                    'severity': 'HIGH',
                    'description': 'Compute instance disk lacks customer-managed encryption',
                    'recommendation': 'Configure CMEK encryption for all attached disks',
                    'remediation_actions': ['enable_disk_cmek']
                })
                break
        
        # Policy 5: Machine type cost optimization
        machine_type = resource_data.get('machineType', '')
        if 'n1-' in machine_type:
            violations.append({
                'policy': 'machine_type_optimization',
                'severity': 'LOW',
                'description': 'Instance uses legacy N1 machine type',
                'recommendation': 'Consider upgrading to E2 or N2 for better price-performance',
                'remediation_actions': ['upgrade_machine_type']
            })
        
        return violations
    
    def evaluate_bigquery_dataset_policies(self, asset: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Evaluate BigQuery dataset against governance policies."""
        violations = []
        resource_data = asset.get('resource', {}).get('data', {})
        
        # Policy 1: Encryption at rest
        default_encryption = resource_data.get('defaultEncryptionConfiguration', {})
        kms_key_name = default_encryption.get('kmsKeyName', '')
        
        if not kms_key_name:
            violations.append({
                'policy': 'bigquery_encryption_required',
                'severity': 'HIGH',
                'description': 'BigQuery dataset lacks customer-managed encryption',
                'recommendation': 'Configure dataset with CMEK encryption',
                'remediation_actions': ['enable_dataset_cmek']
            })
        
        # Policy 2: Access controls
        access_entries = resource_data.get('access', [])
        has_public_access = False
        
        for entry in access_entries:
            if entry.get('specialGroup') == 'allAuthenticatedUsers' or entry.get('domain'):
                has_public_access = True
                break
        
        if has_public_access:
            violations.append({
                'policy': 'bigquery_no_public_access',
                'severity': 'HIGH',
                'description': 'BigQuery dataset has overly broad access permissions',
                'recommendation': 'Restrict access to specific users and service accounts',
                'remediation_actions': ['restrict_dataset_access']
            })
        
        # Policy 3: Table expiration
        default_table_expiration = resource_data.get('defaultTableExpirationMs')
        if not default_table_expiration:
            violations.append({
                'policy': 'table_expiration_required',
                'severity': 'MEDIUM',
                'description': 'BigQuery dataset lacks default table expiration',
                'recommendation': 'Set default table expiration for cost management',
                'remediation_actions': ['set_table_expiration']
            })
        
        return violations
    
    def evaluate_iam_service_account_policies(self, asset: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Evaluate IAM service account against governance policies."""
        violations = []
        resource_data = asset.get('resource', {}).get('data', {})
        
        # Policy 1: Key rotation
        # Note: This would require additional API calls to check key age
        display_name = resource_data.get('displayName', '')
        if not display_name:
            violations.append({
                'policy': 'service_account_description_required',
                'severity': 'LOW',
                'description': 'Service account lacks descriptive display name',
                'recommendation': 'Add meaningful display name for identification',
                'remediation_actions': ['add_display_name']
            })
        
        # Policy 2: Email pattern compliance
        email = resource_data.get('email', '')
        if 'compute@developer.gserviceaccount.com' in email:
            violations.append({
                'policy': 'default_service_account_usage',
                'severity': 'MEDIUM',
                'description': 'Using default Compute Engine service account',
                'recommendation': 'Create dedicated service accounts with minimal permissions',
                'remediation_actions': ['create_dedicated_service_account']
            })
        
        return violations
    
    def evaluate_asset(self, asset: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Main method to evaluate an asset against all applicable policies."""
        asset_type = asset.get('assetType', '')
        
        # Route to appropriate policy evaluator based on asset type
        if asset_type == 'storage.googleapis.com/Bucket':
            return self.evaluate_storage_bucket_policies(asset)
        elif asset_type == 'compute.googleapis.com/Instance':
            return self.evaluate_compute_instance_policies(asset)
        elif asset_type == 'bigquery.googleapis.com/Dataset':
            return self.evaluate_bigquery_dataset_policies(asset)
        elif asset_type == 'iam.googleapis.com/ServiceAccount':
            return self.evaluate_iam_service_account_policies(asset)
        else:
            # Log unsupported asset type for future policy development
            logger.info(f"Asset type not covered by governance policies: {asset_type}")
            return []
    
    def record_violations_in_bigquery(self, violations: List[Dict[str, Any]], 
                                    asset: Dict[str, Any]) -> None:
        """Record policy violations in BigQuery for analytics and reporting."""
        if not violations:
            return
        
        table_id = f"{PROJECT_ID}.{DATASET_ID}.asset_violations"
        resource_name = asset.get('name', '')
        asset_type = asset.get('assetType', '')
        ancestors = asset.get('ancestors', [])
        project_id = ancestors[-1].replace('projects/', '') if ancestors else 'unknown'
        
        rows_to_insert = []
        
        for violation in violations:
            violation_id = hashlib.md5(
                f"{resource_name}-{violation['policy']}-{datetime.now().isoformat()}".encode()
            ).hexdigest()
            
            row = {
                'violation_id': violation_id,
                'resource_name': resource_name,
                'policy_name': violation['policy'],
                'violation_type': violation['description'],
                'severity': violation['severity'],
                'timestamp': datetime.now().isoformat(),
                'project_id': project_id,
                'remediation_status': 'DETECTED',
                'asset_type': asset_type,
                'remediation_actions': violation.get('remediation_actions', [])
            }
            
            rows_to_insert.append(row)
        
        # Insert violations into BigQuery
        try:
            table = bq_client.get_table(table_id)
            errors = bq_client.insert_rows_json(table, rows_to_insert)
            
            if errors:
                logger.error(f"BigQuery insert errors: {errors}")
            else:
                logger.info(f"Successfully recorded {len(violations)} violations for {resource_name}")
                
        except Exception as e:
            logger.error(f"Failed to record violations in BigQuery: {str(e)}")
    
    def send_custom_metrics(self, violations: List[Dict[str, Any]], 
                          asset: Dict[str, Any]) -> None:
        """Send custom metrics to Cloud Monitoring for alerting."""
        try:
            project_name = f"projects/{PROJECT_ID}"
            
            # Create time series for violation counts by severity
            severity_counts = {'HIGH': 0, 'MEDIUM': 0, 'LOW': 0}
            for violation in violations:
                severity = violation.get('severity', 'LOW')
                severity_counts[severity] += 1
            
            # Send metrics for each severity level
            for severity, count in severity_counts.items():
                if count > 0:
                    series = monitoring_v3.TimeSeries()
                    series.metric.type = "custom.googleapis.com/governance/violations"
                    series.metric.labels["severity"] = severity
                    series.metric.labels["policy_type"] = "governance"
                    
                    series.resource.type = "global"
                    series.resource.labels["project_id"] = PROJECT_ID
                    
                    now = datetime.now()
                    seconds = int(now.timestamp())
                    nanos = int((now.timestamp() - seconds) * 10**9)
                    
                    interval = monitoring_v3.TimeInterval()
                    interval.end_time.seconds = seconds
                    interval.end_time.nanos = nanos
                    
                    point = monitoring_v3.Point()
                    point.value.int64_value = count
                    point.interval = interval
                    
                    series.points = [point]
                    
                    monitoring_client.create_time_series(
                        name=project_name, 
                        time_series=[series]
                    )
                    
        except Exception as e:
            logger.error(f"Failed to send custom metrics: {str(e)}")

@functions_framework.http
def evaluate_governance_policy(request):
    """
    Cloud Function entry point for evaluating governance policies.
    
    This function receives asset change events and evaluates them against
    governance policies, recording violations for compliance monitoring.
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        
        if not request_json or 'asset' not in request_json:
            logger.warning("No asset data found in request")
            return {'status': 'no_asset_data', 'message': 'No asset data provided'}, 400
        
        asset = request_json['asset']
        change_type = request_json.get('changeType', 'UNKNOWN')
        
        # Log asset processing
        resource_name = asset.get('name', 'unknown')
        asset_type = asset.get('assetType', 'unknown')
        logger.info(f"Processing asset: {resource_name} (type: {asset_type}, change: {change_type})")
        
        # Initialize policy evaluator
        evaluator = GovernancePolicyEvaluator()
        
        # Evaluate asset against policies
        violations = evaluator.evaluate_asset(asset)
        
        # Record violations if found
        if violations:
            evaluator.record_violations_in_bigquery(violations, asset)
            evaluator.send_custom_metrics(violations, asset)
            
            logger.warning(f"Found {len(violations)} violations for {resource_name}")
            
            # Log violation details
            for violation in violations:
                logger.warning(f"Violation: {violation['policy']} - {violation['description']} (Severity: {violation['severity']})")
        else:
            logger.info(f"No violations found for {resource_name}")
        
        # Return evaluation results
        return {
            'status': 'completed',
            'violations_found': len(violations),
            'resource_name': resource_name,
            'asset_type': asset_type,
            'change_type': change_type,
            'violations': [
                {
                    'policy': v['policy'],
                    'severity': v['severity'],
                    'description': v['description']
                } for v in violations
            ]
        }, 200
        
    except Exception as e:
        logger.error(f"Error processing governance evaluation: {str(e)}")
        return {
            'status': 'error',
            'message': str(e)
        }, 500