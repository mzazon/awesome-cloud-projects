# AWS Data Exchange Auto Update Lambda Function
# This function automatically creates new revisions with updated data

import json
import boto3
import csv
import random
import logging
from datetime import datetime, timedelta
from io import StringIO

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dataexchange = boto3.client('dataexchange')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda handler for automatically updating Data Exchange datasets with new revisions.
    
    Args:
        event: Event data containing dataset_id and bucket_name
        context: Lambda execution context
        
    Returns:
        dict: Response with status code and details
    """
    
    try:
        logger.info(f"Starting automated data update: {json.dumps(event, default=str)}")
        
        # Extract parameters from event
        dataset_id = event.get('dataset_id')
        bucket_name = event.get('bucket_name')
        
        if not dataset_id or not bucket_name:
            raise ValueError("Missing required parameters: dataset_id and bucket_name")
        
        # Generate updated sample data
        current_date = datetime.now().strftime('%Y-%m-%d')
        updated_files = generate_updated_data(bucket_name, current_date)
        
        # Create new revision
        revision_id = create_new_revision(dataset_id, current_date)
        
        # Import updated assets
        import_job_ids = import_updated_assets(dataset_id, revision_id, bucket_name, updated_files)
        
        # Wait for import jobs to complete
        wait_for_import_completion(import_job_ids)
        
        # Finalize the revision
        finalize_revision(dataset_id, revision_id)
        
        # Log success metrics
        log_update_metrics(dataset_id, revision_id, len(updated_files))
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data update completed successfully',
                'dataset_id': dataset_id,
                'revision_id': revision_id,
                'updated_files': len(updated_files),
                'import_jobs': import_job_ids,
                'timestamp': current_date
            })
        }
        
        logger.info(f"Auto update completed successfully: {response}")
        return response
        
    except Exception as e:
        logger.error(f"Error in automated data update: {str(e)}")
        
        # Log failure metrics
        try:
            log_failure_metrics(event.get('dataset_id', 'Unknown'), str(e))
        except:
            pass
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to update data',
                'dataset_id': event.get('dataset_id', 'Unknown')
            })
        }

def generate_updated_data(bucket_name, current_date):
    """
    Generate updated sample data and upload to S3.
    
    Args:
        bucket_name: Name of the S3 bucket
        current_date: Current date string for file naming
        
    Returns:
        list: List of uploaded file keys
    """
    
    updated_files = []
    
    try:
        # Generate updated customer analytics CSV
        csv_data = generate_customer_analytics_data(current_date)
        csv_key = f'analytics-data/customer-analytics-{current_date}.csv'
        
        s3.put_object(
            Bucket=bucket_name,
            Key=csv_key,
            Body=csv_data,
            ContentType='text/csv',
            Metadata={
                'generated-date': current_date,
                'data-type': 'customer-analytics'
            }
        )
        
        updated_files.append(csv_key)
        logger.info(f"Uploaded CSV data to: {csv_key}")
        
        # Generate updated sales summary JSON
        json_data = generate_sales_summary_data(current_date)
        json_key = f'analytics-data/sales-summary-{current_date}.json'
        
        s3.put_object(
            Bucket=bucket_name,
            Key=json_key,
            Body=json_data,
            ContentType='application/json',
            Metadata={
                'generated-date': current_date,
                'data-type': 'sales-summary'
            }
        )
        
        updated_files.append(json_key)
        logger.info(f"Uploaded JSON data to: {json_key}")
        
        # Generate additional data file (weekly trends)
        trends_data = generate_weekly_trends_data(current_date)
        trends_key = f'analytics-data/weekly-trends-{current_date}.json'
        
        s3.put_object(
            Bucket=bucket_name,
            Key=trends_key,
            Body=trends_data,
            ContentType='application/json',
            Metadata={
                'generated-date': current_date,
                'data-type': 'weekly-trends'
            }
        )
        
        updated_files.append(trends_key)
        logger.info(f"Uploaded trends data to: {trends_key}")
        
        return updated_files
        
    except Exception as e:
        logger.error(f"Error generating updated data: {str(e)}")
        raise

def generate_customer_analytics_data(current_date):
    """
    Generate realistic customer analytics CSV data.
    
    Args:
        current_date: Current date string
        
    Returns:
        str: CSV data as string
    """
    
    categories = ['electronics', 'books', 'clothing', 'home', 'sports', 'automotive']
    regions = ['us-east', 'us-west', 'eu-central', 'asia-pacific', 'ca-central']
    
    output = StringIO()
    writer = csv.writer(output)
    
    # Write header
    writer.writerow(['customer_id', 'purchase_date', 'amount', 'category', 'region', 'payment_method'])
    
    # Generate 15-25 random records
    num_records = random.randint(15, 25)
    
    for i in range(1, num_records + 1):
        customer_id = f'C{i:03d}'
        amount = round(random.uniform(25, 500), 2)
        category = random.choice(categories)
        region = random.choice(regions)
        payment_method = random.choice(['credit', 'debit', 'paypal', 'bank_transfer'])
        
        writer.writerow([customer_id, current_date, amount, category, region, payment_method])
    
    return output.getvalue()

def generate_sales_summary_data(current_date):
    """
    Generate sales summary JSON data.
    
    Args:
        current_date: Current date string
        
    Returns:
        str: JSON data as string
    """
    
    # Calculate realistic summary metrics
    transaction_count = random.randint(15, 25)
    total_sales = round(random.uniform(2000, 8000), 2)
    average_order = round(total_sales / transaction_count, 2)
    
    categories = ['electronics', 'books', 'clothing', 'home', 'sports', 'automotive']
    top_category = random.choice(categories)
    
    summary_data = {
        'report_date': current_date,
        'total_sales': total_sales,
        'transaction_count': transaction_count,
        'average_order_value': average_order,
        'top_category': top_category,
        'growth_rate': round(random.uniform(-5.0, 15.0), 2),
        'return_rate': round(random.uniform(2.0, 8.0), 2),
        'customer_satisfaction': round(random.uniform(4.0, 5.0), 1)
    }
    
    return json.dumps(summary_data, indent=2)

def generate_weekly_trends_data(current_date):
    """
    Generate weekly trends JSON data.
    
    Args:
        current_date: Current date string
        
    Returns:
        str: JSON data as string
    """
    
    # Generate trend data for past 7 days
    trends_data = {
        'analysis_date': current_date,
        'period': 'weekly',
        'daily_metrics': []
    }
    
    base_date = datetime.strptime(current_date, '%Y-%m-%d')
    
    for i in range(7):
        trend_date = (base_date - timedelta(days=i)).strftime('%Y-%m-%d')
        daily_sales = round(random.uniform(200, 1200), 2)
        daily_orders = random.randint(5, 25)
        
        trends_data['daily_metrics'].append({
            'date': trend_date,
            'sales': daily_sales,
            'orders': daily_orders,
            'average_order_value': round(daily_sales / daily_orders, 2) if daily_orders > 0 else 0
        })
    
    # Add weekly summary
    total_weekly_sales = sum(day['sales'] for day in trends_data['daily_metrics'])
    total_weekly_orders = sum(day['orders'] for day in trends_data['daily_metrics'])
    
    trends_data['weekly_summary'] = {
        'total_sales': round(total_weekly_sales, 2),
        'total_orders': total_weekly_orders,
        'average_daily_sales': round(total_weekly_sales / 7, 2),
        'peak_day': max(trends_data['daily_metrics'], key=lambda x: x['sales'])['date']
    }
    
    return json.dumps(trends_data, indent=2)

def create_new_revision(dataset_id, current_date):
    """
    Create a new revision in the Data Exchange dataset.
    
    Args:
        dataset_id: ID of the Data Exchange dataset
        current_date: Current date string
        
    Returns:
        str: ID of the created revision
    """
    
    try:
        response = dataexchange.create_revision(
            DataSetId=dataset_id,
            Comment=f'Automated update - {current_date} - Generated by Lambda'
        )
        
        revision_id = response['Id']
        logger.info(f"Created new revision: {revision_id}")
        return revision_id
        
    except Exception as e:
        logger.error(f"Error creating revision: {str(e)}")
        raise

def import_updated_assets(dataset_id, revision_id, bucket_name, file_keys):
    """
    Import updated assets into the Data Exchange revision.
    
    Args:
        dataset_id: ID of the Data Exchange dataset
        revision_id: ID of the revision
        bucket_name: Name of the S3 bucket
        file_keys: List of S3 object keys to import
        
    Returns:
        list: List of import job IDs
    """
    
    import_job_ids = []
    
    try:
        for file_key in file_keys:
            # Create import job for each file
            response = dataexchange.create_job(
                Type='IMPORT_ASSETS_FROM_S3',
                Details={
                    'ImportAssetsFromS3JobDetails': {
                        'DataSetId': dataset_id,
                        'RevisionId': revision_id,
                        'AssetSources': [
                            {
                                'Bucket': bucket_name,
                                'Key': file_key
                            }
                        ]
                    }
                }
            )
            
            job_id = response['Id']
            import_job_ids.append(job_id)
            logger.info(f"Created import job {job_id} for file: {file_key}")
        
        return import_job_ids
        
    except Exception as e:
        logger.error(f"Error importing assets: {str(e)}")
        raise

def wait_for_import_completion(import_job_ids, max_wait_time=300):
    """
    Wait for import jobs to complete.
    
    Args:
        import_job_ids: List of import job IDs
        max_wait_time: Maximum time to wait in seconds
    """
    
    import time
    
    try:
        for job_id in import_job_ids:
            start_time = time.time()
            
            while time.time() - start_time < max_wait_time:
                response = dataexchange.get_job(JobId=job_id)
                state = response['State']
                
                if state == 'COMPLETED':
                    logger.info(f"Import job {job_id} completed successfully")
                    break
                elif state == 'ERROR':
                    error_details = response.get('Errors', [])
                    raise Exception(f"Import job {job_id} failed: {error_details}")
                else:
                    logger.info(f"Import job {job_id} in state: {state}")
                    time.sleep(10)  # Wait 10 seconds before checking again
            else:
                raise Exception(f"Import job {job_id} timed out after {max_wait_time} seconds")
                
    except Exception as e:
        logger.error(f"Error waiting for import completion: {str(e)}")
        raise

def finalize_revision(dataset_id, revision_id):
    """
    Finalize the revision to make it available for sharing.
    
    Args:
        dataset_id: ID of the Data Exchange dataset
        revision_id: ID of the revision to finalize
    """
    
    try:
        dataexchange.update_revision(
            DataSetId=dataset_id,
            RevisionId=revision_id,
            Finalized=True
        )
        
        logger.info(f"Finalized revision: {revision_id}")
        
    except Exception as e:
        logger.error(f"Error finalizing revision: {str(e)}")
        raise

def log_update_metrics(dataset_id, revision_id, file_count):
    """
    Log custom metrics for successful updates.
    
    Args:
        dataset_id: ID of the Data Exchange dataset
        revision_id: ID of the revision
        file_count: Number of files updated
    """
    
    try:
        cloudwatch = boto3.client('cloudwatch')
        
        cloudwatch.put_metric_data(
            Namespace='DataExchange/AutoUpdate',
            MetricData=[
                {
                    'MetricName': 'SuccessfulUpdates',
                    'Dimensions': [
                        {
                            'Name': 'DataSetId',
                            'Value': dataset_id
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'FilesUpdated',
                    'Dimensions': [
                        {
                            'Name': 'DataSetId',
                            'Value': dataset_id
                        }
                    ],
                    'Value': file_count,
                    'Unit': 'Count'
                }
            ]
        )
        
        logger.info(f"Logged success metrics for dataset: {dataset_id}")
        
    except Exception as e:
        logger.warning(f"Failed to log success metrics: {str(e)}")

def log_failure_metrics(dataset_id, error_message):
    """
    Log custom metrics for failed updates.
    
    Args:
        dataset_id: ID of the Data Exchange dataset
        error_message: Error message
    """
    
    try:
        cloudwatch = boto3.client('cloudwatch')
        
        cloudwatch.put_metric_data(
            Namespace='DataExchange/AutoUpdate',
            MetricData=[
                {
                    'MetricName': 'FailedUpdates',
                    'Dimensions': [
                        {
                            'Name': 'DataSetId',
                            'Value': dataset_id
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        logger.info(f"Logged failure metrics for dataset: {dataset_id}")
        
    except Exception as e:
        logger.warning(f"Failed to log failure metrics: {str(e)}")