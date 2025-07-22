import json
import boto3
from datetime import datetime
import uuid
import os

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    """
    Initiates Amazon Comprehend custom model training jobs.
    Supports both entity recognition and document classification models.
    """
    bucket = event['bucket']
    model_type = event['model_type']  # 'entity' or 'classification'
    
    try:
        if model_type == 'entity':
            result = train_entity_model(event)
        elif model_type == 'classification':
            result = train_classification_model(event)
        else:
            raise ValueError(f"Invalid model type: {model_type}")
        
        return {
            'statusCode': 200,
            'model_type': model_type,
            'training_job_arn': result['EntityRecognizerArn'] if model_type == 'entity' else result['DocumentClassifierArn'],
            'training_status': 'SUBMITTED'
        }
        
    except Exception as e:
        print(f"Error in model training: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'model_type': model_type
        }

def train_entity_model(event):
    """
    Initiates training for a custom entity recognition model.
    Configures entity types and training data locations.
    """
    try:
        bucket = event['bucket']
        training_data = event['entity_training_ready']['processed_file']
        
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        recognizer_name = f"{event.get('project_name', 'custom')}-entity-{timestamp}"
        
        # Get entity types from preprocessing results
        entity_types = event['entity_training_ready']['entity_types']
        
        # Configure training job
        training_config = {
            'RecognizerName': recognizer_name,
            'DataAccessRoleArn': event['role_arn'],
            'InputDataConfig': {
                'EntityTypes': [
                    {'Type': entity_type} 
                    for entity_type in entity_types
                ],
                'Documents': {
                    'S3Uri': f"s3://{bucket}/training-data/entities_sample.txt"
                },
                'Annotations': {
                    'S3Uri': f"s3://{bucket}/training-data/{training_data}"
                }
            },
            'LanguageCode': os.environ.get('LANGUAGE_CODE', 'en')
        }
        
        # Add optional configuration
        if 'VolumeKmsKeyId' in event:
            training_config['VolumeKmsKeyId'] = event['VolumeKmsKeyId']
        
        if 'VpcConfig' in event:
            training_config['VpcConfig'] = event['VpcConfig']
        
        # Start training job
        print(f"Starting entity recognizer training: {recognizer_name}")
        response = comprehend.create_entity_recognizer(**training_config)
        
        print(f"Entity recognizer training started successfully: {response['EntityRecognizerArn']}")
        return response
        
    except Exception as e:
        print(f"Error training entity model: {str(e)}")
        raise

def train_classification_model(event):
    """
    Initiates training for a custom document classification model.
    Configures training data and model parameters.
    """
    try:
        bucket = event['bucket']
        training_data = event['classification_training_ready']['processed_file']
        
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        classifier_name = f"{event.get('project_name', 'custom')}-classifier-{timestamp}"
        
        # Configure training job
        training_config = {
            'DocumentClassifierName': classifier_name,
            'DataAccessRoleArn': event['role_arn'],
            'InputDataConfig': {
                'S3Uri': f"s3://{bucket}/training-data/{training_data}"
            },
            'LanguageCode': os.environ.get('LANGUAGE_CODE', 'en')
        }
        
        # Add optional configuration
        if 'VolumeKmsKeyId' in event:
            training_config['VolumeKmsKeyId'] = event['VolumeKmsKeyId']
        
        if 'VpcConfig' in event:
            training_config['VpcConfig'] = event['VpcConfig']
        
        # Configure mode (multi-class or multi-label)
        training_config['Mode'] = event.get('classification_mode', 'MULTI_CLASS')
        
        # Start training job
        print(f"Starting document classifier training: {classifier_name}")
        response = comprehend.create_document_classifier(**training_config)
        
        print(f"Document classifier training started successfully: {response['DocumentClassifierArn']}")
        return response
        
    except Exception as e:
        print(f"Error training classification model: {str(e)}")
        raise