import json
import os
from datetime import datetime, timedelta
from google.cloud import bigquery
from google.cloud import functions_v1
import logging

def process_carbon_data(request):
    """Process carbon footprint data and calculate sustainability metrics."""
    try:
        client = bigquery.Client()
        
        # Query latest carbon footprint data
        query = f"""
        SELECT 
            project.id as project_id,
            usage_month,
            SUM(carbon_footprint_total_kgCO2e.amount) as total_emissions,
            SUM(carbon_footprint_kgCO2e.scope1) as scope_1,
            SUM(carbon_footprint_kgCO2e.scope2.location_based) as scope_2_location,
            SUM(carbon_footprint_kgCO2e.scope2.market_based) as scope_2_market,
            SUM(carbon_footprint_kgCO2e.scope3) as scope_3,
            service.description as service,
            location.region as region
        FROM `{client.project}.${dataset_name}.carbon_footprint`
        WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
        GROUP BY project_id, usage_month, service, region
        ORDER BY usage_month DESC
        """
        
        # Execute query and insert into analytics table
        job_config = bigquery.QueryJobConfig()
        job_config.destination = f"{client.project}.${dataset_name}.sustainability_metrics"
        job_config.write_disposition = bigquery.WriteDisposition.WRITE_APPEND
        
        query_job = client.query(query, job_config=job_config)
        results = query_job.result()
        
        # Calculate sustainability KPIs
        kpi_query = f"""
        SELECT 
            COUNT(DISTINCT project_id) as active_projects,
            AVG(total_emissions) as avg_monthly_emissions,
            SUM(total_emissions) as total_org_emissions,
            MAX(usage_month) as latest_month
        FROM `{client.project}.${dataset_name}.sustainability_metrics`
        WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
        """
        
        kpi_results = list(client.query(kpi_query).result())
        
        logging.info(f"Processed carbon data: {len(list(results))} records")
        logging.info(f"KPIs: {kpi_results[0] if kpi_results else 'No data'}")
        
        return {
            'status': 'success',
            'records_processed': query_job.num_dml_affected_rows,
            'processing_time': datetime.now().isoformat()
        }
        
    except Exception as e:
        logging.error(f"Error processing carbon data: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500