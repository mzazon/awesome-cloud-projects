"""
Cloud Function for Automated Database Governance Compliance Reporting
Generates compliance reports for database fleet governance using Cloud Asset Inventory data
"""

import json
import os
import datetime
from typing import Dict, Any, List, Optional
from google.cloud import asset_v1
from google.cloud import bigquery
from google.cloud import storage
import functions_framework


@functions_framework.http
def generate_compliance_report(request) -> Dict[str, Any]:
    """
    Generate compliance report for database governance.
    
    HTTP Cloud Function that analyzes database assets from Cloud Asset Inventory
    and generates comprehensive compliance reports for audit and governance purposes.
    
    Args:
        request: HTTP request object with optional query parameters:
            - project_id: Google Cloud Project ID (defaults to environment variable)
            - suffix: Random suffix for resource naming
            - report_type: Type of report to generate (compliance, security, etc.)
    
    Returns:
        JSON response with compliance report status and details
    """
    try:
        # Extract parameters from request
        project_id = request.args.get('project_id', os.environ.get('PROJECT_ID', '${project_id}'))
        suffix = request.args.get('suffix', os.environ.get('SUFFIX', '${suffix}'))
        report_type = request.args.get('report_type', 'compliance')
        
        if not project_id:
            return {
                'status': 'error',
                'message': 'PROJECT_ID is required either as query parameter or environment variable'
            }, 400
        
        # Initialize Google Cloud clients
        asset_client = asset_v1.AssetServiceClient()
        bq_client = bigquery.Client(project=project_id)
        storage_client = storage.Client(project=project_id)
        
        # Generate compliance report based on asset inventory data
        report = _generate_governance_report(
            bq_client=bq_client,
            project_id=project_id,
            suffix=suffix,
            report_type=report_type
        )
        
        # Upload report to Cloud Storage
        report_location = _upload_report_to_storage(
            storage_client=storage_client,
            report=report,
            suffix=suffix
        )
        
        # Log compliance metrics for monitoring
        _log_compliance_metrics(report)
        
        return {
            'status': 'success',
            'report_location': report_location,
            'compliance_percentage': report.get('compliance_percentage', 0),
            'total_databases': report.get('total_databases', 0),
            'compliant_databases': report.get('compliant_databases', 0),
            'violations_count': len(report.get('violations', [])),
            'timestamp': report.get('timestamp'),
            'project_id': project_id
        }
        
    except Exception as e:
        error_message = f"Error generating compliance report: {str(e)}"
        print(f"ERROR: {error_message}")
        return {
            'status': 'error',
            'message': error_message
        }, 500


def _generate_governance_report(
    bq_client: bigquery.Client,
    project_id: str,
    suffix: str,
    report_type: str
) -> Dict[str, Any]:
    """
    Generate governance report from BigQuery asset inventory data.
    
    Args:
        bq_client: BigQuery client instance
        project_id: Google Cloud Project ID
        suffix: Random suffix for resource naming
        report_type: Type of report to generate
    
    Returns:
        Dictionary containing comprehensive governance report
    """
    
    # Query database assets from BigQuery
    dataset_id = f"database_governance_{suffix}"
    query = f"""
    SELECT 
        asset_type,
        name,
        resource.data as config,
        ancestors
    FROM `{project_id}.{dataset_id}.asset_inventory`
    WHERE asset_type LIKE '%Instance'
        OR asset_type LIKE '%Database'
        OR asset_type LIKE '%Cluster'
    ORDER BY asset_type, name
    """
    
    try:
        query_job = bq_client.query(query)
        results = list(query_job.result())
    except Exception as e:
        print(f"Warning: Could not query BigQuery asset inventory: {e}")
        # Return empty report if BigQuery data is not available
        results = []
    
    # Initialize report structure
    report = {
        'timestamp': datetime.datetime.now().isoformat(),
        'project_id': project_id,
        'report_type': report_type,
        'total_databases': 0,
        'compliant_databases': 0,
        'violations': [],
        'security_findings': [],
        'recommendations': [],
        'asset_summary': {},
        'governance_score': 0.0
    }
    
    # Analyze each database asset for compliance
    for row in results:
        report['total_databases'] += 1
        asset_type = row.asset_type
        asset_name = row.name
        config = row.config if row.config else {}
        
        # Count asset types
        if asset_type not in report['asset_summary']:
            report['asset_summary'][asset_type] = 0
        report['asset_summary'][asset_type] += 1
        
        # Perform compliance checks based on asset type
        compliance_result = _check_asset_compliance(
            asset_type=asset_type,
            asset_name=asset_name,
            config=config
        )
        
        if compliance_result['compliant']:
            report['compliant_databases'] += 1
        else:
            report['violations'].extend(compliance_result['violations'])
        
        # Add security findings
        report['security_findings'].extend(compliance_result.get('security_findings', []))
        
        # Add recommendations
        report['recommendations'].extend(compliance_result.get('recommendations', []))
    
    # Calculate compliance percentage
    if report['total_databases'] > 0:
        report['compliance_percentage'] = (
            report['compliant_databases'] / report['total_databases']
        ) * 100
        report['governance_score'] = report['compliance_percentage'] / 100
    else:
        report['compliance_percentage'] = 100
        report['governance_score'] = 1.0
    
    # Add summary statistics
    report['summary'] = {
        'governance_level': _determine_governance_level(report['governance_score']),
        'critical_violations': len([v for v in report['violations'] if v.get('severity') == 'critical']),
        'high_violations': len([v for v in report['violations'] if v.get('severity') == 'high']),
        'medium_violations': len([v for v in report['violations'] if v.get('severity') == 'medium']),
        'low_violations': len([v for v in report['violations'] if v.get('severity') == 'low'])
    }
    
    return report


