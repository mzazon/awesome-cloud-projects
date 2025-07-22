import json
from google.cloud import bigquery
from google.cloud import storage
import pandas as pd
from datetime import datetime, timedelta
import functions_framework
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment variables
PROJECT_ID = "${project_id}"
DATASET_NAME = "${dataset_name}"
BUCKET_NAME = "${bucket_name}"

@functions_framework.http
def generate_cost_report(request):
    """Generate weekly cost allocation report."""
    
    try:
        logger.info("Starting cost allocation report generation")
        
        # Initialize clients
        bq_client = bigquery.Client()
        storage_client = storage.Client()
        
        # Query cost allocation data for the last 7 days
        cost_query = f"""
        SELECT 
            billing_date,
            project_id,
            service,
            sku,
            SUM(cost) as total_cost,
            currency,
            department,
            cost_center,
            environment,
            project_code,
            COUNT(*) as line_items
        FROM `{PROJECT_ID}.{DATASET_NAME}.cost_allocation`
        WHERE billing_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        GROUP BY 
            billing_date, project_id, service, sku, 
            currency, department, cost_center, environment, project_code
        ORDER BY total_cost DESC
        """
        
        logger.info("Executing cost allocation query")
        cost_df = bq_client.query(cost_query).to_dataframe()
        
        # Query compliance data
        compliance_query = f"""
        SELECT 
            DATE(timestamp) as compliance_date,
            resource_type,
            department,
            cost_center,
            COUNT(*) as total_resources,
            SUM(CASE WHEN compliant THEN 1 ELSE 0 END) as compliant_resources,
            ROUND(100.0 * SUM(CASE WHEN compliant THEN 1 ELSE 0 END) / COUNT(*), 2) as compliance_percentage
        FROM `{PROJECT_ID}.{DATASET_NAME}.tag_compliance`
        WHERE DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        GROUP BY compliance_date, resource_type, department, cost_center
        ORDER BY compliance_date DESC, compliance_percentage ASC
        """
        
        logger.info("Executing compliance query")
        compliance_df = bq_client.query(compliance_query).to_dataframe()
        
        # Generate report summary
        if not cost_df.empty:
            total_cost = cost_df['total_cost'].sum()
            currency = cost_df['currency'].iloc[0] if not cost_df.empty else 'USD'
            
            # Top departments by cost
            dept_costs = cost_df.groupby('department')['total_cost'].sum().head(5)
            
            # Top services by cost
            service_costs = cost_df.groupby('service')['total_cost'].sum().head(5)
            
        else:
            total_cost = 0.0
            currency = 'USD'
            dept_costs = pd.Series(dtype=float)
            service_costs = pd.Series(dtype=float)
        
        # Calculate overall compliance rate
        if not compliance_df.empty:
            overall_compliance = (
                compliance_df['compliant_resources'].sum() / 
                compliance_df['total_resources'].sum() * 100
            )
        else:
            overall_compliance = 0.0
        
        # Generate comprehensive report
        report = {
            'report_metadata': {
                'generated_at': datetime.utcnow().isoformat(),
                'report_period': '7 days',
                'project_id': PROJECT_ID,
                'dataset': DATASET_NAME
            },
            'cost_summary': {
                'total_weekly_cost': float(total_cost),
                'currency': currency,
                'total_line_items': len(cost_df),
                'departments_with_costs': len(dept_costs)
            },
            'top_departments_by_cost': dept_costs.to_dict(),
            'top_services_by_cost': service_costs.to_dict(),
            'compliance_summary': {
                'overall_compliance_percentage': float(overall_compliance),
                'total_resources_checked': int(compliance_df['total_resources'].sum()) if not compliance_df.empty else 0,
                'compliant_resources': int(compliance_df['compliant_resources'].sum()) if not compliance_df.empty else 0
            },
            'recommendations': generate_recommendations(cost_df, compliance_df)
        }
        
        # Store detailed data as CSV for further analysis
        report_timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        
        # Store report JSON
        bucket = storage_client.bucket(BUCKET_NAME)
        json_blob = bucket.blob(f"reports/cost-allocation-{report_timestamp}.json")
        json_blob.upload_from_string(
            json.dumps(report, indent=2, default=str),
            content_type='application/json'
        )
        
        # Store detailed cost data as CSV
        if not cost_df.empty:
            csv_blob = bucket.blob(f"reports/cost-details-{report_timestamp}.csv")
            csv_blob.upload_from_string(
                cost_df.to_csv(index=False),
                content_type='text/csv'
            )
        
        # Store compliance data as CSV
        if not compliance_df.empty:
            compliance_csv_blob = bucket.blob(f"reports/compliance-details-{report_timestamp}.csv")
            compliance_csv_blob.upload_from_string(
                compliance_df.to_csv(index=False),
                content_type='text/csv'
            )
        
        logger.info(f"Report generated successfully: cost-allocation-{report_timestamp}.json")
        
        return {
            'status': 'success',
            'report': report,
            'files_generated': [
                f"reports/cost-allocation-{report_timestamp}.json",
                f"reports/cost-details-{report_timestamp}.csv" if not cost_df.empty else None,
                f"reports/compliance-details-{report_timestamp}.csv" if not compliance_df.empty else None
            ]
        }
        
    except Exception as e:
        logger.error(f"Error generating cost report: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }, 500

def generate_recommendations(cost_df, compliance_df):
    """Generate actionable recommendations based on cost and compliance data."""
    recommendations = []
    
    # Cost-based recommendations
    if not cost_df.empty:
        # Identify departments with high costs
        dept_costs = cost_df.groupby('department')['total_cost'].sum()
        if len(dept_costs) > 0:
            highest_cost_dept = dept_costs.idxmax()
            recommendations.append(
                f"Review spending for department '{highest_cost_dept}' "
                f"(${dept_costs.max():.2f} this week)"
            )
        
        # Identify services with unexpected costs
        service_costs = cost_df.groupby('service')['total_cost'].sum()
        if len(service_costs) > 0:
            recommendations.append(
                f"Top service by cost: {service_costs.idxmax()} "
                f"(${service_costs.max():.2f})"
            )
    
    # Compliance-based recommendations
    if not compliance_df.empty:
        low_compliance = compliance_df[compliance_df['compliance_percentage'] < 80]
        if not low_compliance.empty:
            for _, row in low_compliance.iterrows():
                recommendations.append(
                    f"Improve tagging compliance for {row['resource_type']} "
                    f"in department '{row['department']}' "
                    f"(currently {row['compliance_percentage']:.1f}%)"
                )
    
    if not recommendations:
        recommendations.append("All systems appear to be operating within normal parameters")
    
    return recommendations