"""
Unit tests for Progressive Web Application CDK Stack

This module contains unit tests for the CDK stack components,
ensuring proper resource creation and configuration.
"""

import pytest
import aws_cdk as cdk
from aws_cdk import assertions

# Import the stack class
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import ProgressiveWebAppStack


class TestProgressiveWebAppStack:
    """Test suite for Progressive Web App Stack"""

    def setup_method(self):
        """Set up test fixtures"""
        self.app = cdk.App()
        self.stack = ProgressiveWebAppStack(
            self.app,
            "TestProgressiveWebAppStack",
            env=cdk.Environment(
                account="123456789012",
                region="us-east-1"
            )
        )
        self.template = assertions.Template.from_stack(self.stack)

    def test_cognito_user_pool_created(self):
        """Test that Cognito User Pool is created with correct configuration"""
        self.template.has_resource_properties(
            "AWS::Cognito::UserPool",
            {
                "UserPoolName": assertions.Match.string_like_regexp(r".*-user-pool"),
                "AliasAttributes": ["email", "preferred_username"],
                "AutoVerifiedAttributes": ["email"],
                "Policies": {
                    "PasswordPolicy": {
                        "MinimumLength": 8,
                        "RequireLowercase": True,
                        "RequireNumbers": True,
                        "RequireSymbols": False,
                        "RequireUppercase": True
                    }
                }
            }
        )

    def test_cognito_user_pool_client_created(self):
        """Test that Cognito User Pool Client is created"""
        self.template.has_resource_properties(
            "AWS::Cognito::UserPoolClient",
            {
                "ClientName": assertions.Match.string_like_regexp(r".*-client"),
                "GenerateSecret": False,
                "ExplicitAuthFlows": [
                    "ALLOW_USER_PASSWORD_AUTH",
                    "ALLOW_USER_SRP_AUTH",
                    "ALLOW_REFRESH_TOKEN_AUTH"
                ]
            }
        )

    def test_cognito_identity_pool_created(self):
        """Test that Cognito Identity Pool is created"""
        self.template.has_resource_properties(
            "AWS::Cognito::IdentityPool",
            {
                "IdentityPoolName": assertions.Match.string_like_regexp(r".*-identity-pool"),
                "AllowUnauthenticatedIdentities": True
            }
        )

    def test_dynamodb_table_created(self):
        """Test that DynamoDB table is created with correct configuration"""
        self.template.has_resource_properties(
            "AWS::DynamoDB::Table",
            {
                "TableName": assertions.Match.string_like_regexp(r".*-tasks"),
                "BillingMode": "PAY_PER_REQUEST",
                "StreamSpecification": {
                    "StreamViewType": "NEW_AND_OLD_IMAGES"
                },
                "PointInTimeRecoverySpecification": {
                    "PointInTimeRecoveryEnabled": True
                },
                "SSESpecification": {
                    "SSEEnabled": True
                }
            }
        )

    def test_dynamodb_gsi_created(self):
        """Test that DynamoDB Global Secondary Indexes are created"""
        self.template.has_resource_properties(
            "AWS::DynamoDB::Table",
            {
                "GlobalSecondaryIndexes": assertions.Match.array_with([
                    {
                        "IndexName": "owner-index",
                        "KeySchema": [
                            {"AttributeName": "owner", "KeyType": "HASH"},
                            {"AttributeName": "createdAt", "KeyType": "RANGE"}
                        ],
                        "Projection": {"ProjectionType": "ALL"}
                    },
                    {
                        "IndexName": "priority-index",
                        "KeySchema": [
                            {"AttributeName": "priority", "KeyType": "HASH"},
                            {"AttributeName": "dueDate", "KeyType": "RANGE"}
                        ],
                        "Projection": {"ProjectionType": "ALL"}
                    }
                ])
            }
        )

    def test_s3_bucket_created(self):
        """Test that S3 bucket is created with correct configuration"""
        self.template.has_resource_properties(
            "AWS::S3::Bucket",
            {
                "BucketName": assertions.Match.string_like_regexp(r".*-attachments-.*"),
                "VersioningConfiguration": {
                    "Status": "Enabled"
                },
                "BucketEncryption": {
                    "ServerSideEncryptionConfiguration": [
                        {
                            "ServerSideEncryptionByDefault": {
                                "SSEAlgorithm": "AES256"
                            }
                        }
                    ]
                },
                "PublicAccessBlockConfiguration": {
                    "BlockPublicAcls": True,
                    "BlockPublicPolicy": True,
                    "IgnorePublicAcls": True,
                    "RestrictPublicBuckets": True
                }
            }
        )

    def test_s3_bucket_cors_configured(self):
        """Test that S3 bucket CORS is configured"""
        self.template.has_resource_properties(
            "AWS::S3::Bucket",
            {
                "CorsConfiguration": {
                    "CorsRules": [
                        {
                            "AllowedHeaders": ["*"],
                            "AllowedMethods": ["GET", "POST", "PUT", "DELETE", "HEAD"],
                            "AllowedOrigins": ["*"],
                            "MaxAge": 3000
                        }
                    ]
                }
            }
        )

    def test_lambda_function_created(self):
        """Test that Lambda function is created with correct configuration"""
        self.template.has_resource_properties(
            "AWS::Lambda::Function",
            {
                "FunctionName": assertions.Match.string_like_regexp(r".*-task-resolver"),
                "Runtime": "python3.9",
                "Handler": "index.handler",
                "Timeout": 30,
                "MemorySize": 256
            }
        )

    def test_appsync_api_created(self):
        """Test that AppSync GraphQL API is created"""
        self.template.has_resource_properties(
            "AWS::AppSync::GraphQLApi",
            {
                "Name": assertions.Match.string_like_regexp(r".*-api"),
                "AuthenticationType": "AMAZON_COGNITO_USER_POOLS",
                "XrayEnabled": True,
                "LogConfig": {
                    "FieldLogLevel": "ALL"
                }
            }
        )

    def test_appsync_data_sources_created(self):
        """Test that AppSync data sources are created"""
        # Lambda data source
        self.template.has_resource_properties(
            "AWS::AppSync::DataSource",
            {
                "Name": "TaskResolverDataSource",
                "Type": "AWS_LAMBDA"
            }
        )

        # DynamoDB data source
        self.template.has_resource_properties(
            "AWS::AppSync::DataSource",
            {
                "Name": "TaskTableDataSource",
                "Type": "AMAZON_DYNAMODB"
            }
        )

    def test_appsync_resolvers_created(self):
        """Test that AppSync resolvers are created"""
        # Test for createTask resolver
        self.template.has_resource_properties(
            "AWS::AppSync::Resolver",
            {
                "TypeName": "Mutation",
                "FieldName": "createTask"
            }
        )

        # Test for listTasks resolver
        self.template.has_resource_properties(
            "AWS::AppSync::Resolver",
            {
                "TypeName": "Query",
                "FieldName": "listTasks"
            }
        )

    def test_amplify_app_created(self):
        """Test that Amplify app is created"""
        self.template.has_resource_properties(
            "AWS::Amplify::App",
            {
                "Name": assertions.Match.string_like_regexp(r".*-pwa"),
                "Description": "Progressive Web Application with AWS Amplify"
            }
        )

    def test_amplify_branch_created(self):
        """Test that Amplify branch is created"""
        self.template.has_resource_properties(
            "AWS::Amplify::Branch",
            {
                "BranchName": "main",
                "EnableAutoBuild": True,
                "Stage": "PRODUCTION"
            }
        )

    def test_iam_roles_created(self):
        """Test that IAM roles are created with correct policies"""
        # Test authenticated role
        self.template.has_resource_properties(
            "AWS::IAM::Role",
            {
                "AssumeRolePolicyDocument": {
                    "Statement": [
                        {
                            "Effect": "Allow",
                            "Principal": {
                                "Federated": "cognito-identity.amazonaws.com"
                            },
                            "Action": "sts:AssumeRoleWithWebIdentity"
                        }
                    ]
                }
            }
        )

    def test_cloudwatch_log_groups_created(self):
        """Test that CloudWatch log groups are created"""
        self.template.has_resource_properties(
            "AWS::Logs::LogGroup",
            {
                "LogGroupName": assertions.Match.string_like_regexp(r"/aws/appsync/.*"),
                "RetentionInDays": 7
            }
        )

    def test_stack_outputs_created(self):
        """Test that stack outputs are created"""
        outputs = self.template.find_outputs("*")
        
        # Check that essential outputs exist
        expected_outputs = [
            "UserPoolId",
            "UserPoolClientId", 
            "IdentityPoolId",
            "GraphQLApiId",
            "GraphQLApiUrl",
            "TaskTableName",
            "AttachmentsBucketName",
            "AmplifyAppId",
            "AmplifyAppUrl",
            "Region"
        ]
        
        for output_name in expected_outputs:
            assert output_name in outputs, f"Missing output: {output_name}"

    def test_resource_count(self):
        """Test that the expected number of resources are created"""
        # This helps ensure we're not creating too many or too few resources
        resource_counts = {
            "AWS::Cognito::UserPool": 1,
            "AWS::Cognito::UserPoolClient": 1,
            "AWS::Cognito::IdentityPool": 1,
            "AWS::DynamoDB::Table": 1,
            "AWS::S3::Bucket": 1,
            "AWS::Lambda::Function": 1,
            "AWS::AppSync::GraphQLApi": 1,
            "AWS::Amplify::App": 1,
            "AWS::Amplify::Branch": 1
        }
        
        for resource_type, expected_count in resource_counts.items():
            self.template.resource_count_is(resource_type, expected_count)

    def test_security_best_practices(self):
        """Test that security best practices are followed"""
        # Test that S3 bucket blocks public access
        self.template.has_resource_properties(
            "AWS::S3::Bucket",
            {
                "PublicAccessBlockConfiguration": {
                    "BlockPublicAcls": True,
                    "BlockPublicPolicy": True,
                    "IgnorePublicAcls": True,
                    "RestrictPublicBuckets": True
                }
            }
        )

        # Test that DynamoDB table is encrypted
        self.template.has_resource_properties(
            "AWS::DynamoDB::Table",
            {
                "SSESpecification": {
                    "SSEEnabled": True
                }
            }
        )

    def test_parameter_configuration(self):
        """Test that CDK parameters are properly configured"""
        # This test ensures the stack can be instantiated with different parameters
        app = cdk.App()
        
        # Test with different parameters
        test_stack = ProgressiveWebAppStack(
            app,
            "TestStack",
            env=cdk.Environment(account="123456789012", region="us-west-2")
        )
        
        # Verify stack was created successfully
        assert test_stack is not None
        
        # Test template synthesis
        template = assertions.Template.from_stack(test_stack)
        assert template is not None


# Integration tests (optional)
class TestIntegration:
    """Integration tests for the full stack"""

    @pytest.mark.integration
    def test_full_stack_deployment(self):
        """Test that the full stack can be deployed (requires AWS credentials)"""
        # This would be an integration test that actually deploys to AWS
        # and verifies the resources work together correctly
        pytest.skip("Integration tests require AWS credentials and real deployment")

    @pytest.mark.integration
    def test_graphql_api_functionality(self):
        """Test GraphQL API functionality"""
        # This would test actual GraphQL operations
        pytest.skip("Integration tests require deployed infrastructure")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])