def _check_asset_compliance(
    asset_type: str,
    asset_name: str,
    config: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Check compliance for a specific database asset.
    
    Args:
        asset_type: Type of the asset (e.g., sqladmin.googleapis.com/Instance)
        asset_name: Full name of the asset
        config: Asset configuration data
    
    Returns:
        Dictionary with compliance status, violations, and recommendations
    """
    
    result = {
        'compliant': True,
        'violations': [],
        'security_findings': [],
        'recommendations': []
    }
    
    # Cloud SQL compliance checks
    if asset_type == 'sqladmin.googleapis.com/Instance':
        result.update(_check_cloudsql_compliance(asset_name, config))
    
    # Spanner compliance checks
    elif asset_type == 'spanner.googleapis.com/Instance':
        result.update(_check_spanner_compliance(asset_name, config))
    
    # Bigtable compliance checks
    elif asset_type == 'bigtableadmin.googleapis.com/Instance':
        result.update(_check_bigtable_compliance(asset_name, config))
    
    return result


def _check_cloudsql_compliance(asset_name: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """Check Cloud SQL instance compliance."""
    result = {
        'compliant': True,
        'violations': [],
        'security_findings': [],
        'recommendations': []
    }
    
    settings = config.get('settings', {})
    
    # Check backup configuration
    backup_config = settings.get('backupConfiguration', {})
    if not backup_config.get('enabled', False):
        result['compliant'] = False
        result['violations'].append({
            'resource': asset_name,
            'type': 'sqladmin.googleapis.com/Instance',
            'issue': 'Automated backups not enabled',
            'severity': 'high',
            'recommendation': 'Enable automated backups with appropriate retention period'
        })
    
    # Check SSL enforcement
    ip_config = settings.get('ipConfiguration', {})
    if not ip_config.get('requireSsl', False):
        result['security_findings'].append({
            'resource': asset_name,
            'finding': 'SSL/TLS not required for connections',
            'severity': 'medium',
            'recommendation': 'Enable SSL/TLS requirement for secure connections'
        })
    
    # Check public IP configuration
    if ip_config.get('ipv4Enabled', True):
        result['security_findings'].append({
            'resource': asset_name,
            'finding': 'Public IP enabled',
            'severity': 'medium',
            'recommendation': 'Consider using private IP for enhanced security'
        })
    
    # Check deletion protection
    if not config.get('settings', {}).get('deletionProtectionEnabled', False):
        result['recommendations'].append({
            'resource': asset_name,
            'recommendation': 'Enable deletion protection for production instances',
            'priority': 'medium'
        })
    
    return result


def _check_spanner_compliance(asset_name: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """Check Spanner instance compliance."""
    result = {
        'compliant': True,
        'violations': [],
        'security_findings': [],
        'recommendations': []
    }
    
    # Check encryption configuration
    encryption_config = config.get('encryptionConfig')
    if not encryption_config:
        result['security_findings'].append({
            'resource': asset_name,
            'finding': 'Custom encryption key not configured',
            'severity': 'low',
            'recommendation': 'Consider using customer-managed encryption keys (CMEK) for enhanced security'
        })
    
    # Check node count for production readiness
    node_count = config.get('nodeCount', 0)
    if node_count < 3:
        result['recommendations'].append({
            'resource': asset_name,
            'recommendation': 'Consider increasing node count to 3+ for production high availability',
            'priority': 'medium'
        })
    
    return result


def _check_bigtable_compliance(asset_name: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """Check Bigtable instance compliance."""
    result = {
        'compliant': True,
        'violations': [],
        'security_findings': [],
        'recommendations': []
    }
    
    # Check instance type
    instance_type = config.get('type', '')
    if instance_type == 'DEVELOPMENT':
        result['recommendations'].append({
            'resource': asset_name,
            'recommendation': 'Development instances should not be used for production workloads',
            'priority': 'high'
        })
    
    # Check cluster configuration
    clusters = config.get('clusters', [])
    for cluster in clusters:
        if cluster.get('serveNodes', 0) < 3:
            result['recommendations'].append({
                'resource': asset_name,
                'recommendation': f'Cluster {cluster.get("name", "unknown")} has fewer than 3 nodes, consider scaling for production',
                'priority': 'medium'
            })
    
    return result


def _determine_governance_level(score: float) -> str:
    """Determine governance level based on compliance score."""
    if score >= 0.95:
        return 'excellent'
    elif score >= 0.85:
        return 'good'
    elif score >= 0.70:
        return 'fair'
    else:
        return 'needs_improvement'


def _upload_report_to_storage(
    storage_client: storage.Client,
    report: Dict[str, Any],
    suffix: str
) -> str:
    """
    Upload compliance report to Cloud Storage.
    
    Args:
        storage_client: Cloud Storage client instance
        report: Compliance report data
        suffix: Random suffix for bucket naming
    
    Returns:
        Cloud Storage URI of uploaded report
    """
    bucket_name = f"db-governance-assets-{suffix}"
    report_date = datetime.date.today().strftime('%Y-%m-%d')
    timestamp = datetime.datetime.now().strftime('%H%M%S')
    blob_name = f"compliance-reports/{report_date}/{timestamp}-governance-report.json"
    
    try:
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        
        # Upload report as JSON
        blob.upload_from_string(
            json.dumps(report, indent=2, default=str),
            content_type='application/json'
        )
        
        return f"gs://{bucket_name}/{blob_name}"
        
    except Exception as e:
        print(f"Warning: Could not upload report to storage: {e}")
        return f"gs://{bucket_name}/{blob_name} (upload failed)"


def _log_compliance_metrics(report: Dict[str, Any]) -> None:
    """
    Log compliance metrics for Cloud Monitoring.
    
    Args:
        report: Compliance report containing metrics to log
    """
    
    # Log structured compliance data for monitoring
    compliance_data = {
        'compliance_percentage': report.get('compliance_percentage', 0),
        'total_databases': report.get('total_databases', 0),
        'compliant_databases': report.get('compliant_databases', 0),
        'violations_count': len(report.get('violations', [])),
        'governance_score': report.get('governance_score', 0),
        'project_id': report.get('project_id', ''),
        'timestamp': report.get('timestamp', ''),
        'governance_level': report.get('summary', {}).get('governance_level', 'unknown')
    }
    
    # Print structured log entry for Cloud Logging
    print(json.dumps({
        'message': 'Database governance compliance report generated',
        'severity': 'INFO',
        'component': 'compliance-reporter',
        'compliance': compliance_data
    }))
    
    # Log any critical violations
    for violation in report.get('violations', []):
        if violation.get('severity') == 'critical':
            print(json.dumps({
                'message': f"Critical compliance violation detected: {violation.get('issue', 'unknown')}",
                'severity': 'ERROR', 
                'component': 'compliance-reporter',
                'violation': violation
            }))


if __name__ == '__main__':
    # For local testing
    import flask
    
    app = flask.Flask(__name__)
    
    @app.route('/', methods=['GET'])
    def test_function():
        request = flask.request
        return generate_compliance_report(request)
    
    app.run(debug=True, host='0.0.0.0', port=8080)