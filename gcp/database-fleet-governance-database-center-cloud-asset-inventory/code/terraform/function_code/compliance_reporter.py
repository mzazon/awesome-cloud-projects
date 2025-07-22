# compliance_reporter.py - Cloud Function for Database Governance Compliance Reporting
"""
Database Governance Compliance Reporter

This Cloud Function generates comprehensive compliance reports for database fleet governance
by analyzing asset inventory data, evaluating security configurations, and producing
actionable insights for governance teams.
"""

import json
import os
import datetime
import logging
from typing import Dict, List, Any, Optional
from google.cloud import asset_v1
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import monitoring_v3
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = "${project_id}"
DATASET_ID = "${dataset_id}"
BUCKET_NAME = "${bucket_name}"

class DatabaseGovernanceReporter:
    """Main class for database governance compliance reporting."""
    
    def __init__(self):
        """Initialize the reporter with GCP clients."""
        self.project_id = PROJECT_ID
        self.dataset_id = DATASET_ID
        self.bucket_name = BUCKET_NAME
        
        # Initialize GCP clients
        self.asset_client = asset_v1.AssetServiceClient()
        self.bq_client = bigquery.Client()
        self.storage_client = storage.Client()
        self.monitoring_client = monitoring_v3.MetricServiceClient()
        
        # Compliance rules and weights
        self.compliance_rules = {
            "backup_enabled": {"weight": 0.25, "description": "Backup configuration enabled"},
            "ssl_required": {"weight": 0.20, "description": "SSL/TLS encryption required"},
            "private_ip_only": {"weight": 0.20, "description": "Private IP access only"},
            "audit_logs_enabled": {"weight": 0.15, "description": "Audit logging enabled"},
            "deletion_protection": {"weight": 0.10, "description": "Deletion protection enabled"},
            "maintenance_window": {"weight": 0.10, "description": "Maintenance window configured"}
        }
    
    def analyze_cloud_sql_compliance(self, instance_data: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze Cloud SQL instance compliance against governance policies."""
        compliance_results = {}
        settings = instance_data.get("settings", {})
        
        # Check backup configuration
        backup_config = settings.get("backupConfiguration", {})
        compliance_results["backup_enabled"] = backup_config.get("enabled", False)
        
        # Check SSL requirement
        ip_config = settings.get("ipConfiguration", {})
        compliance_results["ssl_required"] = ip_config.get("requireSsl", False)
        
        # Check private IP configuration
        compliance_results["private_ip_only"] = not ip_config.get("ipv4Enabled", True)
        
        # Check deletion protection
        compliance_results["deletion_protection"] = instance_data.get("deletionProtection", False)
        
        # Check maintenance window
        maintenance_window = settings.get("maintenanceWindow", {})
        compliance_results["maintenance_window"] = bool(maintenance_window.get("day"))
        
        # Audit logs (check database flags)
        database_flags = settings.get("databaseFlags", [])
        log_statement_flag = any(
            flag.get("name") == "log_statement" and flag.get("value") in ["all", "ddl", "mod"]
            for flag in database_flags
        )
        compliance_results["audit_logs_enabled"] = log_statement_flag
        
        return compliance_results
    
    def analyze_spanner_compliance(self, instance_data: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze Spanner instance compliance against governance policies."""
        compliance_results = {}
        
        # Spanner has built-in backup and encryption
        compliance_results["backup_enabled"] = True  # Automatic backups
        compliance_results["ssl_required"] = True   # Always encrypted in transit
        compliance_results["private_ip_only"] = True  # Private by default
        compliance_results["audit_logs_enabled"] = True  # Cloud Audit Logs
        
        # Check encryption configuration
        encryption_config = instance_data.get("encryptionConfig", {})
        compliance_results["encryption_at_rest"] = bool(encryption_config)
        
        # Deletion protection (not directly available, assume false)
        compliance_results["deletion_protection"] = False
        compliance_results["maintenance_window"] = True  # Managed by Google
        
        return compliance_results
    
    def analyze_bigtable_compliance(self, instance_data: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze Bigtable instance compliance against governance policies."""
        compliance_results = {}
        
        # Bigtable compliance characteristics
        compliance_results["backup_enabled"] = False  # Manual backup setup required
        compliance_results["ssl_required"] = True     # Always encrypted in transit
        compliance_results["private_ip_only"] = True  # Private by default
        compliance_results["audit_logs_enabled"] = True  # Cloud Audit Logs
        compliance_results["deletion_protection"] = False  # Check instance labels
        compliance_results["maintenance_window"] = True   # Managed by Google
        
        return compliance_results
    
    def calculate_compliance_score(self, compliance_results: Dict[str, bool]) -> float:
        """Calculate overall compliance score based on weighted rules."""
        total_weight = 0
        achieved_weight = 0
        
        for rule, config in self.compliance_rules.items():
            if rule in compliance_results:
                total_weight += config["weight"]
                if compliance_results[rule]:
                    achieved_weight += config["weight"]
        
        return achieved_weight / total_weight if total_weight > 0 else 0.0
    
    def get_database_assets(self) -> List[Dict[str, Any]]:
        """Retrieve database assets from Cloud Asset Inventory."""
        try:
            # Query BigQuery for latest asset inventory data
            query = f"""
            SELECT 
                asset_type,
                name,
                resource.data as config,
                ancestors
            FROM `{self.project_id}.{self.dataset_id}.asset_inventory`
            WHERE asset_type IN (
                'sqladmin.googleapis.com/Instance',
                'spanner.googleapis.com/Instance',
                'bigtableadmin.googleapis.com/Instance'
            )
            AND resource.data IS NOT NULL
            ORDER BY name
            """
            
            query_job = self.bq_client.query(query)
            results = query_job.result()
            
            assets = []
            for row in results:
                assets.append({
                    "asset_type": row.asset_type,
                    "name": row.name,
                    "config": json.loads(row.config) if isinstance(row.config, str) else row.config,
                    "ancestors": row.ancestors
                })
            
            return assets
            
        except Exception as e:
            logger.warning(f"Failed to query BigQuery, falling back to direct API: {e}")
            # Fallback to direct Asset API call
            return self._get_assets_from_api()
    
    def _get_assets_from_api(self) -> List[Dict[str, Any]]:
        """Fallback method to get assets directly from Asset API."""
        try:
            parent = f"projects/{self.project_id}"
            asset_types = [
                "sqladmin.googleapis.com/Instance",
                "spanner.googleapis.com/Instance", 
                "bigtableadmin.googleapis.com/Instance"
            ]
            
            assets = []
            for asset_type in asset_types:
                request = asset_v1.SearchAllResourcesRequest(
                    scope=parent,
                    asset_types=[asset_type]
                )
                
                page_result = self.asset_client.search_all_resources(request=request)
                for resource in page_result:
                    assets.append({
                        "asset_type": asset_type,
                        "name": resource.name,
                        "config": json.loads(resource.additional_attributes.get("data", "{}")),
                        "ancestors": [parent]
                    })
            
            return assets
            
        except Exception as e:
            logger.error(f"Failed to retrieve assets from API: {e}")
            return []
    
    def generate_compliance_report(self) -> Dict[str, Any]:
        """Generate comprehensive compliance report for all database assets."""
        try:
            timestamp = datetime.datetime.now().isoformat()
            assets = self.get_database_assets()
            
            report = {
                "timestamp": timestamp,
                "project_id": self.project_id,
                "total_databases": len(assets),
                "compliant_databases": 0,
                "compliance_details": [],
                "violations": [],
                "summary": {},
                "recommendations": []
            }
            
            total_compliance_score = 0.0
            
            for asset in assets:
                asset_type = asset["asset_type"]
                asset_name = asset["name"]
                config = asset["config"]
                
                # Analyze compliance based on asset type
                if "sqladmin" in asset_type:
                    compliance_results = self.analyze_cloud_sql_compliance(config)
                    service_type = "Cloud SQL"
                elif "spanner" in asset_type:
                    compliance_results = self.analyze_spanner_compliance(config)
                    service_type = "Spanner"
                elif "bigtable" in asset_type:
                    compliance_results = self.analyze_bigtable_compliance(config)
                    service_type = "Bigtable"
                else:
                    continue
                
                # Calculate compliance score for this asset
                asset_compliance_score = self.calculate_compliance_score(compliance_results)
                total_compliance_score += asset_compliance_score
                
                # Determine if asset is compliant (threshold: 0.8)
                is_compliant = asset_compliance_score >= 0.8
                if is_compliant:
                    report["compliant_databases"] += 1
                
                # Add to compliance details
                report["compliance_details"].append({
                    "name": asset_name,
                    "type": service_type,
                    "compliance_score": asset_compliance_score,
                    "is_compliant": is_compliant,
                    "rules": compliance_results
                })
                
                # Track violations
                for rule, passed in compliance_results.items():
                    if not passed and rule in self.compliance_rules:
                        report["violations"].append({
                            "resource": asset_name,
                            "type": service_type,
                            "rule": rule,
                            "description": self.compliance_rules[rule]["description"],
                            "severity": "high" if self.compliance_rules[rule]["weight"] >= 0.2 else "medium"
                        })
            
            # Calculate overall compliance percentage
            if report["total_databases"] > 0:
                report["overall_compliance_score"] = total_compliance_score / report["total_databases"]
                report["compliance_percentage"] = (report["compliant_databases"] / report["total_databases"]) * 100
            else:
                report["overall_compliance_score"] = 1.0
                report["compliance_percentage"] = 100.0
            
            # Generate summary
            report["summary"] = {
                "total_databases": report["total_databases"],
                "compliant_databases": report["compliant_databases"],
                "non_compliant_databases": report["total_databases"] - report["compliant_databases"],
                "overall_score": report["overall_compliance_score"],
                "compliance_percentage": report["compliance_percentage"],
                "total_violations": len(report["violations"])
            }
            
            # Generate recommendations
            report["recommendations"] = self._generate_recommendations(report["violations"])
            
            return report
            
        except Exception as e:
            logger.error(f"Error generating compliance report: {e}")
            return {
                "status": "error",
                "message": str(e),
                "timestamp": datetime.datetime.now().isoformat()
            }
    
    def _generate_recommendations(self, violations: List[Dict[str, Any]]) -> List[str]:
        """Generate actionable recommendations based on compliance violations."""
        recommendations = []
        
        # Group violations by rule type
        violation_counts = {}
        for violation in violations:
            rule = violation["rule"]
            violation_counts[rule] = violation_counts.get(rule, 0) + 1
        
        # Generate recommendations based on most common violations
        for rule, count in sorted(violation_counts.items(), key=lambda x: x[1], reverse=True):
            if rule == "backup_enabled":
                recommendations.append(f"Enable automated backups for {count} database instance(s) to ensure data protection and disaster recovery capability.")
            elif rule == "ssl_required":
                recommendations.append(f"Configure SSL/TLS encryption for {count} database instance(s) to protect data in transit.")
            elif rule == "private_ip_only":
                recommendations.append(f"Configure private IP access for {count} database instance(s) to improve network security.")
            elif rule == "audit_logs_enabled":
                recommendations.append(f"Enable audit logging for {count} database instance(s) to maintain security compliance and monitoring.")
            elif rule == "deletion_protection":
                recommendations.append(f"Enable deletion protection for {count} critical database instance(s) to prevent accidental data loss.")
            elif rule == "maintenance_window":
                recommendations.append(f"Configure maintenance windows for {count} database instance(s) to minimize disruption during updates.")
        
        return recommendations[:5]  # Return top 5 recommendations
    
    def save_report_to_storage(self, report: Dict[str, Any]) -> str:
        """Save compliance report to Cloud Storage."""
        try:
            bucket = self.storage_client.bucket(self.bucket_name)
            
            # Generate file path with timestamp
            date_str = datetime.date.today().strftime("%Y-%m-%d")
            timestamp_str = datetime.datetime.now().strftime("%H-%M-%S")
            blob_name = f"compliance-reports/{date_str}/governance-report-{timestamp_str}.json"
            
            blob = bucket.blob(blob_name)
            blob.upload_from_string(
                json.dumps(report, indent=2),
                content_type="application/json"
            )
            
            return f"gs://{self.bucket_name}/{blob_name}"
            
        except Exception as e:
            logger.error(f"Failed to save report to storage: {e}")
            return ""
    
    def send_compliance_metric(self, compliance_score: float) -> None:
        """Send compliance score to Cloud Monitoring."""
        try:
            project_name = f"projects/{self.project_id}"
            
            # Create time series data
            series = monitoring_v3.TimeSeries()
            series.metric.type = "custom.googleapis.com/database/governance_score"
            series.resource.type = "global"
            series.resource.labels["project_id"] = self.project_id
            
            # Create data point
            now = datetime.datetime.now()
            seconds = int(now.timestamp())
            nanos = int((now.timestamp() - seconds) * 10**9)
            interval = monitoring_v3.TimeInterval(
                end_time={"seconds": seconds, "nanos": nanos}
            )
            point = monitoring_v3.Point(
                interval=interval,
                value=monitoring_v3.TypedValue(double_value=compliance_score)
            )
            series.points = [point]
            
            # Send to monitoring
            self.monitoring_client.create_time_series(
                name=project_name,
                time_series=[series]
            )
            
            logger.info(f"Sent compliance score {compliance_score} to Cloud Monitoring")
            
        except Exception as e:
            logger.warning(f"Failed to send metric to Cloud Monitoring: {e}")


@functions_framework.http
def generate_compliance_report(request):
    """Cloud Function entry point for generating database governance compliance reports."""
    try:
        # Initialize the reporter
        reporter = DatabaseGovernanceReporter()
        
        # Generate compliance report
        logger.info("Starting database governance compliance report generation")
        report = reporter.generate_compliance_report()
        
        if "status" in report and report["status"] == "error":
            logger.error(f"Report generation failed: {report.get('message', 'Unknown error')}")
            return {
                "status": "error",
                "message": report.get("message", "Unknown error")
            }, 500
        
        # Save report to Cloud Storage
        storage_location = reporter.save_report_to_storage(report)
        
        # Send compliance score to monitoring
        if "overall_compliance_score" in report:
            reporter.send_compliance_metric(report["overall_compliance_score"])
        
        # Log compliance score for log-based metrics
        logger.info(json.dumps({
            "compliance_score": report.get("overall_compliance_score", 0.0),
            "total_databases": report.get("total_databases", 0),
            "compliant_databases": report.get("compliant_databases", 0),
            "violations": len(report.get("violations", []))
        }))
        
        # Return summary response
        response = {
            "status": "success",
            "timestamp": report.get("timestamp"),
            "summary": report.get("summary", {}),
            "report_location": storage_location,
            "compliance_score": report.get("overall_compliance_score", 0.0),
            "recommendations_count": len(report.get("recommendations", []))
        }
        
        logger.info(f"Compliance report generated successfully: {response}")
        return response
        
    except Exception as e:
        error_message = f"Unexpected error in compliance report generation: {str(e)}"
        logger.error(error_message)
        return {
            "status": "error",
            "message": error_message,
            "timestamp": datetime.datetime.now().isoformat()
        }, 500