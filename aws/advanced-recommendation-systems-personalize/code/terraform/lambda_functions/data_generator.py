import json
import boto3
import csv
import random
import time
import logging
import os
from datetime import datetime, timedelta
from io import StringIO

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """Generate sample datasets for Amazon Personalize training"""
    
    logger.info(f"Starting data generation with event: {json.dumps(event)}")
    
    try:
        # Get configuration from environment variables
        bucket_name = os.environ.get('BUCKET_NAME')
        num_users = int(os.environ.get('NUM_USERS', 500))
        num_items = int(os.environ.get('NUM_ITEMS', 1000))
        num_interactions = int(os.environ.get('NUM_INTERACTIONS', 25000))
        categories = os.environ.get('CATEGORIES', 'electronics,clothing,books,sports,home,beauty').split(',')
        
        if not bucket_name:
            raise ValueError("BUCKET_NAME environment variable is required")
        
        logger.info(f"Configuration - Users: {num_users}, Items: {num_items}, Interactions: {num_interactions}")
        
        # Determine what to generate
        action = event.get('action', 'generate_all_datasets')
        
        results = {}
        
        if action in ['generate_all_datasets', 'generate_interactions']:
            interactions_result = generate_interactions_dataset(
                bucket_name, num_users, num_items, num_interactions
            )
            results['interactions'] = interactions_result
        
        if action in ['generate_all_datasets', 'generate_items']:
            items_result = generate_items_dataset(
                bucket_name, num_items, categories
            )
            results['items'] = items_result
        
        if action in ['generate_all_datasets', 'generate_users']:
            users_result = generate_users_dataset(
                bucket_name, num_users
            )
            results['users'] = users_result
        
        if action == 'generate_batch_input':
            batch_input_result = generate_batch_input_sample(
                bucket_name, min(num_users, 100)  # Limit to 100 users for batch sample
            )
            results['batch_input'] = batch_input_result
        
        logger.info("Data generation completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data generation completed successfully',
                'action': action,
                'results': results,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        error_message = str(e)
        logger.error(f"Error in data generation: {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Data generation failed',
                'message': error_message,
                'timestamp': datetime.now().isoformat()
            })
        }

def generate_interactions_dataset(bucket_name, num_users, num_items, num_interactions):
    """Generate user-item interactions dataset"""
    
    logger.info(f"Generating {num_interactions} interactions for {num_users} users and {num_items} items")
    
    # Generate user and item lists
    users = [f"user_{i:04d}" for i in range(1, num_users + 1)]
    items = [f"item_{i:04d}" for i in range(1, num_items + 1)]
    
    # Generate interactions
    interactions = []
    base_timestamp = int((datetime.now() - timedelta(days=90)).timestamp())
    
    # Create some popular items for realistic distribution
    popular_items = random.sample(items, min(100, len(items)))
    
    for _ in range(num_interactions):
        user = random.choice(users)
        
        # 30% chance to select from popular items, 70% from all items
        if random.random() < 0.3:
            item = random.choice(popular_items)
        else:
            item = random.choice(items)
        
        # Event type distribution: view (60%), purchase (10%), add_to_cart (20%), like (10%)
        event_type = random.choices(
            ["view", "purchase", "add_to_cart", "like"], 
            weights=[60, 10, 20, 10]
        )[0]
        
        # Generate timestamp within last 90 days
        timestamp = base_timestamp + random.randint(0, 90 * 24 * 3600)
        
        # Event value based on type
        event_value_map = {
            "view": 1,
            "purchase": 5,
            "add_to_cart": 2,
            "like": 3
        }
        event_value = event_value_map[event_type]
        
        interactions.append({
            "USER_ID": user,
            "ITEM_ID": item,
            "TIMESTAMP": timestamp,
            "EVENT_TYPE": event_type,
            "EVENT_VALUE": event_value
        })
    
    # Convert to CSV and upload to S3
    csv_content = convert_to_csv(interactions, ["USER_ID", "ITEM_ID", "TIMESTAMP", "EVENT_TYPE", "EVENT_VALUE"])
    
    s3_key = "training-data/interactions.csv"
    s3_client.put_object(
        Bucket=bucket_name,
        Key=s3_key,
        Body=csv_content,
        ContentType='text/csv'
    )
    
    logger.info(f"Uploaded interactions dataset to s3://{bucket_name}/{s3_key}")
    
    return {
        'file': s3_key,
        'records': len(interactions),
        'unique_users': len(set(interaction['USER_ID'] for interaction in interactions)),
        'unique_items': len(set(interaction['ITEM_ID'] for interaction in interactions))
    }

