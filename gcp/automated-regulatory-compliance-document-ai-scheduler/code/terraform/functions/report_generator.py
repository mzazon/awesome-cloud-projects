import json
from google.cloud import storage
from google.cloud import logging
import functions_framework
import os
from datetime import datetime, timedelta
from collections import defaultdict
import csv
from io import StringIO

# Initialize clients
storage_client = storage.Client()
logging_client = logging.Client()
logger = logging_client.logger('compliance-reporter')

PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
PROCESSED_BUCKET = os.environ.get('PROCESSED_BUCKET', '${processed_bucket}')
REPORTS_BUCKET = os.environ.get('REPORTS_BUCKET', '${reports_bucket}')

@functions_framework.http
def generate_compliance_report(request):
    """Generate compliance reports from processed documents."""
    
    try:
        # Parse request parameters
        request_json = request.get_json(silent=True)
        report_type = request_json.get('report_type', 'daily') if request_json else 'daily'
        
        logger.log_text(f"Generating {report_type} compliance report")
        
        # Get processed documents from the last period
        processed_docs = get_processed_documents(report_type)
        
        # Generate compliance summary
        compliance_summary = generate_compliance_summary(processed_docs)
        
        # Create detailed report
        report_data = {
            'report_type': report_type,
            'generated_timestamp': datetime.utcnow().isoformat(),
            'summary': compliance_summary,
            'detailed_results': processed_docs,
            'recommendations': generate_recommendations(compliance_summary)
        }
        
        # Save JSON report
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        json_report_name = f"reports/{report_type}_compliance_report_{timestamp}.json"
        save_report(json_report_name, json.dumps(report_data, indent=2))
        
        # Generate CSV report for regulatory submissions
        csv_report_name = f"reports/{report_type}_compliance_report_{timestamp}.csv"
        csv_content = generate_csv_report(processed_docs)
        save_report(csv_report_name, csv_content)
        
        logger.log_text(f"Compliance reports generated: {json_report_name}, {csv_report_name}")
        
        return {
            'status': 'success',
            'json_report': json_report_name,
            'csv_report': csv_report_name,
            'summary': compliance_summary
        }
        
    except Exception as e:
        error_msg = f"Error generating compliance report: {str(e)}"
        logger.log_text(error_msg, severity='ERROR')
        return {'status': 'error', 'message': str(e)}, 500

def get_processed_documents(report_type):
    """Retrieve processed documents from the specified time period."""
    bucket = storage_client.bucket(PROCESSED_BUCKET)
    
    # Calculate time filter based on report type
    time_deltas = {
        'daily': timedelta(days=1),
        'weekly': timedelta(weeks=1),
        'monthly': timedelta(days=30)
    }
    
    cutoff_time = datetime.utcnow() - time_deltas.get(report_type, timedelta(days=1))
    processed_docs = []
    
    # List and process documents
    try:
        for blob in bucket.list_blobs(prefix='processed/'):
            if blob.time_created and blob.time_created >= cutoff_time.replace(tzinfo=blob.time_created.tzinfo):
                try:
                    content = blob.download_as_text()
                    doc_data = json.loads(content)
                    processed_docs.append(doc_data)
                except (json.JSONDecodeError, Exception) as e:
                    logger.log_text(f"Error reading document {blob.name}: {str(e)}")
    except Exception as e:
        logger.log_text(f"Error listing documents: {str(e)}")
    
    return processed_docs

def generate_compliance_summary(processed_docs):
    """Generate summary statistics for compliance reporting."""
    summary = {
        'total_documents_processed': len(processed_docs),
        'compliant_documents': 0,
        'non_compliant_documents': 0,
        'documents_with_warnings': 0,
        'common_violations': defaultdict(int),
        'processing_success_rate': 0
    }
    
    for doc in processed_docs:
        validation_results = doc.get('validation_results', {})
        status = validation_results.get('overall_status', 'UNKNOWN')
        
        if status == 'COMPLIANT':
            summary['compliant_documents'] += 1
        elif status == 'NON_COMPLIANT':
            summary['non_compliant_documents'] += 1
            
            # Track common violations
            for violation in validation_results.get('violations', []):
                summary['common_violations'][violation] += 1
        
        if validation_results.get('warnings'):
            summary['documents_with_warnings'] += 1
    
    # Calculate success rate
    if summary['total_documents_processed'] > 0:
        summary['processing_success_rate'] = round((
            summary['compliant_documents'] / summary['total_documents_processed']
        ) * 100, 2)
    
    # Convert defaultdict to regular dict for JSON serialization
    summary['common_violations'] = dict(summary['common_violations'])
    
    return summary

def generate_recommendations(summary):
    """Generate compliance recommendations based on summary data."""
    recommendations = []
    
    if summary['non_compliant_documents'] > 0:
        recommendations.append({
            'priority': 'HIGH',
            'recommendation': f"Address {summary['non_compliant_documents']} non-compliant documents immediately",
            'action': 'Review and remediate compliance violations'
        })
    
    if summary['documents_with_warnings'] > 0:
        recommendations.append({
            'priority': 'MEDIUM',
            'recommendation': f"Review {summary['documents_with_warnings']} documents with warnings",
            'action': 'Improve document quality and formatting'
        })
    
    # Recommendations for common violations
    for violation, count in summary['common_violations'].items():
        if count >= 3:
            recommendations.append({
                'priority': 'MEDIUM',
                'recommendation': f"Common violation detected: {violation} ({count} occurrences)",
                'action': 'Implement process improvements to prevent this violation'
            })
    
    return recommendations

def generate_csv_report(processed_docs):
    """Generate CSV format report for regulatory submissions."""
    output = StringIO()
    writer = csv.writer(output)
    
    # Write header
    writer.writerow([
        'Document Name',
        'Processing Date',
        'Compliance Status',
        'Violations Count',
        'Warnings Count',
        'Key Fields Extracted',
        'Overall Score'
    ])
    
    # Write data rows
    for doc in processed_docs:
        validation_results = doc.get('validation_results', {})
        extracted_data = doc.get('extracted_data', {})
        
        writer.writerow([
            doc.get('document_name', 'Unknown'),
            doc.get('processed_timestamp', 'Unknown'),
            validation_results.get('overall_status', 'UNKNOWN'),
            len(validation_results.get('violations', [])),
            len(validation_results.get('warnings', [])),
            len(extracted_data.get('key_value_pairs', {})),
            calculate_compliance_score(validation_results)
        ])
    
    return output.getvalue()

def calculate_compliance_score(validation_results):
    """Calculate a compliance score (0-100) based on validation results."""
    violations = len(validation_results.get('violations', []))
    warnings = len(validation_results.get('warnings', []))
    checks = len(validation_results.get('checks_performed', []))
    
    if checks == 0:
        return 0
    
    # Start with 100, deduct points for violations and warnings
    score = 100 - (violations * 20) - (warnings * 5)
    return max(0, min(100, score))

def save_report(report_name, content):
    """Save report to Cloud Storage."""
    try:
        bucket = storage_client.bucket(REPORTS_BUCKET)
        blob = bucket.blob(report_name)
        content_type = 'application/json' if report_name.endswith('.json') else 'text/csv'
        blob.upload_from_string(content, content_type=content_type)
    except Exception as e:
        logger.log_text(f"Error saving report {report_name}: {str(e)}", severity='ERROR')
        raise