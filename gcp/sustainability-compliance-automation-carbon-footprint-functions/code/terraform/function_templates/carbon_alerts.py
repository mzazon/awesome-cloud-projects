import json
import os
from datetime import datetime, timedelta
from google.cloud import bigquery
import logging

def carbon_alerts(request):
    """Monitor carbon emissions and generate sustainability alerts."""
    try:
        client = bigquery.Client()
        
        # Define sustainability thresholds
        MONTHLY_THRESHOLD = ${monthly_threshold}  # kg CO2e
        GROWTH_THRESHOLD = ${growth_threshold}   # month-over-month growth
        
        # Check for threshold violations
        alert_query = f"""
        WITH current_month AS (
            SELECT 
                SUM(total_emissions) as current_emissions,
                MAX(usage_month) as current_month
            FROM `{client.project}.${dataset_name}.sustainability_metrics`
            WHERE usage_month = (
                SELECT MAX(usage_month) 
                FROM `{client.project}.${dataset_name}.sustainability_metrics`
            )
        ),
        previous_month AS (
            SELECT 
                SUM(total_emissions) as previous_emissions
            FROM `{client.project}.${dataset_name}.sustainability_metrics`
            WHERE usage_month = DATE_SUB((
                SELECT MAX(usage_month) 
                FROM `{client.project}.${dataset_name}.sustainability_metrics`
            ), INTERVAL 1 MONTH)
        )
        SELECT 
            c.current_emissions,
            p.previous_emissions,
            c.current_month,
            CASE 
                WHEN c.current_emissions > {MONTHLY_THRESHOLD} THEN 'THRESHOLD_EXCEEDED'
                WHEN p.previous_emissions > 0 AND 
                     (c.current_emissions - p.previous_emissions) / p.previous_emissions > {GROWTH_THRESHOLD} 
                     THEN 'HIGH_GROWTH'
                ELSE 'NORMAL'
            END as alert_type,
            ROUND(
                CASE WHEN p.previous_emissions > 0 
                     THEN (c.current_emissions - p.previous_emissions) / p.previous_emissions * 100 
                     ELSE 0 END, 2
            ) as growth_percentage
        FROM current_month c
        CROSS JOIN previous_month p
        """
        
        results = list(client.query(alert_query).result())
        
        alerts = []
        for row in results:
            if row.alert_type != 'NORMAL':
                alert = {
                    'alert_type': row.alert_type,
                    'current_emissions': float(row.current_emissions),
                    'previous_emissions': float(row.previous_emissions or 0),
                    'growth_percentage': float(row.growth_percentage),
                    'month': row.current_month.isoformat(),
                    'timestamp': datetime.now().isoformat()
                }
                alerts.append(alert)
        
        # Log alerts for monitoring
        if alerts:
            for alert in alerts:
                logging.warning(f"Sustainability Alert: {alert}")
        else:
            logging.info("No sustainability alerts triggered")
        
        return {
            'status': 'success',
            'alerts_count': len(alerts),
            'alerts': alerts,
            'check_time': datetime.now().isoformat()
        }
        
    except Exception as e:
        logging.error(f"Error checking carbon alerts: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500