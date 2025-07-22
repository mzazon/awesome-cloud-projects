import json
import boto3

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    """
    Checks the training status of Amazon Comprehend custom models.
    Monitors both entity recognition and document classification training jobs.
    """
    model_type = event['model_type']
    job_arn = event['training_job_arn']
    
    try:
        if model_type == 'entity':
            response = comprehend.describe_entity_recognizer(
                EntityRecognizerArn=job_arn
            )
            status = response['EntityRecognizerProperties']['Status']
            model_details = response['EntityRecognizerProperties']
            
        elif model_type == 'classification':
            response = comprehend.describe_document_classifier(
                DocumentClassifierArn=job_arn
            )
            status = response['DocumentClassifierProperties']['Status']
            model_details = response['DocumentClassifierProperties']
        
        else:
            raise ValueError(f"Invalid model type: {model_type}")
        
        # Determine if training is complete
        is_complete = status in ['TRAINED', 'TRAINING_FAILED', 'STOPPED']
        
        # Extract relevant training metrics if available
        training_metrics = {}
        if status == 'TRAINED':
            if model_type == 'entity' and 'RecognizerMetadata' in model_details:
                metadata = model_details['RecognizerMetadata']
                if 'EvaluationMetrics' in metadata:
                    training_metrics = metadata['EvaluationMetrics']
            elif model_type == 'classification' and 'ClassifierMetadata' in model_details:
                metadata = model_details['ClassifierMetadata']
                if 'EvaluationMetrics' in metadata:
                    training_metrics = metadata['EvaluationMetrics']
        
        # Log training progress
        print(f"Model {job_arn} status: {status}")
        if training_metrics:
            print(f"Training metrics: {json.dumps(training_metrics, indent=2)}")
        
        result = {
            'statusCode': 200,
            'model_type': model_type,
            'training_job_arn': job_arn,
            'training_status': status,
            'is_complete': is_complete,
            'model_details': {
                'status': status,
                'training_metrics': training_metrics
            }
        }
        
        # Include additional status information
        if 'SubmitTime' in model_details:
            result['model_details']['submit_time'] = model_details['SubmitTime'].isoformat()
        
        if 'EndTime' in model_details:
            result['model_details']['end_time'] = model_details['EndTime'].isoformat()
        
        if 'TrainingStartTime' in model_details:
            result['model_details']['training_start_time'] = model_details['TrainingStartTime'].isoformat()
        
        if 'TrainingEndTime' in model_details:
            result['model_details']['training_end_time'] = model_details['TrainingEndTime'].isoformat()
        
        # Include error message if training failed
        if status == 'TRAINING_FAILED' and 'Message' in model_details:
            result['model_details']['error_message'] = model_details['Message']
        
        return result
        
    except Exception as e:
        print(f"Error checking model status: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'model_type': model_type,
            'training_job_arn': job_arn
        }