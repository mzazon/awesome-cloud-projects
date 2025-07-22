"""
Climate Risk Assessment - Monitoring Function
This Cloud Function monitors climate risk levels and generates alerts.
"""

import functions_framework
from google.cloud import bigquery
from google.cloud import monitoring_v3
import json
from datetime import datetime, timedelta
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@functions_framework.http
def monitor_climate_risks(request):
    """
    Monitor climate risk levels and generate alerts
    
    Args:
        request: HTTP request object with JSON payload containing:
            - dataset_id: BigQuery dataset ID
    
    Returns:
        JSON response with monitoring results and alerts
    """
    try:
        # Parse request parameters
        request_json = request.get_json()
        if not request_json:
            return {'error': 'No JSON data provided'}, 400
        
        dataset_id = request_json.get('dataset_id')
        if not dataset_id:
            return {'error': 'dataset_id is required'}, 400
        
        logger.info(f"Monitoring climate risks for dataset: {dataset_id}")
        
        client = bigquery.Client()
        project_id = os.environ.get('PROJECT_ID', client.project)
        
        # Check if climate risk analysis view exists
        view_id = f"{project_id}.{dataset_id}.climate_risk_analysis"
        
        try:
            client.get_table(view_id)
        except Exception as e:
            logger.warning(f"Climate risk analysis view not found: {str(e)}")
            return {
                'status': 'warning',
                'message': 'Climate risk analysis view not found. Please run climate data processing first.',
                'timestamp': datetime.now().isoformat()
            }, 404
        
        # Query current risk levels
        query = f"""
        SELECT 
          risk_category,
          COUNT(*) as location_count,
          AVG(composite_risk_score) as avg_risk_score,
          MAX(composite_risk_score) as max_risk_score,
          MIN(composite_risk_score) as min_risk_score,
          ST_CENTROID(ST_UNION_AGG(region_center)) as risk_center
        FROM `{view_id}`
        GROUP BY risk_category
        ORDER BY avg_risk_score DESC
        """
        
        logger.info("Querying current risk levels...")
        results = client.query(query).to_dataframe()
        
        if results.empty:
            return {
                'status': 'warning',
                'message': 'No climate risk data found. Please run climate data processing first.',
                'timestamp': datetime.now().isoformat()
            }, 404
        
        # Calculate system metrics
        total_locations = results['location_count'].sum()
        high_risk_locations = results[results['risk_category'] == 'HIGH']['location_count'].sum()
        high_risk_percentage = (high_risk_locations / total_locations) * 100 if total_locations > 0 else 0
        
        logger.info(f"Analysis complete: {total_locations} locations, "
                   f"{high_risk_percentage:.1f}% high risk")
        
        # Create custom metrics for Cloud Monitoring
        try:
            monitoring_client = monitoring_v3.MetricServiceClient()
            project_name = f"projects/{project_id}"
            
            # Create time series for high risk percentage
            series = monitoring_v3.TimeSeries()
            series.metric.type = "custom.googleapis.com/climate_risk/high_risk_percentage"
            series.resource.type = "global"
            
            point = monitoring_v3.Point()
            point.value.double_value = high_risk_percentage
            point.interval.end_time.seconds = int(datetime.now().timestamp())
            series.points = [point]
            
            monitoring_client.create_time_series(
                name=project_name, 
                time_series=[series]
            )
            
            logger.info("Custom metrics sent to Cloud Monitoring")
            
        except Exception as e:
            logger.warning(f"Failed to send metrics to Cloud Monitoring: {str(e)}")
        
        # Generate response with risk summary
        risk_distribution = []
        for _, row in results.iterrows():
            risk_distribution.append({
                'risk_category': row['risk_category'],
                'location_count': int(row['location_count']),
                'avg_risk_score': round(float(row['avg_risk_score']), 2),
                'max_risk_score': round(float(row['max_risk_score']), 2),
                'min_risk_score': round(float(row['min_risk_score']), 2)
            })
        
        response = {
            'status': 'success',
            'timestamp': datetime.now().isoformat(),
            'total_locations_analyzed': int(total_locations),
            'high_risk_locations': int(high_risk_locations),
            'high_risk_percentage': round(high_risk_percentage, 2),
            'risk_distribution': risk_distribution,
            'alerts': []
        }
        
        # Generate alerts for high risk conditions
        if high_risk_percentage > 25:
            response['alerts'].append({
                'level': 'WARNING',
                'message': f'{high_risk_percentage:.1f}% of monitored locations show high climate risk',
                'action': 'Review adaptation strategies for high-risk areas',
                'threshold': 25.0,
                'current_value': high_risk_percentage
            })
        
        if high_risk_percentage > 50:
            response['alerts'].append({
                'level': 'CRITICAL',
                'message': f'{high_risk_percentage:.1f}% of monitored locations show high climate risk',
                'action': 'Immediate review of climate adaptation plans required',
                'threshold': 50.0,
                'current_value': high_risk_percentage
            })
        
        # Check for extreme risk scores
        max_risk_score = results['max_risk_score'].max()
        if max_risk_score > 80:
            response['alerts'].append({
                'level': 'CRITICAL',
                'message': f'Extreme climate risk detected (score: {max_risk_score:.1f})',
                'action': 'Investigate locations with extreme risk scores',
                'threshold': 80.0,
                'current_value': max_risk_score
            })
        
        # Add recommendations based on risk levels
        if high_risk_percentage > 0:
            response['recommendations'] = []
            
            if high_risk_percentage > 25:
                response['recommendations'].append(
                    "Consider implementing climate adaptation measures in high-risk areas"
                )
            
            if high_risk_percentage > 50:
                response['recommendations'].append(
                    "Urgent review of infrastructure resilience required"
                )
            
            response['recommendations'].append(
                "Monitor weather patterns and satellite data for early warning signs"
            )
        
        logger.info(f"Climate risk monitoring completed successfully. "
                   f"Generated {len(response['alerts'])} alerts.")
        
        return response
        
    except Exception as e:
        logger.error(f"Error monitoring climate risks: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }, 500