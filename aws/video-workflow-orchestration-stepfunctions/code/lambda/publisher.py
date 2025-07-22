"""
Video Publisher Lambda Function
Handles final publishing and notification for the video processing workflow.
"""

import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any, List

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sns_client = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function handler for publishing video content and sending notifications.
    
    Args:
        event: Event data containing jobId, outputs, quality results, and quality status
        context: Lambda runtime context
        
    Returns:
        Dict containing publishing status and notification information
    """
    try:
        # Extract input parameters
        job_id = event.get('jobId')
        outputs = event.get('outputs', [])
        quality_results = event.get('qualityResults', [])
        quality_passed = event.get('qualityPassed', False)
        
        if not job_id:
            raise ValueError("Missing required parameter: jobId")
        
        print(f"Starting publishing process for job {job_id}, quality passed: {quality_passed}")
        
        # Process based on quality control results
        if quality_passed:
            result = handle_successful_processing(job_id, outputs, quality_results)
        else:
            result = handle_failed_quality_control(job_id, outputs, quality_results)
        
        # Send notification
        notification_result = send_workflow_notification(job_id, quality_passed, result, outputs, quality_results)
        result['notification'] = notification_result
        
        print(f"Publishing completed for job {job_id}: {result['status']}")
        
        return {
            'statusCode': 200,
            'jobId': job_id,
            'status': result['status'],
            'message': result['message'],
            'publishedOutputs': result.get('publishedOutputs', []),
            'notification': notification_result
        }
        
    except Exception as e:
        error_message = f"Error in publishing: {str(e)}"
        print(error_message)
        
        # Update job with error status
        try:
            table = dynamodb.Table(os.environ['JOBS_TABLE'])
            update_publishing_error(table, event.get('jobId', 'unknown'), error_message)
        except Exception as db_error:
            print(f"Failed to update job error status: {str(db_error)}")
        
        return {
            'statusCode': 500,
            'jobId': event.get('jobId', 'unknown'),
            'error': error_message,
            'status': 'PUBLISHING_ERROR',
            'message': 'Publishing failed due to error'
        }

def handle_successful_processing(job_id: str, outputs: List[Dict[str, Any]], quality_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Handle successful video processing by publishing content and updating status.
    
    Args:
        job_id: Job identifier
        outputs: List of output files
        quality_results: Quality validation results
        
    Returns:
        Dict containing publishing results
    """
    try:
        print(f"Processing successful completion for job {job_id}")
        
        # Process each output for publishing
        published_outputs = []
        for output in outputs:
            published_output = process_output_for_publishing(output, quality_results)
            published_outputs.append(published_output)
        
        # Calculate publishing metrics
        publishing_summary = calculate_publishing_summary(published_outputs, quality_results)
        
        # Update job status in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        update_successful_completion(table, job_id, published_outputs, publishing_summary)
        
        return {
            'status': 'PUBLISHED',
            'message': f'Video processing completed successfully for job {job_id}',
            'publishedOutputs': published_outputs,
            'publishingSummary': publishing_summary,
            'completedAt': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        error_msg = f"Error handling successful processing: {str(e)}"
        print(error_msg)
        raise

def handle_failed_quality_control(job_id: str, outputs: List[Dict[str, Any]], quality_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Handle failed quality control by updating status and preparing failure information.
    
    Args:
        job_id: Job identifier
        outputs: List of output files
        quality_results: Quality validation results that failed
        
    Returns:
        Dict containing failure handling results
    """
    try:
        print(f"Processing quality control failure for job {job_id}")
        
        # Analyze quality failure reasons
        failure_analysis = analyze_quality_failures(quality_results)
        
        # Update job status in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        update_quality_failure(table, job_id, outputs, quality_results, failure_analysis)
        
        return {
            'status': 'FAILED_QUALITY_CONTROL',
            'message': f'Video processing failed quality control for job {job_id}',
            'failureAnalysis': failure_analysis,
            'qualityResults': quality_results,
            'failedAt': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        error_msg = f"Error handling quality failure: {str(e)}"
        print(error_msg)
        raise

def process_output_for_publishing(output: Dict[str, Any], quality_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Process individual output for publishing, including metadata enrichment.
    
    Args:
        output: Output file information
        quality_results: Quality validation results
        
    Returns:
        Dict containing processed output information
    """
    output_format = output.get('format', 'unknown')
    output_key = output.get('key', '')
    output_bucket = output.get('bucket', '')
    
    # Find quality result for this output
    quality_result = next(
        (qr for qr in quality_results if qr.get('format') == output_format),
        {}
    )
    
    # Generate public access information (if applicable)
    access_info = generate_access_information(output_bucket, output_key, output_format)
    
    # Create publishing metadata
    publishing_metadata = {
        'format': output_format,
        'bucket': output_bucket,
        'key': output_key,
        'qualityScore': quality_result.get('score', 0.0),
        'accessInfo': access_info,
        'publishedAt': datetime.utcnow().isoformat(),
        'status': 'PUBLISHED'
    }
    
    # Add format-specific metadata
    if output_format == 'mp4':
        publishing_metadata['contentType'] = 'video/mp4'
        publishing_metadata['usage'] = 'direct_download'
    elif output_format == 'hls':
        publishing_metadata['contentType'] = 'application/vnd.apple.mpegurl'
        publishing_metadata['usage'] = 'streaming'
    elif output_format == 'thumbnails':
        publishing_metadata['contentType'] = 'image/jpeg'
        publishing_metadata['usage'] = 'preview'
    
    print(f"Processed {output_format} output for publishing: {output_key}")
    return publishing_metadata

def generate_access_information(bucket: str, key: str, format_type: str) -> Dict[str, Any]:
    """
    Generate access information for published content.
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        format_type: Output format type
        
    Returns:
        Dict containing access information
    """
    # Generate S3 URL (private)
    s3_url = f"s3://{bucket}/{key}"
    
    # In a production system, you might generate:
    # - CloudFront URLs for public access
    # - Presigned URLs for temporary access
    # - API Gateway URLs for controlled access
    
    access_info = {
        's3_location': s3_url,
        'private_access': True,
        'requires_authentication': True
    }
    
    # Add format-specific access patterns
    if format_type == 'hls':
        access_info['streaming_protocol'] = 'HLS'
        access_info['player_compatibility'] = ['iOS Safari', 'Android Chrome', 'Desktop Safari']
    elif format_type == 'mp4':
        access_info['download_available'] = True
        access_info['progressive_playback'] = True
    elif format_type == 'thumbnails':
        access_info['preview_available'] = True
        access_info['cache_duration'] = 3600  # 1 hour
    
    return access_info

def calculate_publishing_summary(published_outputs: List[Dict[str, Any]], quality_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Calculate summary statistics for the publishing process.
    
    Args:
        published_outputs: List of published outputs
        quality_results: Quality validation results
        
    Returns:
        Dict containing publishing summary statistics
    """
    # Count outputs by format
    format_counts = {}
    total_quality_score = 0.0
    
    for output in published_outputs:
        format_type = output.get('format', 'unknown')
        format_counts[format_type] = format_counts.get(format_type, 0) + 1
        total_quality_score += output.get('qualityScore', 0.0)
    
    average_quality = total_quality_score / len(published_outputs) if published_outputs else 0.0
    
    # Identify primary output
    primary_output = next(
        (output for output in published_outputs if output.get('format') == 'mp4'),
        published_outputs[0] if published_outputs else None
    )
    
    summary = {
        'total_outputs': len(published_outputs),
        'formats_published': list(format_counts.keys()),
        'format_counts': format_counts,
        'average_quality_score': round(average_quality, 3),
        'primary_output': primary_output,
        'publishing_success': True,
        'summary_generated_at': datetime.utcnow().isoformat()
    }
    
    # Add recommendations
    recommendations = generate_publishing_recommendations(published_outputs, average_quality)
    summary['recommendations'] = recommendations
    
    return summary

def generate_publishing_recommendations(published_outputs: List[Dict[str, Any]], average_quality: float) -> List[str]:
    """
    Generate recommendations based on publishing results.
    
    Args:
        published_outputs: List of published outputs
        average_quality: Average quality score
        
    Returns:
        List of recommendation strings
    """
    recommendations = []
    
    # Quality-based recommendations
    if average_quality < 0.7:
        recommendations.append("Consider reviewing encoding parameters to improve output quality")
    elif average_quality >= 0.9:
        recommendations.append("Excellent quality achieved - current settings are optimal")
    
    # Format-based recommendations
    formats = [output.get('format') for output in published_outputs]
    
    if 'hls' not in formats:
        recommendations.append("Consider adding HLS output for better streaming compatibility")
    
    if 'thumbnails' not in formats:
        recommendations.append("Consider generating thumbnails for preview purposes")
    
    if len(published_outputs) == 1:
        recommendations.append("Consider adding multiple output formats for broader compatibility")
    
    return recommendations

def analyze_quality_failures(quality_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Analyze quality control failures to provide detailed failure information.
    
    Args:
        quality_results: Quality validation results
        
    Returns:
        Dict containing failure analysis
    """
    failed_checks = []
    common_issues = []
    
    for result in quality_results:
        format_type = result.get('format', 'unknown')
        checks = result.get('checks', {})
        score = result.get('score', 0.0)
        
        # Collect failed checks
        for check_name, passed in checks.items():
            if not passed:
                failed_checks.append({
                    'format': format_type,
                    'check': check_name,
                    'description': get_check_description(check_name)
                })
        
        # Identify common issues
        if score < 0.3:
            common_issues.append(f"Very poor quality detected in {format_type} output")
        elif not checks.get('file_exists', True):
            common_issues.append(f"Missing {format_type} output file")
        elif not checks.get('file_size_valid', True):
            common_issues.append(f"Invalid file size for {format_type} output")
    
    # Generate corrective actions
    corrective_actions = generate_corrective_actions(failed_checks, common_issues)
    
    return {
        'failed_checks': failed_checks,
        'common_issues': common_issues,
        'corrective_actions': corrective_actions,
        'total_failed_outputs': len([r for r in quality_results if r.get('score', 0) < 0.8]),
        'analysis_timestamp': datetime.utcnow().isoformat()
    }

def get_check_description(check_name: str) -> str:
    """Get human-readable description for quality check."""
    descriptions = {
        'file_exists': 'Output file was not created',
        'file_size_valid': 'Output file size is outside expected range',
        'format_supported': 'Output format is not supported or correctly formatted',
        'resolution_appropriate': 'Output resolution is not appropriate for the source',
        'duration_consistent': 'Output duration does not match source expectations',
        'no_corruption_detected': 'Potential file corruption detected'
    }
    return descriptions.get(check_name, f'Quality check failed: {check_name}')

def generate_corrective_actions(failed_checks: List[Dict[str, Any]], common_issues: List[str]) -> List[str]:
    """Generate corrective actions based on failure analysis."""
    actions = []
    
    # Check for specific patterns
    check_types = [check['check'] for check in failed_checks]
    
    if 'file_exists' in check_types:
        actions.append("Verify MediaConvert job configuration and output settings")
    
    if 'file_size_valid' in check_types:
        actions.append("Review encoding bitrate and compression settings")
    
    if 'format_supported' in check_types:
        actions.append("Check output format configuration and container settings")
    
    if 'resolution_appropriate' in check_types:
        actions.append("Verify video resolution and scaling parameters")
    
    if len(set(check_types)) > 2:
        actions.append("Consider reviewing entire MediaConvert job template")
    
    # Add general recommendations
    if not actions:
        actions.append("Review workflow logs for additional error information")
    
    actions.append("Monitor subsequent jobs for similar issues")
    
    return actions

def send_workflow_notification(job_id: str, quality_passed: bool, result: Dict[str, Any], outputs: List[Dict[str, Any]], quality_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Send SNS notification about workflow completion.
    
    Args:
        job_id: Job identifier
        quality_passed: Whether quality control passed
        result: Processing result information
        outputs: Output files
        quality_results: Quality validation results
        
    Returns:
        Dict containing notification result
    """
    try:
        # Prepare notification content
        if quality_passed:
            subject = f"Video Processing Success - Job {job_id}"
            message = create_success_notification_message(job_id, result, outputs, quality_results)
        else:
            subject = f"Video Processing Quality Control Failed - Job {job_id}"
            message = create_failure_notification_message(job_id, result, quality_results)
        
        # Send SNS notification
        sns_response = sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject=subject
        )
        
        print(f"Sent SNS notification for job {job_id}: {sns_response['MessageId']}")
        
        return {
            'sent': True,
            'message_id': sns_response['MessageId'],
            'subject': subject,
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        error_msg = f"Error sending notification: {str(e)}"
        print(error_msg)
        return {
            'sent': False,
            'error': error_msg,
            'timestamp': datetime.utcnow().isoformat()
        }

def create_success_notification_message(job_id: str, result: Dict[str, Any], outputs: List[Dict[str, Any]], quality_results: List[Dict[str, Any]]) -> str:
    """Create success notification message."""
    publishing_summary = result.get('publishingSummary', {})
    
    message = f"""
Video Processing Workflow Completed Successfully

Job ID: {job_id}
Status: {result['status']}
Completed At: {result.get('completedAt', 'Unknown')}

Outputs Generated:
"""
    
    for output in outputs:
        format_type = output.get('format', 'unknown')
        location = output.get('key', 'unknown')
        message += f"  - {format_type.upper()}: {location}\n"
    
    message += f"""
Quality Summary:
  - Total Outputs: {publishing_summary.get('total_outputs', 0)}
  - Average Quality Score: {publishing_summary.get('average_quality_score', 0):.3f}
  - Formats: {', '.join(publishing_summary.get('formats_published', []))}

The video processing workflow has completed successfully and all outputs are available for use.
"""
    
    return message

def create_failure_notification_message(job_id: str, result: Dict[str, Any], quality_results: List[Dict[str, Any]]) -> str:
    """Create failure notification message."""
    failure_analysis = result.get('failureAnalysis', {})
    
    message = f"""
Video Processing Workflow Failed Quality Control

Job ID: {job_id}
Status: {result['status']}
Failed At: {result.get('failedAt', 'Unknown')}

Quality Control Issues:
"""
    
    for issue in failure_analysis.get('common_issues', []):
        message += f"  - {issue}\n"
    
    message += "\nRecommended Actions:\n"
    for action in failure_analysis.get('corrective_actions', []):
        message += f"  - {action}\n"
    
    message += "\nPlease review the workflow configuration and retry processing."
    
    return message

def update_successful_completion(table: Any, job_id: str, published_outputs: List[Dict[str, Any]], publishing_summary: Dict[str, Any]) -> None:
    """Update DynamoDB job record with successful completion."""
    try:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET JobStatus = :status, PublishedAt = :timestamp, PublishedOutputs = :outputs, PublishingSummary = :summary',
            ExpressionAttributeValues={
                ':status': 'PUBLISHED',
                ':timestamp': datetime.utcnow().isoformat(),
                ':outputs': published_outputs,
                ':summary': publishing_summary
            }
        )
        print(f"Updated job {job_id} with successful completion in DynamoDB")
        
    except Exception as e:
        print(f"Error updating DynamoDB: {str(e)}")
        raise

def update_quality_failure(table: Any, job_id: str, outputs: List[Dict[str, Any]], quality_results: List[Dict[str, Any]], failure_analysis: Dict[str, Any]) -> None:
    """Update DynamoDB job record with quality control failure."""
    try:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET JobStatus = :status, FailedAt = :timestamp, FailureReason = :reason, FailureAnalysis = :analysis, FailedOutputs = :outputs',
            ExpressionAttributeValues={
                ':status': 'FAILED_QUALITY_CONTROL',
                ':timestamp': datetime.utcnow().isoformat(),
                ':reason': 'Quality control validation failed',
                ':analysis': failure_analysis,
                ':outputs': outputs
            }
        )
        print(f"Updated job {job_id} with quality failure in DynamoDB")
        
    except Exception as e:
        print(f"Error updating DynamoDB: {str(e)}")
        raise

def update_publishing_error(table: Any, job_id: str, error_message: str) -> None:
    """Update DynamoDB job record with publishing error."""
    try:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET JobStatus = :status, PublishingErrorMessage = :error, PublishingErrorTimestamp = :timestamp',
            ExpressionAttributeValues={
                ':status': 'PUBLISHING_ERROR',
                ':error': error_message,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        print(f"Updated job {job_id} with publishing error in DynamoDB")
        
    except Exception as e:
        print(f"Error updating DynamoDB with publishing error: {str(e)}")