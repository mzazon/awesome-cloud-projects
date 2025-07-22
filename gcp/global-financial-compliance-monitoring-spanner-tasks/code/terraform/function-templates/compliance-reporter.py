import json
from datetime import datetime, timedelta
from google.cloud import spanner
from google.cloud import storage
import functions_framework

# Initialize clients
spanner_client = spanner.Client()
storage_client = storage.Client()

# Configuration from Terraform template variables
SPANNER_INSTANCE = "${spanner_instance}"
SPANNER_DATABASE = "${spanner_database}"
PROJECT_ID = "${project_id}"
BUCKET_NAME = "${bucket_name}"

@functions_framework.http
def generate_compliance_report(request):
    """Generate compliance report for regulatory authorities"""
    
    try:
        # Handle CORS preflight requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        # Set CORS headers for actual request
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        
        # Parse request parameters
        request_json = request.get_json(silent=True) or {}
        report_type = request_json.get('report_type', 'daily')
        jurisdiction = request_json.get('jurisdiction', 'US')
        
        # Validate parameters
        if report_type not in ['daily', 'weekly', 'monthly']:
            return json.dumps({'error': 'Invalid report_type. Must be daily, weekly, or monthly'}), 400, headers
        
        if len(jurisdiction) != 2:
            return json.dumps({'error': 'Invalid jurisdiction. Must be 2-letter country code'}), 400, headers
        
        # Connect to Spanner database
        instance = spanner_client.instance(SPANNER_INSTANCE)
        database = instance.database(SPANNER_DATABASE)
        
        # Generate report data
        report_data = generate_report_data(database, report_type, jurisdiction)
        
        # Save report to Cloud Storage
        report_filename = save_report_to_storage(report_data, report_type, jurisdiction)
        
        response = {
            'report_generated': True,
            'report_file': report_filename,
            'report_type': report_type,
            'jurisdiction': jurisdiction,
            'timestamp': datetime.utcnow().isoformat(),
            'summary': report_data.get('summary_stats', {})
        }
        
        return json.dumps(response), 200, headers
        
    except Exception as e:
        error_response = {
            'report_generated': False,
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }
        return json.dumps(error_response), 500, headers

def generate_report_data(database, report_type, jurisdiction):
    """Generate compliance report data from Spanner"""
    
    # Calculate time range based on report type
    end_date = datetime.utcnow()
    if report_type == 'daily':
        start_date = end_date - timedelta(days=1)
    elif report_type == 'weekly':
        start_date = end_date - timedelta(weeks=1)
    elif report_type == 'monthly':
        start_date = end_date - timedelta(days=30)
    
    with database.snapshot() as snapshot:
        # Query transaction summary
        summary_results = snapshot.execute_sql("""
            SELECT 
                compliance_status,
                COUNT(*) as transaction_count,
                SUM(amount) as total_amount,
                AVG(risk_score) as avg_risk_score
            FROM transactions 
            WHERE created_at >= @start_date
            AND (source_country = @jurisdiction OR destination_country = @jurisdiction)
            GROUP BY compliance_status
        """, params={
            'start_date': start_date,
            'jurisdiction': jurisdiction
        }, param_types={
            'start_date': spanner.param_types.TIMESTAMP,
            'jurisdiction': spanner.param_types.STRING
        })
        
        transaction_summary = []
        for row in summary_results:
            transaction_summary.append({
                'compliance_status': row[0],
                'transaction_count': row[1],
                'total_amount': float(row[2]) if row[2] is not None else 0,
                'avg_risk_score': float(row[3]) if row[3] is not None else 0
            })
        
        # Query high-risk transactions
        high_risk_results = snapshot.execute_sql("""
            SELECT 
                transaction_id, 
                amount, 
                source_country, 
                destination_country, 
                risk_score, 
                compliance_status,
                transaction_type,
                created_at
            FROM transactions
            WHERE created_at >= @start_date
            AND risk_score > 75
            AND (source_country = @jurisdiction OR destination_country = @jurisdiction)
            ORDER BY risk_score DESC
            LIMIT 100
        """, params={
            'start_date': start_date,
            'jurisdiction': jurisdiction
        }, param_types={
            'start_date': spanner.param_types.TIMESTAMP,
            'jurisdiction': spanner.param_types.STRING
        })
        
        high_risk_transactions = []
        for row in high_risk_results:
            high_risk_transactions.append({
                'transaction_id': row[0],
                'amount': float(row[1]) if row[1] is not None else 0,
                'source_country': row[2],
                'destination_country': row[3],
                'risk_score': float(row[4]) if row[4] is not None else 0,
                'compliance_status': row[5],
                'transaction_type': row[6],
                'created_at': row[7].isoformat() if row[7] else None
            })
        
        # Query compliance statistics
        stats_results = snapshot.execute_sql("""
            SELECT 
                COUNT(*) as total_transactions,
                COUNT(CASE WHEN compliance_status = 'APPROVED' THEN 1 END) as approved_count,
                COUNT(CASE WHEN compliance_status = 'HIGH_RISK' THEN 1 END) as high_risk_count,
                COUNT(CASE WHEN compliance_status = 'BLOCKED' THEN 1 END) as blocked_count,
                AVG(risk_score) as overall_avg_risk_score,
                MAX(amount) as max_transaction_amount,
                MIN(amount) as min_transaction_amount
            FROM transactions
            WHERE created_at >= @start_date
            AND (source_country = @jurisdiction OR destination_country = @jurisdiction)
        """, params={
            'start_date': start_date,
            'jurisdiction': jurisdiction
        }, param_types={
            'start_date': spanner.param_types.TIMESTAMP,
            'jurisdiction': spanner.param_types.STRING
        })
        
        stats_row = list(stats_results)[0]
        summary_stats = {
            'total_transactions': stats_row[0] or 0,
            'approved_count': stats_row[1] or 0,
            'high_risk_count': stats_row[2] or 0,
            'blocked_count': stats_row[3] or 0,
            'overall_avg_risk_score': float(stats_row[4]) if stats_row[4] is not None else 0,
            'max_transaction_amount': float(stats_row[5]) if stats_row[5] is not None else 0,
            'min_transaction_amount': float(stats_row[6]) if stats_row[6] is not None else 0
        }
        
        return {
            'summary': transaction_summary,
            'high_risk_transactions': high_risk_transactions,
            'summary_stats': summary_stats,
            'report_period': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            },
            'metadata': {
                'report_type': report_type,
                'jurisdiction': jurisdiction,
                'generated_at': datetime.utcnow().isoformat()
            }
        }

def save_report_to_storage(report_data, report_type, jurisdiction):
    """Save compliance report to Cloud Storage"""
    
    # Generate filename with timestamp
    timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    filename = f'{jurisdiction.lower()}/{report_type}-compliance-report-{timestamp}.json'
    
    try:
        # Get bucket
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # Create blob and upload report
        blob = bucket.blob(filename)
        blob.upload_from_string(
            json.dumps(report_data, indent=2, default=str),
            content_type='application/json'
        )
        
        # Set metadata
        blob.metadata = {
            'report_type': report_type,
            'jurisdiction': jurisdiction,
            'generated_at': datetime.utcnow().isoformat(),
            'generator': 'compliance-reporter-function'
        }
        blob.patch()
        
        return f'gs://{BUCKET_NAME}/{filename}'
        
    except Exception as e:
        print(f"Error saving report to storage: {str(e)}")
        raise