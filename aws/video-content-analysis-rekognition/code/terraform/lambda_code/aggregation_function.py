import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Aggregate and store analysis results from Rekognition jobs
    """
    try:
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb')
        s3 = boto3.client('s3')
        
        table = dynamodb.Table('${analysis_table}')
        
        # Extract job information
        job_id = event['jobId']
        video_id = event['videoId']
        moderation_job_id = event.get('moderationJobId')
        segment_job_id = event.get('segmentJobId')
        
        results = {
            'jobId': job_id,
            'videoId': video_id,
            'processedAt': datetime.now().isoformat(),
            'moderation': {},
            'segments': {},
            'summary': {}
        }
        
        # Get content moderation results
        if moderation_job_id:
            try:
                moderation_response = rekognition.get_content_moderation(
                    JobId=moderation_job_id
                )
                results['moderation'] = {
                    'jobStatus': moderation_response['JobStatus'],
                    'labels': moderation_response.get('ModerationLabels', [])
                }
            except Exception as e:
                print(f"Error getting moderation results: {str(e)}")
                results['moderation'] = {
                    'jobStatus': 'ERROR',
                    'error': str(e)
                }
        
        # Get segment detection results
        if segment_job_id:
            try:
                segment_response = rekognition.get_segment_detection(
                    JobId=segment_job_id
                )
                results['segments'] = {
                    'jobStatus': segment_response['JobStatus'],
                    'technicalCues': segment_response.get('TechnicalCues', []),
                    'shotSegments': segment_response.get('Segments', [])
                }
            except Exception as e:
                print(f"Error getting segment results: {str(e)}")
                results['segments'] = {
                    'jobStatus': 'ERROR',
                    'error': str(e)
                }
        
        # Create summary
        moderation_labels = results['moderation'].get('labels', [])
        segment_count = len(results['segments'].get('shotSegments', []))
        
        results['summary'] = {
            'moderationLabelsCount': len(moderation_labels),
            'segmentCount': segment_count,
            'hasInappropriateContent': len(moderation_labels) > 0,
            'analysisComplete': True
        }
        
        # Store results in S3
        results_key = f"analysis-results/{job_id}/results.json"
        s3.put_object(
            Bucket='${results_bucket}',
            Key=results_key,
            Body=json.dumps(results, indent=2),
            ContentType='application/json'
        )
        
        # Update DynamoDB with final results
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET JobStatus = :status, ResultsS3Key = :s3key, Summary = :summary',
            ExpressionAttributeValues={
                ':status': 'COMPLETED',
                ':s3key': results_key,
                ':summary': results['summary']
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'videoId': video_id,
                'resultsLocation': f"s3://${results_bucket}/{results_key}",
                'summary': results['summary'],
                'status': 'COMPLETED'
            }
        }
        
    except Exception as e:
        print(f"Error aggregating results: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }