import json
import os
import logging
import time
import requests
from google.cloud import storage
import functions_framework

@functions_framework.http
def orchestrate_video_generation(request):
    """Orchestrate batch video generation from creative briefs"""
    try:
        # Get environment variables
        input_bucket = os.environ.get('INPUT_BUCKET')
        output_bucket = os.environ.get('OUTPUT_BUCKET')
        video_function_url = os.environ.get('VIDEO_FUNCTION_URL')
        
        if not all([input_bucket, output_bucket, video_function_url]):
            return {'error': 'Missing required environment variables'}, 500
        
        # List creative brief files
        storage_client = storage.Client()
        bucket = storage_client.bucket(input_bucket)
        
        briefs = []
        for blob in bucket.list_blobs(prefix='briefs/'):
            if blob.name.endswith('.json'):
                briefs.append(blob.name)
        
        logging.info(f"Found {len(briefs)} creative briefs to process")
        
        # Process each brief
        results = []
        for brief_file in briefs:
            try:
                # Download and parse brief
                blob = bucket.blob(brief_file)
                brief_content = json.loads(blob.download_as_text())
                
                # Prepare generation request
                generation_request = {
                    'prompt': brief_content.get('video_prompt'),
                    'output_bucket': output_bucket,
                    'resolution': brief_content.get('resolution', '1080p'),
                    'brief_id': brief_content.get('id', brief_file)
                }
                
                # Call video generation function
                response = requests.post(
                    video_function_url,
                    json=generation_request,
                    headers={'Content-Type': 'application/json'},
                    timeout=600  # Increase timeout for video generation
                )
                
                if response.status_code == 200:
                    result = response.json()
                    results.append({
                        'brief': brief_file,
                        'status': 'success',
                        'video_id': result.get('video_id'),
                        'filename': result.get('filename'),
                        'video_uri': result.get('video_uri')
                    })
                    logging.info(f"Successfully processed brief: {brief_file}")
                else:
                    logging.error(f"Failed to process brief {brief_file}: {response.text}")
                    results.append({
                        'brief': brief_file,
                        'status': 'failed',
                        'error': response.text
                    })
                
                # Add delay between requests to avoid rate limits
                time.sleep(5)
                
            except Exception as e:
                logging.error(f"Error processing brief {brief_file}: {str(e)}")
                results.append({
                    'brief': brief_file,
                    'status': 'error',
                    'error': str(e)
                })
        
        # Generate summary report
        successful = len([r for r in results if r['status'] == 'success'])
        failed = len(results) - successful
        
        summary = {
            'total_briefs': len(briefs),
            'successful_generations': successful,
            'failed_generations': failed,
            'results': results,
            'processed_at': time.time()
        }
        
        # Save batch processing report
        output_bucket_obj = storage_client.bucket(output_bucket)
        report_blob = output_bucket_obj.blob(f"reports/batch_report_{int(time.time())}.json")
        report_blob.upload_from_string(
            json.dumps(summary, indent=2),
            content_type='application/json'
        )
        
        logging.info(f"Batch processing completed: {successful}/{len(briefs)} successful")
        
        return summary
        
    except Exception as e:
        logging.error(f"Error in orchestration: {str(e)}")
        return {'error': str(e)}, 500