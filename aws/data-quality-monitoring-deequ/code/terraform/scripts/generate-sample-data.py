#!/usr/bin/env python3
"""
Sample Data Generator for Deequ Data Quality Monitoring
Generates customer data with intentional quality issues for testing
"""

import pandas as pd
import numpy as np
import random
import boto3
import argparse
from datetime import datetime, timedelta

def generate_sample_data(num_records=10000, quality_issues=True):
    """
    Generate sample customer data with optional quality issues
    
    Args:
        num_records (int): Number of records to generate
        quality_issues (bool): Whether to introduce quality issues
        
    Returns:
        pandas.DataFrame: Generated sample data
    """
    print(f"🔄 Generating {num_records} sample customer records...")
    
    # Set random seed for reproducibility
    np.random.seed(42)
    random.seed(42)
    
    # Generate base dataset
    data = {
        'customer_id': list(range(1, num_records + 1)),
        'email': [f'user{i}@example.com' for i in range(1, num_records + 1)],
        'age': np.random.randint(18, 80, num_records).tolist(),
        'income': np.random.normal(50000, 20000, num_records).tolist(),
        'region': np.random.choice(['US', 'EU', 'APAC'], num_records).tolist(),
        'signup_date': [(datetime.now() - timedelta(days=random.randint(1, 365))).strftime('%Y-%m-%d') 
                       for _ in range(num_records)]
    }
    
    if quality_issues:
        print("⚠️  Introducing intentional quality issues for testing...")
        
        # 1. Missing values in income (5% of records)
        missing_indices = np.random.choice(num_records, size=int(num_records * 0.05), replace=False)
        for idx in missing_indices:
            data['income'][idx] = None
        print(f"   - Added {len(missing_indices)} missing income values")
        
        # 2. Invalid email formats (2% of records)
        invalid_email_indices = np.random.choice(num_records, size=int(num_records * 0.02), replace=False)
        for idx in invalid_email_indices:
            data['email'][idx] = f'invalid-email-{idx}'
        print(f"   - Added {len(invalid_email_indices)} invalid email formats")
        
        # 3. Negative ages (1% of records)
        negative_age_indices = np.random.choice(num_records, size=int(num_records * 0.01), replace=False)
        for idx in negative_age_indices:
            data['age'][idx] = -abs(data['age'][idx])
        print(f"   - Added {len(negative_age_indices)} negative age values")
        
        # 4. Duplicate customer IDs (3% of records)
        duplicate_indices = np.random.choice(num_records, size=int(num_records * 0.03), replace=False)
        for idx in duplicate_indices:
            if idx > 0:  # Avoid index out of bounds
                data['customer_id'][idx] = data['customer_id'][idx - 1]
        print(f"   - Added {len(duplicate_indices)} duplicate customer IDs")
        
        # 5. Invalid regions (1% of records)
        invalid_region_indices = np.random.choice(num_records, size=int(num_records * 0.01), replace=False)
        for idx in invalid_region_indices:
            data['region'][idx] = 'INVALID'
        print(f"   - Added {len(invalid_region_indices)} invalid region values")
        
        # 6. Extreme income values (outliers)
        extreme_income_indices = np.random.choice(num_records, size=int(num_records * 0.005), replace=False)
        for idx in extreme_income_indices:
            data['income'][idx] = random.choice([1000000, -50000])  # Very high or negative income
        print(f"   - Added {len(extreme_income_indices)} extreme income outliers")
    
    # Convert to DataFrame
    df = pd.DataFrame(data)
    
    print(f"✅ Generated dataset with {len(df)} records and {len(df.columns)} columns")
    
    return df

def generate_high_quality_data(num_records=10000):
    """
    Generate high-quality data without any issues for comparison
    
    Args:
        num_records (int): Number of records to generate
        
    Returns:
        pandas.DataFrame: High-quality sample data
    """
    print(f"✨ Generating {num_records} high-quality customer records...")
    
    np.random.seed(42)
    random.seed(42)
    
    data = {
        'customer_id': list(range(1, num_records + 1)),
        'email': [f'customer{i}@company.com' for i in range(1, num_records + 1)],
        'age': np.random.randint(18, 80, num_records).tolist(),
        'income': np.random.normal(55000, 15000, num_records).round(2).tolist(),
        'region': np.random.choice(['US', 'EU', 'APAC'], num_records).tolist(),
        'signup_date': [(datetime.now() - timedelta(days=random.randint(1, 365))).strftime('%Y-%m-%d') 
                       for _ in range(num_records)]
    }
    
    # Ensure all income values are positive
    data['income'] = [max(20000, income) for income in data['income']]
    
    df = pd.DataFrame(data)
    print(f"✅ Generated high-quality dataset with {len(df)} records")
    
    return df

