import json
import boto3
import os
from data_utils import DataProcessor
from datetime import datetime, timedelta

def lambda_handler(event, context):
    processor = DataProcessor()
    cloudwatch = boto3.client('cloudwatch')
    
    # Parse EventBridge event
    detail = event['detail']
    process_id = detail['processId']
    quality_score = detail.get('qualityScore', 0)
    validation_passed = detail.get('validationPassed', False)
    
    try:
        # Calculate quality metrics over time
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        # Query recent processing metadata
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['METADATA_TABLE'])
        
        # Scan for recent records (in production, use GSI for better performance)
        response = table.scan(
            FilterExpression='ProcessingStage = :stage',
            ExpressionAttributeValues={':stage': 'validation'}
        )
        
        # Calculate aggregate metrics
        total_records = len(response['Items'])
        passed_records = sum(1 for item in response['Items'] 
                           if item.get('ValidationPassed', False))
        avg_quality_score = sum(float(item.get('QualityScore', 0)) 
                              for item in response['Items']) / max(total_records, 1)
        
        # Publish CloudWatch metrics
        cloudwatch.put_metric_data(
            Namespace='DataLake/Quality',
            MetricData=[
                {
                    'MetricName': 'ValidationSuccessRate',
                    'Value': (passed_records / max(total_records, 1)) * 100,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'AverageQualityScore',
                    'Value': avg_quality_score,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'ProcessedRecords',
                    'Value': total_records,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                }
            ]
        )
        
        # Store aggregated quality metadata
        quality_metadata = {
            'TotalRecords': total_records,
            'PassedRecords': passed_records,
            'SuccessRate': (passed_records / max(total_records, 1)) * 100,
            'AverageQualityScore': avg_quality_score,
            'ProcessingStage': 'quality_monitoring'
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=f"quality-{datetime.utcnow().isoformat()}",
            metadata=quality_metadata
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Quality metrics updated',
                'metrics': quality_metadata
            })
        }
        
    except Exception as e:
        print(f"Error monitoring quality: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }