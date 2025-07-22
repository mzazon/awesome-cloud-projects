import functions_framework
from google.cloud import bigquery
from google.cloud import pubsub_v1
import json
import os
import statistics
from datetime import datetime, timedelta

@functions_framework.cloud_event
def detect_anomalies(cloud_event):
    """Detect cost anomalies and send alerts."""
    
    client = bigquery.Client()
    publisher = pubsub_v1.PublisherClient()
    
    project_id = "${project_id}"
    dataset_name = "${dataset_name}"
    topic_path = publisher.topic_path(project_id, 'cost-optimization-alerts')
    
    try:
        # Query recent cost data for anomaly detection
        query = f"""
        WITH daily_costs AS (
            SELECT 
                project.id as project_id,
                service.description as service_name,
                DATE(usage_start_time) as usage_date,
                SUM(cost) as daily_cost
            FROM `{project_id}.{dataset_name}.gcp_billing_export_v1_*`
            WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
            GROUP BY project_id, service_name, usage_date
        ),
        stats AS (
            SELECT 
                project_id,
                service_name,
                AVG(daily_cost) as avg_cost,
                STDDEV(daily_cost) as std_cost
            FROM daily_costs
            WHERE usage_date < CURRENT_DATE()
            GROUP BY project_id, service_name
        )
        SELECT 
            dc.project_id,
            dc.service_name,
            dc.daily_cost,
            s.avg_cost,
            s.std_cost,
            ABS(dc.daily_cost - s.avg_cost) / s.std_cost as z_score
        FROM daily_costs dc
        JOIN stats s ON dc.project_id = s.project_id AND dc.service_name = s.service_name
        WHERE dc.usage_date = CURRENT_DATE()
        AND ABS(dc.daily_cost - s.avg_cost) / s.std_cost > 2.0
        ORDER BY z_score DESC
        """
        
        results = client.query(query).result()
        
        # Process anomalies and send alerts
        for row in results:
            anomaly = {
                'type': 'cost_anomaly',
                'project_id': row.project_id,
                'service': row.service_name,
                'current_cost': float(row.daily_cost),
                'expected_cost': float(row.avg_cost),
                'z_score': float(row.z_score),
                'severity': 'high' if row.z_score > 3.0 else 'medium',
                'timestamp': datetime.now().isoformat()
            }
            
            # Publish to Pub/Sub
            message = json.dumps(anomaly).encode('utf-8')
            publisher.publish(topic_path, message)
            
            # Store in BigQuery for tracking
            insert_query = f"""
            INSERT INTO `{project_id}.{dataset_name}.cost_anomalies`
            VALUES (
                CURRENT_TIMESTAMP(),
                '{row.project_id}',
                '{row.service_name}',
                {row.avg_cost},
                {row.daily_cost},
                {(row.daily_cost - row.avg_cost) / row.avg_cost * 100},
                'statistical_anomaly'
            )
            """
            client.query(insert_query)
        
        return f"Processed {results.total_rows} potential anomalies"
        
    except Exception as e:
        print(f"Error in anomaly detection: {str(e)}")
        return f"Error: {str(e)}"