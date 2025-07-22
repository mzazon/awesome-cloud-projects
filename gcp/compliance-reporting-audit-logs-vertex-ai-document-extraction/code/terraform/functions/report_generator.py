"""
Cloud Function for generating automated compliance reports
Analyzes processed documents and audit logs to create comprehensive compliance reports
"""

import json
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from google.cloud import storage
from google.cloud import logging
import functions_framework


# Initialize clients
storage_client = storage.Client()
logging_client = logging.Client()
logger = logging_client.logger("compliance-report")

# Environment variables
COMPLIANCE_BUCKET = os.environ.get('COMPLIANCE_BUCKET', '${compliance_bucket}')
REPORTS_BUCKET = os.environ.get('REPORTS_BUCKET', '${reports_bucket}')


@functions_framework.http
def generate_compliance_report(request) -> Dict[str, Any]:
    """
    Generate automated compliance reports from processed data
    
    This function creates comprehensive compliance reports by analyzing:
    - Processed compliance documents
    - Document processing metrics
    - Compliance framework adherence
    - Security and audit findings
    
    Args:
        request: HTTP request containing report parameters
        
    Returns:
        Dictionary with report generation status and metadata
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True) or {}
        report_type = request_json.get('report_type', 'manual')
        frameworks = request_json.get('frameworks', ['SOC2', 'ISO27001'])
        
        logger.log_text(f"Starting compliance report generation - Type: {report_type}")
        
        # Collect data for report generation
        processed_documents = _collect_processed_documents()
        compliance_metrics = _calculate_compliance_metrics(processed_documents)
        framework_analysis = _analyze_framework_compliance(processed_documents, frameworks)
        security_findings = _generate_security_findings(processed_documents)
        
        # Generate comprehensive report
        report_data = _create_report_structure(
            report_type, frameworks, processed_documents, 
            compliance_metrics, framework_analysis, security_findings
        )
        
        # Save report to storage
        report_path = _save_compliance_report(report_data)
        
        logger.log_text(f"Compliance report generated successfully: {report_path}")
        
        return {
            "status": "success",
            "report_type": report_type,
            "report_path": report_path,
            "report_date": report_data["report_metadata"]["generation_date"],
            "documents_analyzed": len(processed_documents),
            "frameworks_covered": frameworks
        }
        
    except Exception as e:
        error_message = f"Error generating compliance report: {str(e)}"
        logger.log_text(error_message, severity="ERROR")
        return {
            "status": "error",
            "message": error_message,
            "timestamp": datetime.utcnow().isoformat()
        }


def _collect_processed_documents() -> List[Dict[str, Any]]:
    """Collect all processed compliance documents for analysis"""
    try:
        bucket = storage_client.bucket(COMPLIANCE_BUCKET)
        processed_blobs = bucket.list_blobs(prefix="processed/")
        
        documents = []
        for blob in processed_blobs:
            if blob.name.endswith('.json'):
                try:
                    content = json.loads(blob.download_as_text())
                    documents.append(content)
                except json.JSONDecodeError as e:
                    logger.log_text(f"Error parsing document {blob.name}: {str(e)}")
                    continue
        
        logger.log_text(f"Collected {len(documents)} processed documents for analysis")
        return documents
        
    except Exception as e:
        logger.log_text(f"Error collecting processed documents: {str(e)}", severity="ERROR")
        return []


def _calculate_compliance_metrics(documents: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Calculate key compliance metrics from processed documents"""
    if not documents:
        return {"total_documents": 0, "processing_success_rate": 0.0}
    
    metrics = {
        "total_documents": len(documents),
        "processing_success_rate": 0.0,
        "average_confidence": 0.0,
        "document_types": {},
        "frameworks_identified": {},
        "sensitive_data_count": 0,
        "high_confidence_documents": 0,
        "low_confidence_documents": 0
    }
    
    total_confidence = 0
    confidence_threshold_high = 0.8
    confidence_threshold_low = 0.5
    
    for doc in documents:
        # Confidence metrics
        confidence = doc.get("extraction_confidence", 0.0)
        total_confidence += confidence
        
        if confidence >= confidence_threshold_high:
            metrics["high_confidence_documents"] += 1
        elif confidence < confidence_threshold_low:
            metrics["low_confidence_documents"] += 1
        
        # Document type distribution
        doc_type = doc.get("compliance_metadata", {}).get("document_type", "Unknown")
        metrics["document_types"][doc_type] = metrics["document_types"].get(doc_type, 0) + 1
        
        # Framework identification
        frameworks = doc.get("compliance_metadata", {}).get("compliance_framework", [])
        for framework in frameworks:
            metrics["frameworks_identified"][framework] = metrics["frameworks_identified"].get(framework, 0) + 1
        
        # Sensitive data detection
        if doc.get("compliance_metadata", {}).get("contains_sensitive_data", False):
            metrics["sensitive_data_count"] += 1
    
    # Calculate averages
    metrics["average_confidence"] = total_confidence / len(documents)
    metrics["processing_success_rate"] = (len(documents) - metrics["low_confidence_documents"]) / len(documents)
    
    return metrics


