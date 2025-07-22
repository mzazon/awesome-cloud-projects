import functions_framework
from google.cloud import bigquery
from google.cloud import monitoring_v3
import json
import os
from datetime import datetime, timedelta

@functions_framework.http
def analyze_costs(request):
    """Analyze cost trends and generate optimization recommendations."""
    
    client = bigquery.Client()
    project_id = "${project_id}"
    dataset_name = "${dataset_name}"
    
    try:
        # Query for cost trends over the last 30 days
        query = f"""
        SELECT 
            service.description as service_name,
            DATE(usage_start_time) as usage_date,
            SUM(cost) as daily_cost,
            AVG(cost) OVER (
                PARTITION BY service.description 
                ORDER BY DATE(usage_start_time) 
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
            ) as avg_weekly_cost
        FROM `{project_id}.{dataset_name}.gcp_billing_export_v1_*`
        WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY service_name, usage_date
        ORDER BY usage_date DESC, daily_cost DESC
        """
        
        results = client.query(query).result()
        
        # Analyze results for optimization opportunities
        recommendations = []
        for row in results:
            if row.daily_cost > row.avg_weekly_cost * 1.2:
                recommendations.append({
                    'service': row.service_name,
                    'date': row.usage_date.isoformat(),
                    'current_cost': row.daily_cost,
                    'average_cost': row.avg_weekly_cost,
                    'recommendation': f'Cost spike detected for {row.service_name}. Consider reviewing resource usage.'
                })
        
        return {
            'status': 'success',
            'timestamp': datetime.now().isoformat(),
            'recommendations': recommendations[:10],  # Top 10 recommendations
            'total_recommendations': len(recommendations)
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }