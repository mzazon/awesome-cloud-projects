import json
import logging
from google.cloud import billing_v1
from google.cloud import bigquery
from google.cloud import pubsub_v1
from datetime import datetime, timedelta
import os
import base64

def analyze_costs(event, context):
    """Analyze costs across projects and detect anomalies"""
    
    # Configure logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Initialize clients
    billing_client = billing_v1.CloudBillingClient()
    bq_client = bigquery.Client()
    publisher = pubsub_v1.PublisherClient()
    
    # Configuration from template variables and environment
    dataset_id = "${dataset_name}"
    project_id = "${project_id}"
    topic_name = f"projects/{project_id}/topics/recommendations-generated"
    
    try:
        # Parse incoming Pub/Sub message
        if 'data' in event:
            message_data = json.loads(base64.b64decode(event['data']).decode('utf-8'))
            logger.info(f"Processing trigger: {message_data.get('trigger', 'unknown')}")
        else:
            message_data = {"trigger": "direct_call", "type": "manual"}
        
        # Get billing accounts accessible to the service account
        billing_accounts = billing_client.list_billing_accounts()
        
        analysis_results = []
        
        for account in billing_accounts:
            if not account.open:
                continue
                
            account_id = account.name.split('/')[-1]
            logger.info(f"Analyzing billing account: {account_id}")
            
            # Get projects linked to billing account
            try:
                projects = billing_client.list_project_billing_info(
                    name=account.name
                )
                
                for project in projects:
                    if project.billing_enabled:
                        project_id_clean = project.project_id
                        logger.info(f"Analyzing project: {project_id_clean}")
                        
                        # In a real implementation, you would query the Cloud Billing API
                        # For demonstration, we'll create sample cost data
                        # Note: Actual implementation would use billing export data or Billing API
                        
                        # Sample cost analysis (replace with actual billing API calls)
                        sample_services = ["compute", "storage", "networking", "bigquery"]
                        
                        for service in sample_services:
                            # Generate sample cost data (in production, query actual billing data)
                            cost_data = {
                                'project_id': project_id_clean,
                                'billing_account_id': account_id,
                                'service': service,
                                'cost': 100.0 + (hash(service + project_id_clean) % 500),  # Sample cost
                                'currency': 'USD',
                                'usage_date': datetime.now().strftime('%Y-%m-%d'),
                                'optimization_potential': 15.0 + (hash(service) % 50)  # Sample savings
                            }
                            
                            analysis_results.append(cost_data)
                            
                            # Insert into BigQuery
                            table_id = f"{project_id}.{dataset_id}.cost_analysis"
                            table = bq_client.get_table(table_id)
                            
                            rows_to_insert = [cost_data]
                            errors = bq_client.insert_rows_json(table, rows_to_insert)
                            
                            if not errors:
                                logger.info(f"Cost data inserted for project: {project_id_clean}, service: {service}")
                            else:
                                logger.error(f"BigQuery insert errors: {errors}")
                        
                        # Publish to recommendations topic for each project
                        recommendation_message = json.dumps({
                            'project_id': project_id_clean,
                            'billing_account_id': account_id,
                            'cost_data_count': len(sample_services),
                            'trigger': 'cost_analysis_complete',
                            'analysis_timestamp': datetime.now().isoformat()
                        })
                        
                        future = publisher.publish(topic_name, recommendation_message.encode('utf-8'))
                        logger.info(f"Published recommendation trigger for project: {project_id_clean}")
                        
            except Exception as e:
                logger.error(f"Error processing billing account {account_id}: {str(e)}")
                continue
        
        # Summary response
        summary = {
            "status": "success",
            "message": "Cost analysis completed",
            "projects_analyzed": len(set(r['project_id'] for r in analysis_results)),
            "total_cost_records": len(analysis_results),
            "analysis_timestamp": datetime.now().isoformat()
        }
        
        logger.info(f"Cost analysis complete: {summary}")
        return summary
        
    except Exception as e:
        error_msg = f"Cost analysis failed: {str(e)}"
        logger.error(error_msg)
        return {"status": "error", "message": error_msg}

# Entry point for Cloud Functions
def main(event, context):
    return analyze_costs(event, context)