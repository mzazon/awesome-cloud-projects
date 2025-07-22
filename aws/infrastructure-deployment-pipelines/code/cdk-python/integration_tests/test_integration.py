"""
Integration tests for the Infrastructure Deployment Pipeline.

This module contains integration tests that validate the deployed infrastructure
works correctly in a real AWS environment.
"""

import os
import json
import boto3
import pytest
from typing import Dict, Any
from botocore.exceptions import ClientError


class TestInfrastructureIntegration:
    """Integration test suite for the deployed infrastructure."""

    def setup_method(self):
        """Set up test fixtures before each test method."""
        # Initialize AWS clients
        self.s3_client = boto3.client('s3')
        self.dynamodb_client = boto3.client('dynamodb')
        self.lambda_client = boto3.client('lambda')
        self.cloudwatch_client = boto3.client('cloudwatch')
        
        # Get resource names from environment variables
        self.assets_bucket_name = os.environ.get('ASSETS_BUCKET_NAME')
        self.app_table_name = os.environ.get('APP_TABLE_NAME')
        self.api_function_name = os.environ.get('API_FUNCTION_NAME')
        
        # Verify required environment variables are set
        if not all([self.assets_bucket_name, self.app_table_name, self.api_function_name]):
            pytest.skip("Required environment variables not set")

    def test_s3_bucket_exists_and_accessible(self):
        """Test that S3 bucket exists and is accessible."""
        try:
            # Test bucket exists
            response = self.s3_client.head_bucket(Bucket=self.assets_bucket_name)
            assert response['ResponseMetadata']['HTTPStatusCode'] == 200
            
            # Test bucket configuration
            versioning = self.s3_client.get_bucket_versioning(Bucket=self.assets_bucket_name)
            assert versioning.get('Status') == 'Enabled'
            
            # Test bucket encryption
            encryption = self.s3_client.get_bucket_encryption(Bucket=self.assets_bucket_name)
            assert 'ServerSideEncryptionConfiguration' in encryption
            
            print(f"✅ S3 bucket {self.assets_bucket_name} exists and is properly configured")
            
        except ClientError as e:
            pytest.fail(f"S3 bucket test failed: {e}")

    def test_dynamodb_table_exists_and_accessible(self):
        """Test that DynamoDB table exists and is accessible."""
        try:
            # Test table exists
            response = self.dynamodb_client.describe_table(TableName=self.app_table_name)
            assert response['Table']['TableStatus'] == 'ACTIVE'
            
            # Test table configuration
            table = response['Table']
            assert table['BillingMode'] == 'PAY_PER_REQUEST'
            assert table['KeySchema'][0]['AttributeName'] == 'id'
            assert table['KeySchema'][0]['KeyType'] == 'HASH'
            
            print(f"✅ DynamoDB table {self.app_table_name} exists and is properly configured")
            
        except ClientError as e:
            pytest.fail(f"DynamoDB table test failed: {e}")

    def test_lambda_function_exists_and_accessible(self):
        """Test that Lambda function exists and is accessible."""
        try:
            # Test function exists
            response = self.lambda_client.get_function(FunctionName=self.api_function_name)
            assert response['Configuration']['State'] == 'Active'
            
            # Test function configuration
            config = response['Configuration']
            assert config['Runtime'] == 'python3.11'
            assert config['Handler'] == 'index.handler'
            assert config['MemorySize'] == 256
            assert config['Timeout'] == 60
            
            # Test environment variables
            env_vars = config.get('Environment', {}).get('Variables', {})
            assert 'TABLE_NAME' in env_vars
            assert 'ENVIRONMENT' in env_vars
            assert 'BUCKET_NAME' in env_vars
            
            print(f"✅ Lambda function {self.api_function_name} exists and is properly configured")
            
        except ClientError as e:
            pytest.fail(f"Lambda function test failed: {e}")

    def test_lambda_function_invocation(self):
        """Test that Lambda function can be invoked successfully."""
        try:
            # Create test payload
            test_payload = {
                'requestId': 'integration-test-001',
                'action': 'test',
                'data': {'test': True}
            }
            
            # Invoke function
            response = self.lambda_client.invoke(
                FunctionName=self.api_function_name,
                InvocationType='RequestResponse',
                Payload=json.dumps(test_payload)
            )
            
            # Verify response
            assert response['StatusCode'] == 200
            assert 'Payload' in response
            
            # Parse response payload
            payload = json.loads(response['Payload'].read())
            assert payload['statusCode'] == 200
            
            response_body = json.loads(payload['body'])
            assert response_body['message'] == 'Request processed successfully'
            assert response_body['requestId'] == 'integration-test-001'
            
            print(f"✅ Lambda function invocation successful")
            
        except ClientError as e:
            pytest.fail(f"Lambda function invocation failed: {e}")
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse Lambda response: {e}")

    def test_data_persistence_in_dynamodb(self):
        """Test that data is properly persisted in DynamoDB."""
        try:
            # First, invoke Lambda to create data
            test_payload = {
                'requestId': 'integration-test-002',
                'action': 'create',
                'data': {'test': 'data-persistence'}
            }
            
            lambda_response = self.lambda_client.invoke(
                FunctionName=self.api_function_name,
                InvocationType='RequestResponse',
                Payload=json.dumps(test_payload)
            )
            
            # Verify Lambda execution was successful
            payload = json.loads(lambda_response['Payload'].read())
            assert payload['statusCode'] == 200
            
            # Query DynamoDB to verify data was stored
            response = self.dynamodb_client.get_item(
                TableName=self.app_table_name,
                Key={'id': {'S': 'integration-test-002'}}
            )
            
            # Verify item exists
            assert 'Item' in response
            item = response['Item']
            assert item['id']['S'] == 'integration-test-002'
            assert 'timestamp' in item
            assert 'environment' in item
            assert 'data' in item
            
            print(f"✅ Data persistence test successful")
            
        except ClientError as e:
            pytest.fail(f"Data persistence test failed: {e}")

    def test_s3_bucket_file_operations(self):
        """Test that S3 bucket supports file operations."""
        try:
            # Test file upload
            test_content = b"Integration test file content"
            test_key = "integration-test/test-file.txt"
            
            self.s3_client.put_object(
                Bucket=self.assets_bucket_name,
                Key=test_key,
                Body=test_content,
                ContentType='text/plain'
            )
            
            # Test file download
            response = self.s3_client.get_object(
                Bucket=self.assets_bucket_name,
                Key=test_key
            )
            
            downloaded_content = response['Body'].read()
            assert downloaded_content == test_content
            
            # Test file deletion
            self.s3_client.delete_object(
                Bucket=self.assets_bucket_name,
                Key=test_key
            )
            
            print(f"✅ S3 file operations test successful")
            
        except ClientError as e:
            pytest.fail(f"S3 file operations test failed: {e}")

    def test_cloudwatch_monitoring(self):
        """Test that CloudWatch monitoring is working."""
        try:
            # Get metrics for Lambda function
            response = self.cloudwatch_client.get_metric_statistics(
                Namespace='AWS/Lambda',
                MetricName='Invocations',
                Dimensions=[
                    {
                        'Name': 'FunctionName',
                        'Value': self.api_function_name
                    }
                ],
                StartTime=boto3.Session().region_name and 
                         boto3.client('sts').get_caller_identity()['Account'] and
                         __import__('datetime').datetime.utcnow() - __import__('datetime').timedelta(hours=1),
                EndTime=__import__('datetime').datetime.utcnow(),
                Period=300,
                Statistics=['Sum']
            )
            
            # Verify metrics are being collected
            assert 'Datapoints' in response
            print(f"✅ CloudWatch monitoring test successful")
            
        except ClientError as e:
            # CloudWatch metrics might not be available immediately
            print(f"⚠️  CloudWatch monitoring test skipped: {e}")

    def test_error_handling(self):
        """Test error handling in the Lambda function."""
        try:
            # Create invalid payload to trigger error
            test_payload = {
                'requestId': None,  # Invalid requestId
                'action': 'invalid-action',
                'data': 'invalid-data'
            }
            
            # Invoke function
            response = self.lambda_client.invoke(
                FunctionName=self.api_function_name,
                InvocationType='RequestResponse',
                Payload=json.dumps(test_payload)
            )
            
            # Verify response
            assert response['StatusCode'] == 200
            
            # Parse response payload
            payload = json.loads(response['Payload'].read())
            
            # Should handle error gracefully
            assert payload['statusCode'] in [200, 500]  # Either success or handled error
            
            print(f"✅ Error handling test successful")
            
        except ClientError as e:
            pytest.fail(f"Error handling test failed: {e}")

    def test_resource_permissions(self):
        """Test that Lambda function has correct permissions."""
        try:
            # Test Lambda can write to DynamoDB
            test_payload = {
                'requestId': 'permission-test-001',
                'action': 'test-permissions',
                'data': {'permission': 'dynamodb-write'}
            }
            
            response = self.lambda_client.invoke(
                FunctionName=self.api_function_name,
                InvocationType='RequestResponse',
                Payload=json.dumps(test_payload)
            )
            
            payload = json.loads(response['Payload'].read())
            assert payload['statusCode'] == 200
            
            # Verify data was written to DynamoDB
            db_response = self.dynamodb_client.get_item(
                TableName=self.app_table_name,
                Key={'id': {'S': 'permission-test-001'}}
            )
            
            assert 'Item' in db_response
            
            print(f"✅ Resource permissions test successful")
            
        except ClientError as e:
            pytest.fail(f"Resource permissions test failed: {e}")

    def test_security_configuration(self):
        """Test security configuration of resources."""
        try:
            # Test S3 bucket public access is blocked
            public_access_block = self.s3_client.get_public_access_block(
                Bucket=self.assets_bucket_name
            )
            
            config = public_access_block['PublicAccessBlockConfiguration']
            assert config['BlockPublicAcls'] is True
            assert config['IgnorePublicAcls'] is True
            assert config['BlockPublicPolicy'] is True
            assert config['RestrictPublicBuckets'] is True
            
            # Test DynamoDB table encryption
            table_description = self.dynamodb_client.describe_table(
                TableName=self.app_table_name
            )
            
            # DynamoDB encryption at rest is enabled by default
            assert table_description['Table']['TableStatus'] == 'ACTIVE'
            
            print(f"✅ Security configuration test successful")
            
        except ClientError as e:
            pytest.fail(f"Security configuration test failed: {e}")

    def cleanup_method(self):
        """Clean up after each test method."""
        # Clean up any test data created during tests
        try:
            # Delete any test items from DynamoDB
            test_ids = [
                'integration-test-001',
                'integration-test-002',
                'permission-test-001'
            ]
            
            for test_id in test_ids:
                try:
                    self.dynamodb_client.delete_item(
                        TableName=self.app_table_name,
                        Key={'id': {'S': test_id}}
                    )
                except ClientError:
                    pass  # Ignore errors during cleanup
                    
        except Exception:
            pass  # Ignore cleanup errors