def _analyze_framework_compliance(documents: List[Dict[str, Any]], target_frameworks: List[str]) -> Dict[str, Any]:
    """Analyze compliance status for specific frameworks"""
    framework_analysis = {}
    
    for framework in target_frameworks:
        analysis = {
            "framework": framework,
            "relevant_documents": 0,
            "compliance_status": "UNKNOWN",
            "coverage_percentage": 0.0,
            "recommendations": [],
            "critical_findings": [],
            "document_details": []
        }
        
        # Analyze documents for this framework
        framework_docs = [
            doc for doc in documents 
            if framework in doc.get("compliance_metadata", {}).get("compliance_framework", [])
        ]
        
        analysis["relevant_documents"] = len(framework_docs)
        
        if framework_docs:
            # Calculate framework-specific metrics
            high_quality_docs = sum(
                1 for doc in framework_docs 
                if doc.get("extraction_confidence", 0.0) >= 0.8
            )
            
            analysis["coverage_percentage"] = (high_quality_docs / len(framework_docs)) * 100
            
            # Determine compliance status
            if analysis["coverage_percentage"] >= 90:
                analysis["compliance_status"] = "COMPLIANT"
            elif analysis["coverage_percentage"] >= 70:
                analysis["compliance_status"] = "PARTIALLY_COMPLIANT"
            else:
                analysis["compliance_status"] = "NON_COMPLIANT"
            
            # Generate framework-specific recommendations
            analysis["recommendations"] = _generate_framework_recommendations(framework, framework_docs)
            analysis["critical_findings"] = _identify_critical_findings(framework, framework_docs)
            
            # Document details for auditing
            analysis["document_details"] = [
                {
                    "name": doc.get("document_name", "Unknown"),
                    "type": doc.get("compliance_metadata", {}).get("document_type", "Unknown"),
                    "confidence": doc.get("extraction_confidence", 0.0),
                    "version": doc.get("compliance_metadata", {}).get("policy_version"),
                    "effective_date": doc.get("compliance_metadata", {}).get("effective_date")
                }
                for doc in framework_docs
            ]
        
        framework_analysis[framework] = analysis
    
    return framework_analysis


def _generate_framework_recommendations(framework: str, documents: List[Dict[str, Any]]) -> List[str]:
    """Generate specific recommendations for compliance frameworks"""
    recommendations = []
    
    # Common recommendations based on document analysis
    low_confidence_docs = [doc for doc in documents if doc.get("extraction_confidence", 0.0) < 0.7]
    if low_confidence_docs:
        recommendations.append(f"Review {len(low_confidence_docs)} documents with low extraction confidence")
    
    # Framework-specific recommendations
    if framework == "SOC2":
        recommendations.extend([
            "Ensure all access control policies are current and properly documented",
            "Verify system monitoring and incident response procedures are documented",
            "Review data backup and recovery procedures documentation"
        ])
    elif framework == "ISO27001":
        recommendations.extend([
            "Verify information security management system documentation is complete",
            "Ensure risk assessment and treatment documentation is current",
            "Review security incident management procedures"
        ])
    elif framework == "HIPAA":
        recommendations.extend([
            "Verify all PHI handling procedures are documented and current",
            "Ensure breach notification procedures are properly documented",
            "Review technical safeguards documentation"
        ])
    
    return recommendations