def generate_items_dataset(bucket_name, num_items, categories):
    """Generate items metadata dataset"""
    
    logger.info(f"Generating metadata for {num_items} items")
    
    items_metadata = []
    base_timestamp = int((datetime.now() - timedelta(days=365)).timestamp())
    
    brands = [f"Brand_{i}" for i in range(1, 51)]  # 50 different brands
    
    for i in range(1, num_items + 1):
        item_id = f"item_{i:04d}"
        
        items_metadata.append({
            "ITEM_ID": item_id,
            "CATEGORY": random.choice(categories),
            "PRICE": round(random.uniform(10, 500), 2),
            "BRAND": random.choice(brands),
            "CREATION_TIMESTAMP": base_timestamp + random.randint(0, 365 * 24 * 3600)
        })
    
    # Convert to CSV and upload to S3
    csv_content = convert_to_csv(items_metadata, ["ITEM_ID", "CATEGORY", "PRICE", "BRAND", "CREATION_TIMESTAMP"])
    
    s3_key = "metadata/items.csv"
    s3_client.put_object(
        Bucket=bucket_name,
        Key=s3_key,
        Body=csv_content,
        ContentType='text/csv'
    )
    
    logger.info(f"Uploaded items dataset to s3://{bucket_name}/{s3_key}")
    
    return {
        'file': s3_key,
        'records': len(items_metadata),
        'categories': list(set(item['CATEGORY'] for item in items_metadata)),
        'price_range': {
            'min': min(item['PRICE'] for item in items_metadata),
            'max': max(item['PRICE'] for item in items_metadata)
        }
    }

def generate_users_dataset(bucket_name, num_users):
    """Generate users metadata dataset"""
    
    logger.info(f"Generating metadata for {num_users} users")
    
    users_metadata = []
    
    for i in range(1, num_users + 1):
        user_id = f"user_{i:04d}"
        
        users_metadata.append({
            "USER_ID": user_id,
            "AGE": random.randint(18, 65),
            "GENDER": random.choice(["M", "F"]),
            "MEMBERSHIP_TYPE": random.choice(["free", "premium", "enterprise"])
        })
    
    # Convert to CSV and upload to S3
    csv_content = convert_to_csv(users_metadata, ["USER_ID", "AGE", "GENDER", "MEMBERSHIP_TYPE"])
    
    s3_key = "metadata/users.csv"
    s3_client.put_object(
        Bucket=bucket_name,
        Key=s3_key,
        Body=csv_content,
        ContentType='text/csv'
    )
    
    logger.info(f"Uploaded users dataset to s3://{bucket_name}/{s3_key}")
    
    return {
        'file': s3_key,
        'records': len(users_metadata),
        'age_range': {
            'min': min(user['AGE'] for user in users_metadata),
            'max': max(user['AGE'] for user in users_metadata)
        },
        'membership_distribution': {
            membership: len([u for u in users_metadata if u['MEMBERSHIP_TYPE'] == membership])
            for membership in ["free", "premium", "enterprise"]
        }
    }

def generate_batch_input_sample(bucket_name, num_users_sample):
    """Generate sample batch input for batch inference jobs"""
    
    logger.info(f"Generating batch input sample for {num_users_sample} users")
    
    batch_input_lines = []
    for i in range(1, num_users_sample + 1):
        user_id = f"user_{i:04d}"
        batch_input_lines.append(json.dumps({"userId": user_id}))
    
    batch_content = '\n'.join(batch_input_lines)
    
    s3_key = "batch-input/users-batch.json"
    s3_client.put_object(
        Bucket=bucket_name,
        Key=s3_key,
        Body=batch_content,
        ContentType='application/json'
    )
    
    logger.info(f"Uploaded batch input sample to s3://{bucket_name}/{s3_key}")
    
    return {
        'file': s3_key,
        'records': num_users_sample
    }

def convert_to_csv(data, fieldnames):
    """Convert list of dictionaries to CSV string"""
    
    output = StringIO()
    writer = csv.DictWriter(output, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(data)
    
    return output.getvalue()

def validate_data_quality(interactions, items, users):
    """Validate generated data meets Personalize requirements"""
    
    # Check minimum requirements
    unique_users = len(set(interaction['USER_ID'] for interaction in interactions))
    unique_items = len(set(interaction['ITEM_ID'] for interaction in interactions))
    total_interactions = len(interactions)
    
    validation_results = {
        'meets_requirements': True,
        'issues': []
    }
    
    if unique_users < 25:
        validation_results['meets_requirements'] = False
        validation_results['issues'].append(f"Not enough unique users: {unique_users} (minimum: 25)")
    
    if unique_items < 100:
        validation_results['meets_requirements'] = False
        validation_results['issues'].append(f"Not enough unique items: {unique_items} (minimum: 100)")
    
    if total_interactions < 1000:
        validation_results['meets_requirements'] = False
        validation_results['issues'].append(f"Not enough interactions: {total_interactions} (minimum: 1000)")
    
    validation_results['statistics'] = {
        'unique_users': unique_users,
        'unique_items': unique_items,
        'total_interactions': total_interactions,
        'items_count': len(items),
        'users_count': len(users)
    }
    
    return validation_results