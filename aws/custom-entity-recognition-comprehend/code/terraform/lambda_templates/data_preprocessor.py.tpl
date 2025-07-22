import json
import boto3
import csv
from io import StringIO
import re
import os

s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Preprocesses training data for Amazon Comprehend custom models.
    Validates CSV format, checks minimum example counts, and prepares data for training.
    """
    bucket = event['bucket']
    entity_key = event['entity_training_data']
    classification_key = event['classification_training_data']
    
    try:
        # Process entity training data
        entity_result = process_entity_data(bucket, entity_key)
        
        # Process classification training data
        classification_result = process_classification_data(bucket, classification_key)
        
        return {
            'statusCode': 200,
            'entity_training_ready': entity_result,
            'classification_training_ready': classification_result,
            'bucket': bucket
        }
        
    except Exception as e:
        print(f"Error in data preprocessing: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }

def process_entity_data(bucket, key):
    """
    Processes and validates entity recognition training data.
    Checks CSV format, entity types, and minimum example counts.
    """
    try:
        # Download and validate entity training data
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parse CSV and validate format
        csv_reader = csv.DictReader(StringIO(content))
        rows = list(csv_reader)
        
        # Validate required columns
        required_columns = ['Text', 'File', 'Line', 'BeginOffset', 'EndOffset', 'Type']
        if not all(col in csv_reader.fieldnames for col in required_columns):
            raise ValueError(f"Missing required columns. Expected: {required_columns}")
        
        # Validate entity types and counts
        entity_types = {}
        for row in rows:
            entity_type = row['Type']
            entity_types[entity_type] = entity_types.get(entity_type, 0) + 1
            
            # Validate offset values are numeric
            try:
                int(row['BeginOffset'])
                int(row['EndOffset'])
            except ValueError:
                raise ValueError(f"Invalid offset values in row: {row}")
        
        # Check minimum examples per entity type
        min_examples = 10
        insufficient_types = [et for et, count in entity_types.items() if count < min_examples]
        
        if insufficient_types:
            print(f"Warning: Entity types with fewer than {min_examples} examples: {insufficient_types}")
        
        # Save processed data
        processed_key = key.replace('.csv', '_processed.csv')
        s3.put_object(
            Bucket=bucket,
            Key=processed_key,
            Body=content,
            ContentType='text/csv'
        )
        
        return {
            'processed_file': processed_key,
            'entity_types': list(entity_types.keys()),
            'total_examples': len(rows),
            'entity_counts': entity_types,
            'warnings': insufficient_types if insufficient_types else None
        }
        
    except Exception as e:
        print(f"Error processing entity data: {str(e)}")
        raise

def process_classification_data(bucket, key):
    """
    Processes and validates classification training data.
    Checks CSV format, labels, and minimum example counts.
    """
    try:
        # Download and validate classification training data
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parse CSV and validate format
        csv_reader = csv.DictReader(StringIO(content))
        rows = list(csv_reader)
        
        # Validate required columns
        required_columns = ['Text', 'Label']
        if not all(col in csv_reader.fieldnames for col in required_columns):
            raise ValueError(f"Missing required columns. Expected: {required_columns}")
        
        # Validate labels and counts
        label_counts = {}
        for row in rows:
            label = row['Label']
            text = row['Text']
            
            # Basic text validation
            if len(text.strip()) < 10:
                print(f"Warning: Very short text found: {text[:50]}...")
            
            label_counts[label] = label_counts.get(label, 0) + 1
        
        # Check minimum examples per label
        min_examples = 10
        insufficient_labels = [label for label, count in label_counts.items() if count < min_examples]
        
        if insufficient_labels:
            print(f"Warning: Labels with fewer than {min_examples} examples: {insufficient_labels}")
        
        # Save processed data
        processed_key = key.replace('.csv', '_processed.csv')
        s3.put_object(
            Bucket=bucket,
            Key=processed_key,
            Body=content,
            ContentType='text/csv'
        )
        
        return {
            'processed_file': processed_key,
            'labels': list(label_counts.keys()),
            'total_examples': len(rows),
            'label_counts': label_counts,
            'warnings': insufficient_labels if insufficient_labels else None
        }
        
    except Exception as e:
        print(f"Error processing classification data: {str(e)}")
        raise