def generate_severely_corrupted_data(num_records=1000):
    """
    Generate severely corrupted data to test alert system
    
    Args:
        num_records (int): Number of records to generate
        
    Returns:
        pandas.DataFrame: Severely corrupted sample data
    """
    print(f"💥 Generating {num_records} severely corrupted records for testing...")
    
    data = {
        'customer_id': [1] * num_records,  # All duplicate IDs
        'email': ['invalid-email'] * num_records,  # All invalid emails
        'age': [-25] * num_records,  # All negative ages
        'income': [None] * num_records,  # All missing income
        'region': ['INVALID'] * num_records,  # All invalid regions
        'signup_date': ['invalid-date'] * num_records  # Invalid dates
    }
    
    df = pd.DataFrame(data)
    print(f"💥 Generated severely corrupted dataset for alert testing")
    
    return df

def upload_to_s3(df, s3_bucket, s3_key):
    """
    Upload DataFrame to S3 as CSV
    
    Args:
        df (pandas.DataFrame): DataFrame to upload
        s3_bucket (str): S3 bucket name
        s3_key (str): S3 object key
    """
    try:
        print(f"☁️  Uploading data to s3://{s3_bucket}/{s3_key}")
        
        # Save to local file first
        local_file = '/tmp/sample_data.csv'
        df.to_csv(local_file, index=False)
        
        # Upload to S3
        s3_client = boto3.client('s3')
        s3_client.upload_file(local_file, s3_bucket, s3_key)
        
        print(f"✅ Successfully uploaded {len(df)} records to S3")
        
    except Exception as e:
        print(f"❌ Error uploading to S3: {str(e)}")
        raise

def main():
    """Main execution function"""
    parser = argparse.ArgumentParser(description='Generate sample data for Deequ quality monitoring')
    parser.add_argument('--records', type=int, default=10000, help='Number of records to generate')
    parser.add_argument('--output', type=str, default='sample_customer_data.csv', help='Output file name')
    parser.add_argument('--s3-bucket', type=str, help='S3 bucket to upload data')
    parser.add_argument('--s3-key', type=str, help='S3 key for uploaded data')
    parser.add_argument('--data-type', type=str, choices=['normal', 'high-quality', 'corrupted'], 
                       default='normal', help='Type of data to generate')
    parser.add_argument('--no-issues', action='store_true', help='Generate data without quality issues')
    
    args = parser.parse_args()
    
    print("🔧 Sample Data Generator for Deequ Quality Monitoring")
    print("=" * 60)
    
    # Generate data based on type
    if args.data_type == 'high-quality' or args.no_issues:
        df = generate_high_quality_data(args.records)
    elif args.data_type == 'corrupted':
        df = generate_severely_corrupted_data(args.records)
    else:
        df = generate_sample_data(args.records, quality_issues=not args.no_issues)
    
    # Save locally
    print(f"💾 Saving data to {args.output}")
    df.to_csv(args.output, index=False)
    
    # Display sample data
    print("\n📄 Sample of generated data:")
    print(df.head(10).to_string())
    
    # Display data quality summary
    print(f"\n📊 Data Quality Summary:")
    print(f"   - Total records: {len(df)}")
    print(f"   - Missing values: {df.isnull().sum().sum()}")
    print(f"   - Duplicate customer IDs: {df['customer_id'].duplicated().sum()}")
    print(f"   - Invalid emails: {sum(1 for email in df['email'] if '@' not in str(email))}")
    print(f"   - Negative ages: {sum(1 for age in df['age'] if age < 0)}")
    
    # Upload to S3 if specified
    if args.s3_bucket and args.s3_key:
        upload_to_s3(df, args.s3_bucket, args.s3_key)
    
    print("\n✅ Sample data generation completed successfully! 🎉")

if __name__ == "__main__":
    main()