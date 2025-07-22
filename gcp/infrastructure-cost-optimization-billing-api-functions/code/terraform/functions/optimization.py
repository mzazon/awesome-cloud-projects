import functions_framework
from google.cloud import bigquery
from google.cloud import monitoring_v3
import json
import os
from datetime import datetime, timedelta

@functions_framework.http
def optimize_resources(request):
    """Generate resource optimization recommendations."""
    
    client = bigquery.Client()
    monitoring_client = monitoring_v3.MetricServiceClient()
    
    project_id = "${project_id}"
    dataset_name = "${dataset_name}"
    
    try:
        # Analyze compute instance usage patterns
        compute_query = f"""
        SELECT 
            resource.labels.instance_id,
            resource.labels.zone,
            SUM(cost) as total_cost,
            COUNT(DISTINCT DATE(usage_start_time)) as active_days
        FROM `{project_id}.{dataset_name}.gcp_billing_export_v1_*`
        WHERE service.description = 'Compute Engine'
        AND DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        GROUP BY instance_id, zone
        HAVING total_cost > 0
        ORDER BY total_cost DESC
        """
        
        compute_results = client.query(compute_query).result()
        
        # Analyze storage usage
        storage_query = f"""
        SELECT 
            sku.description,
            SUM(cost) as total_cost,
            SUM(usage.amount) as usage_amount,
            usage.unit
        FROM `{project_id}.{dataset_name}.gcp_billing_export_v1_*`
        WHERE service.description = 'Cloud Storage'
        AND DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY sku.description, usage.unit
        ORDER BY total_cost DESC
        """
        
        storage_results = client.query(storage_query).result()
        
        # Generate optimization recommendations
        recommendations = []
        
        # Compute optimizations
        for row in compute_results:
            if row.active_days < 7:  # Instance not used every day
                recommendations.append({
                    'type': 'compute_scheduling',
                    'resource': row.instance_id,
                    'zone': row.zone,
                    'current_cost': float(row.total_cost),
                    'recommendation': 'Consider scheduling instance shutdown during off-hours',
                    'potential_savings': float(row.total_cost) * 0.3
                })
        
        # Storage optimizations
        for row in storage_results:
            if 'Standard' in row.sku_description and row.total_cost > 50:
                recommendations.append({
                    'type': 'storage_lifecycle',
                    'resource': row.sku_description,
                    'current_cost': float(row.total_cost),
                    'recommendation': 'Implement lifecycle policies for long-term storage',
                    'potential_savings': float(row.total_cost) * 0.4
                })
        
        # Calculate total potential savings
        total_savings = sum(r.get('potential_savings', 0) for r in recommendations)
        
        return {
            'status': 'success',
            'timestamp': datetime.now().isoformat(),
            'recommendations': recommendations[:15],
            'total_potential_savings': total_savings,
            'summary': {
                'compute_recommendations': len([r for r in recommendations if r['type'] == 'compute_scheduling']),
                'storage_recommendations': len([r for r in recommendations if r['type'] == 'storage_lifecycle'])
            }
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }