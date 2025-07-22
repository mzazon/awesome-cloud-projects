import json
import boto3
from datetime import datetime
import uuid
import os

comprehend = boto3.client('comprehend')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Provides real-time inference using trained Amazon Comprehend custom models.
    Supports both entity recognition and document classification.
    """
    try:
        # Parse request
        body = json.loads(event.get('body', '{}'))
        text = body.get('text', '')
        entity_model_arn = body.get('entity_model_arn')
        classifier_model_arn = body.get('classifier_model_arn')
        
        if not text:
            return {
                'statusCode': 400,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'Text is required'})
            }
        
        if len(text.strip()) < 1:
            return {
                'statusCode': 400,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'Text cannot be empty'})
            }
        
        # Validate text length (Comprehend has limits)
        if len(text) > 100000:  # 100KB limit for sync operations
            return {
                'statusCode': 400,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'Text too long. Maximum 100,000 characters allowed.'})
            }
        
        results = {}
        
        # Perform entity recognition if model is provided
        if entity_model_arn:
            try:
                entity_results = comprehend.detect_entities(
                    Text=text,
                    EndpointArn=entity_model_arn
                )
                results['entities'] = process_entity_results(entity_results['Entities'])
            except Exception as e:
                print(f"Entity recognition error: {str(e)}")
                results['entities'] = {'error': str(e)}
        
        # Perform classification if model is provided
        if classifier_model_arn:
            try:
                classification_results = comprehend.classify_document(
                    Text=text,
                    EndpointArn=classifier_model_arn
                )
                results['classification'] = process_classification_results(classification_results['Classes'])
            except Exception as e:
                print(f"Classification error: {str(e)}")
                results['classification'] = {'error': str(e)}
        
        # Store results if table is configured
        if os.environ.get('RESULTS_TABLE'):
            try:
                store_results(text, results, entity_model_arn, classifier_model_arn)
            except Exception as e:
                print(f"Error storing results: {str(e)}")
                # Don't fail the request if storage fails
        
        response_body = {
            'text': text,
            'results': results,
            'timestamp': datetime.now().isoformat(),
            'models_used': {
                'entity_model': entity_model_arn if entity_model_arn else None,
                'classifier_model': classifier_model_arn if classifier_model_arn else None
            }
        }
        
        return {
            'statusCode': 200,
            'headers': get_cors_headers(),
            'body': json.dumps(response_body, default=str)
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Internal server error'})
        }

def process_entity_results(entities):
    """
    Processes and enhances entity recognition results.
    """
    processed_entities = []
    
    for entity in entities:
        processed_entity = {
            'text': entity['Text'],
            'type': entity['Type'],
            'confidence': round(entity['Score'], 4),
            'begin_offset': entity['BeginOffset'],
            'end_offset': entity['EndOffset']
        }
        processed_entities.append(processed_entity)
    
    # Sort by confidence score (highest first)
    processed_entities.sort(key=lambda x: x['confidence'], reverse=True)
    
    # Group by entity type
    entity_summary = {}
    for entity in processed_entities:
        entity_type = entity['type']
        if entity_type not in entity_summary:
            entity_summary[entity_type] = []
        entity_summary[entity_type].append(entity)
    
    return {
        'entities': processed_entities,
        'entity_summary': entity_summary,
        'total_entities': len(processed_entities)
    }

def process_classification_results(classes):
    """
    Processes and enhances classification results.
    """
    processed_classes = []
    
    for cls in classes:
        processed_class = {
            'name': cls['Name'],
            'confidence': round(cls['Score'], 4)
        }
        processed_classes.append(processed_class)
    
    # Sort by confidence score (highest first)
    processed_classes.sort(key=lambda x: x['confidence'], reverse=True)
    
    # Determine the predicted class (highest confidence)
    predicted_class = processed_classes[0] if processed_classes else None
    
    return {
        'classes': processed_classes,
        'predicted_class': predicted_class,
        'total_classes': len(processed_classes)
    }

def store_results(text, results, entity_model_arn, classifier_model_arn):
    """
    Stores inference results in DynamoDB for analytics and auditing.
    """
    table_name = os.environ['RESULTS_TABLE']
    table = dynamodb.Table(table_name)
    
    item = {
        'id': str(uuid.uuid4()),
        'text': text[:1000],  # Truncate text for storage efficiency
        'text_length': len(text),
        'results': json.dumps(results, default=str),
        'entity_model_arn': entity_model_arn or 'N/A',
        'classifier_model_arn': classifier_model_arn or 'N/A',
        'timestamp': int(datetime.now().timestamp()),
        'iso_timestamp': datetime.now().isoformat()
    }
    
    # Add summary statistics
    if 'entities' in results and 'total_entities' in results['entities']:
        item['total_entities'] = results['entities']['total_entities']
    
    if 'classification' in results and 'predicted_class' in results['classification']:
        predicted = results['classification']['predicted_class']
        if predicted:
            item['predicted_class'] = predicted['name']
            item['prediction_confidence'] = predicted['confidence']
    
    table.put_item(Item=item)

def get_cors_headers():
    """
    Returns CORS headers for API responses.
    """
    return {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
    }