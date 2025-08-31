import json
import os
from datetime import datetime, timedelta
from google.cloud import bigquery
from google.cloud import storage
import csv
import io
import logging

def generate_esg_report(request):
    """Generate ESG compliance report from carbon footprint data."""
    try:
        client = bigquery.Client()
        storage_client = storage.Client()
        
        # Generate comprehensive ESG report query
        report_query = f"""
        WITH monthly_trends AS (
            SELECT 
                usage_month,
                SUM(total_emissions) as monthly_total,
                AVG(total_emissions) OVER (ORDER BY usage_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as three_month_avg
            FROM `{client.project}.${dataset_name}.sustainability_metrics`
            WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
            GROUP BY usage_month
        ),
        service_breakdown AS (
            SELECT 
                service,
                SUM(total_emissions) as service_emissions,
                ROUND(SUM(total_emissions) / SUM(SUM(total_emissions)) OVER () * 100, 2) as percentage
            FROM `{client.project}.${dataset_name}.sustainability_metrics`
            WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
            GROUP BY service
        )
        SELECT 
            'Monthly Trends' as report_section,
            TO_JSON_STRING(ARRAY_AGG(STRUCT(usage_month, monthly_total, three_month_avg))) as data
        FROM monthly_trends
        UNION ALL
        SELECT 
            'Service Breakdown' as report_section,
            TO_JSON_STRING(ARRAY_AGG(STRUCT(service, service_emissions, percentage))) as data
        FROM service_breakdown
        """
        
        results = list(client.query(report_query).result())
        
        # Create ESG report
        report_data = {
            'report_date': datetime.now().isoformat(),
            'organization': client.project,
            'reporting_period': '12 months',
            'methodology': 'GHG Protocol compliant via Google Cloud Carbon Footprint',
            'sections': {}
        }
        
        for row in results:
            report_data['sections'][row.report_section] = json.loads(row.data)
        
        # Save report to Cloud Storage
        bucket_name = f"esg-reports-${random_suffix}"
        
        try:
            bucket = storage_client.create_bucket(bucket_name)
        except Exception:
            bucket = storage_client.bucket(bucket_name)
        
        blob_name = f"esg-report-{datetime.now().strftime('%Y-%m-%d')}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(report_data, indent=2))
        
        logging.info(f"ESG report generated: gs://{bucket_name}/{blob_name}")
        
        return {
            'status': 'success',
            'report_location': f"gs://{bucket_name}/{blob_name}",
            'generation_time': datetime.now().isoformat()
        }
        
    except Exception as e:
        logging.error(f"Error generating ESG report: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500