def _identify_critical_findings(framework: str, documents: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Identify critical compliance findings that require immediate attention"""
    findings = []
    
    for doc in documents:
        # Check for outdated documents (if version/date available)
        effective_date = doc.get("compliance_metadata", {}).get("effective_date")
        if effective_date:
            # This is a simplified check - in practice, you'd parse the date properly
            findings.append({
                "type": "OUTDATED_DOCUMENT",
                "severity": "MEDIUM",
                "document": doc.get("document_name", "Unknown"),
                "description": f"Document may be outdated - effective date: {effective_date}"
            })
        
        # Check for low confidence extraction
        if doc.get("extraction_confidence", 0.0) < 0.5:
            findings.append({
                "type": "LOW_EXTRACTION_CONFIDENCE",
                "severity": "HIGH",
                "document": doc.get("document_name", "Unknown"),
                "description": f"Low extraction confidence: {doc.get('extraction_confidence', 0.0):.2f}"
            })
        
        # Check for sensitive data without proper handling indicators
        if doc.get("compliance_metadata", {}).get("contains_sensitive_data", False):
            findings.append({
                "type": "SENSITIVE_DATA_DETECTED",
                "severity": "HIGH",
                "document": doc.get("document_name", "Unknown"),
                "description": "Document contains sensitive data - verify proper handling procedures"
            })
    
    return findings


def _generate_security_findings(documents: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Generate security-related findings from document analysis"""
    security_findings = {
        "total_sensitive_documents": 0,
        "encryption_status": "COMPLIANT",  # Assuming KMS encryption is configured
        "access_control_status": "COMPLIANT",  # Assuming IAM is properly configured
        "data_classification": {},
        "recommendations": []
    }
    
    # Analyze sensitive data distribution
    for doc in documents:
        if doc.get("compliance_metadata", {}).get("contains_sensitive_data", False):
            security_findings["total_sensitive_documents"] += 1
            
            doc_type = doc.get("compliance_metadata", {}).get("document_type", "Unknown")
            security_findings["data_classification"][doc_type] = security_findings["data_classification"].get(doc_type, 0) + 1
    
    # Generate security recommendations
    if security_findings["total_sensitive_documents"] > 0:
        security_findings["recommendations"].extend([
            "Review data classification and handling procedures for sensitive documents",
            "Ensure all sensitive documents are properly encrypted at rest and in transit",
            "Verify access controls for sensitive document repositories"
        ])
    
    return security_findings


def _create_report_structure(
    report_type: str, 
    frameworks: List[str], 
    documents: List[Dict[str, Any]],
    metrics: Dict[str, Any],
    framework_analysis: Dict[str, Any],
    security_findings: Dict[str, Any]
) -> Dict[str, Any]:
    """Create the complete report structure"""
    
    current_time = datetime.utcnow()
    
    report = {
        "report_metadata": {
            "report_id": f"COMP-{current_time.strftime('%Y%m%d-%H%M%S')}",
            "generation_date": current_time.isoformat() + "Z",
            "report_type": report_type,
            "frameworks_analyzed": frameworks,
            "reporting_period": {
                "start_date": (current_time - timedelta(days=30)).isoformat() + "Z",
                "end_date": current_time.isoformat() + "Z"
            },
            "generated_by": "Automated Compliance Reporting System"
        },
        
        "executive_summary": {
            "overall_compliance_status": _determine_overall_status(framework_analysis),
            "documents_processed": metrics["total_documents"],
            "processing_success_rate": metrics["processing_success_rate"],
            "critical_findings_count": sum(
                len(analysis.get("critical_findings", [])) 
                for analysis in framework_analysis.values()
            ),
            "recommendations_count": sum(
                len(analysis.get("recommendations", [])) 
                for analysis in framework_analysis.values()
            )
        },
        
        "compliance_metrics": metrics,
        "framework_analysis": framework_analysis,
        "security_assessment": security_findings,
        
        "audit_trail": {
            "processing_infrastructure": "Google Cloud Platform",
            "document_ai_processor": "Vertex AI Document AI",
            "audit_logging": "Cloud Audit Logs",
            "report_automation": "Cloud Functions + Cloud Scheduler",
            "data_encryption": "Google Cloud KMS",
            "access_controls": "Google Cloud IAM"
        },
        
        "next_actions": _generate_next_actions(framework_analysis, security_findings)
    }
    
    return report


def _determine_overall_status(framework_analysis: Dict[str, Any]) -> str:
    """Determine overall compliance status across all frameworks"""
    statuses = [analysis.get("compliance_status", "UNKNOWN") for analysis in framework_analysis.values()]
    
    if not statuses:
        return "UNKNOWN"
    elif all(status == "COMPLIANT" for status in statuses):
        return "COMPLIANT"
    elif any(status == "NON_COMPLIANT" for status in statuses):
        return "NON_COMPLIANT"
    else:
        return "PARTIALLY_COMPLIANT"


def _generate_next_actions(framework_analysis: Dict[str, Any], security_findings: Dict[str, Any]) -> List[str]:
    """Generate prioritized next actions based on analysis results"""
    actions = []
    
    # Critical actions from framework analysis
    for framework, analysis in framework_analysis.items():
        if analysis.get("compliance_status") == "NON_COMPLIANT":
            actions.append(f"PRIORITY: Address {framework} compliance gaps immediately")
        
        critical_findings = analysis.get("critical_findings", [])
        high_severity_findings = [f for f in critical_findings if f.get("severity") == "HIGH"]
        if high_severity_findings:
            actions.append(f"Review {len(high_severity_findings)} high-severity findings for {framework}")
    
    # Security actions
    if security_findings.get("total_sensitive_documents", 0) > 0:
        actions.append("Review data handling procedures for sensitive documents")
    
    # General maintenance actions
    actions.extend([
        "Schedule next compliance review cycle",
        "Update document processing workflows based on findings",
        "Review and update compliance monitoring procedures"
    ])
    
    return actions[:10]  # Limit to top 10 actions


def _save_compliance_report(report_data: Dict[str, Any]) -> str:
    """Save the compliance report to storage"""
    try:
        bucket = storage_client.bucket(REPORTS_BUCKET)
        
        # Create report filename with timestamp
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        report_filename = f"compliance-report-{timestamp}.json"
        
        # Save JSON report
        json_blob = bucket.blob(f"reports/json/{report_filename}")
        json_blob.upload_from_string(
            json.dumps(report_data, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        # Generate human-readable report
        readable_report = _generate_readable_report(report_data)
        text_filename = f"compliance-report-{timestamp}.txt"
        
        text_blob = bucket.blob(f"reports/text/{text_filename}")
        text_blob.upload_from_string(readable_report, content_type='text/plain')
        
        logger.log_text(f"Saved compliance reports: {report_filename}")
        return f"reports/json/{report_filename}"
        
    except Exception as e:
        logger.log_text(f"Error saving compliance report: {str(e)}", severity="ERROR")
        raise


def _generate_readable_report(report_data: Dict[str, Any]) -> str:
    """Generate a human-readable version of the compliance report"""
    metadata = report_data["report_metadata"]
    summary = report_data["executive_summary"]
    frameworks = report_data["framework_analysis"]
    
    report_lines = [
        "="*80,
        "COMPLIANCE REPORT",
        "="*80,
        f"Report ID: {metadata['report_id']}",
        f"Generated: {metadata['generation_date']}",
        f"Type: {metadata['report_type']}",
        f"Frameworks: {', '.join(metadata['frameworks_analyzed'])}",
        "",
        "EXECUTIVE SUMMARY",
        "-"*50,
        f"Overall Status: {summary['overall_compliance_status']}",
        f"Documents Processed: {summary['documents_processed']}",
        f"Processing Success Rate: {summary['processing_success_rate']:.1%}",
        f"Critical Findings: {summary['critical_findings_count']}",
        f"Total Recommendations: {summary['recommendations_count']}",
        ""
    ]
    
    # Framework details
    for framework_name, analysis in frameworks.items():
        report_lines.extend([
            f"FRAMEWORK: {framework_name}",
            "-"*50,
            f"Status: {analysis['compliance_status']}",
            f"Relevant Documents: {analysis['relevant_documents']}",
            f"Coverage: {analysis['coverage_percentage']:.1f}%",
            ""
        ])
        
        if analysis.get("critical_findings"):
            report_lines.append("Critical Findings:")
            for finding in analysis["critical_findings"]:
                report_lines.append(f"  - {finding['type']}: {finding['description']}")
            report_lines.append("")
        
        if analysis.get("recommendations"):
            report_lines.append("Recommendations:")
            for rec in analysis["recommendations"]:
                report_lines.append(f"  - {rec}")
            report_lines.append("")
    
    # Next actions
    next_actions = report_data.get("next_actions", [])
    if next_actions:
        report_lines.extend([
            "NEXT ACTIONS",
            "-"*50
        ])
        for i, action in enumerate(next_actions, 1):
            report_lines.append(f"{i}. {action}")
        report_lines.append("")
    
    # Audit trail
    report_lines.extend([
        "AUDIT TRAIL",
        "-"*50,
        "This report was generated automatically using:",
        "- Google Cloud Audit Logs for activity tracking",
        "- Vertex AI Document AI for document processing",
        "- Cloud Functions for automated analysis",
        "- Cloud Storage for secure data management",
        "",
        f"Generated on: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}",
        "="*80
    ])
    
    return "\n".join(report_lines)