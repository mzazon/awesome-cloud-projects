#!/usr/bin/env python3
"""
CDK Python Application for Building Advanced Recommendation Systems with Amazon Personalize

This application deploys a comprehensive recommendation system using Amazon Personalize
with multiple ML algorithms, real-time and batch inference capabilities, A/B testing
framework, and automated model retraining.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_apigateway as apigateway,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class PersonalizeRecommendationStack(Stack):
    """
    CDK Stack for Amazon Personalize Recommendation System
    
    This stack creates:
    - S3 bucket for training data and batch outputs
    - IAM roles for Personalize service and Lambda functions
    - Lambda functions for recommendation API with A/B testing
    - EventBridge rules for automated model retraining
    - API Gateway for REST API endpoints
    - CloudWatch monitoring and dashboards
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.dataset_group_name = f"ecommerce-recommendation-{cdk.Aws.ACCOUNT_ID[:8]}"
        self.random_suffix = cdk.Aws.ACCOUNT_ID[:8].lower()
        
        # Create S3 bucket for data storage
        self.data_bucket = self._create_data_bucket()
        
        # Create IAM roles
        self.personalize_role = self._create_personalize_service_role()
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda functions
        self.recommendation_function = self._create_recommendation_function()
        self.retraining_function = self._create_retraining_function()
        
        # Create API Gateway
        self.api = self._create_api_gateway()
        
        # Create EventBridge for automated retraining
        self._create_retraining_schedule()
        
        # Create CloudWatch dashboard
        self._create_monitoring_dashboard()
        
        # Output important values
        self._create_outputs()

    def _create_data_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing training data and batch outputs."""
        bucket = s3.Bucket(
            self,
            "PersonalizeDataBucket",
            bucket_name=f"personalize-comprehensive-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="training-data-lifecycle",
                    enabled=True,
                    expiration=Duration.days(365),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )

        # Create directory structure in S3
        for prefix in ["training-data/", "batch-output/", "metadata/", "batch-input/"]:
            s3.BucketDeployment(
                self,
                f"Create{prefix.replace('/', '').replace('-', '').title()}Prefix",
                sources=[s3.Source.data(prefix, "")],
                destination_bucket=bucket,
                destination_key_prefix=prefix
            )

        return bucket

    def _create_personalize_service_role(self) -> iam.Role:
        """Create IAM role for Amazon Personalize service."""
        role = iam.Role(
            self,
            "PersonalizeServiceRole",
            role_name=f"PersonalizeServiceRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("personalize.amazonaws.com"),
            description="Service role for Amazon Personalize to access S3 data",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonPersonalizeFullAccess")
            ]
        )

        # Add custom S3 policy
        s3_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:ListBucket",
                        "s3:PutObject"
                    ],
                    resources=[
                        self.data_bucket.bucket_arn,
                        f"{self.data_bucket.bucket_arn}/*"
                    ]
                )
            ]
        )

        iam.Policy(
            self,
            "PersonalizeS3Policy",
            policy_name=f"PersonalizeS3Access-{self.random_suffix}",
            policy_document=s3_policy,
            roles=[role]
        )

        return role

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda functions."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"LambdaRecommendationRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for recommendation Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add Personalize and CloudWatch permissions
        personalize_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "personalize:GetRecommendations",
                        "personalize:GetPersonalizedRanking",
                        "personalize:DescribeCampaign",
                        "personalize:DescribeFilter",
                        "personalize:CreateSolutionVersion",
                        "personalize:DescribeSolutionVersion",
                        "personalize:ListSolutions",
                        "personalize:ListSolutionVersions"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudwatch:PutMetricData",
                        "cloudwatch:GetMetricStatistics",
                        "cloudwatch:ListMetrics"
                    ],
                    resources=["*"]
                )
            ]
        )

        iam.Policy(
            self,
            "LambdaPersonalizePolicy",
            policy_name=f"LambdaPersonalizePolicy-{self.random_suffix}",
            policy_document=personalize_policy,
            roles=[role]
        )

        return role

    def _create_recommendation_function(self) -> lambda_.Function:
        """Create Lambda function for recommendation API with A/B testing."""
        function = lambda_.Function(
            self,
            "RecommendationFunction",
            function_name=f"comprehensive-recommendation-api-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="recommendation_service.lambda_handler",
            code=lambda_.Code.from_inline(self._get_recommendation_function_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=512,
            environment={
                "BUCKET_NAME": self.data_bucket.bucket_name,
                "DATASET_GROUP_NAME": self.dataset_group_name,
                "RANDOM_SUFFIX": self.random_suffix,
                # These will be set manually or via parameter store in production
                "USER_PERSONALIZATION_CAMPAIGN_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:campaign/user-personalization-campaign-{self.random_suffix}",
                "SIMILAR_ITEMS_CAMPAIGN_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:campaign/similar-items-campaign-{self.random_suffix}",
                "TRENDING_NOW_CAMPAIGN_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:campaign/trending-now-campaign-{self.random_suffix}",
                "POPULARITY_CAMPAIGN_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:campaign/popularity-campaign-{self.random_suffix}",
                "EXCLUDE_PURCHASED_FILTER_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:filter/exclude-purchased-{self.random_suffix}",
                "CATEGORY_FILTER_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:filter/category-filter-{self.random_suffix}",
                "PRICE_FILTER_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:filter/price-filter-{self.random_suffix}",
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            description="Comprehensive recommendation API with A/B testing and filtering capabilities"
        )

        return function

    def _create_retraining_function(self) -> lambda_.Function:
        """Create Lambda function for automated model retraining."""
        function = lambda_.Function(
            self,
            "RetrainingFunction",
            function_name=f"personalize-retraining-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="retraining_automation.lambda_handler",
            code=lambda_.Code.from_inline(self._get_retraining_function_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "USER_PERSONALIZATION_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:solution/user-personalization-{self.random_suffix}",
                "SIMILAR_ITEMS_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:solution/similar-items-{self.random_suffix}",
                "TRENDING_NOW_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:solution/trending-now-{self.random_suffix}",
                "POPULARITY_ARN": f"arn:aws:personalize:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:solution/popularity-count-{self.random_suffix}",
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            description="Automated retraining function for Personalize solutions"
        )

        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """Create API Gateway for recommendation endpoints."""
        api = apigateway.RestApi(
            self,
            "RecommendationAPI",
            rest_api_name=f"personalize-recommendation-api-{self.random_suffix}",
            description="Comprehensive recommendation API with A/B testing",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            ),
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            )
        )

        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.recommendation_function,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )

        # Create recommendation resources and methods
        recommendations = api.root.add_resource("recommendations")
        
        # GET /recommendations/{userId}
        user_resource = recommendations.add_resource("{userId}")
        user_resource.add_method(
            "GET",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

        # GET /recommendations/{userId}/{type}
        type_resource = user_resource.add_resource("{type}")
        type_resource.add_method("GET", lambda_integration)

        # GET /recommendations/similar/{itemId}
        similar = recommendations.add_resource("similar")
        item_resource = similar.add_resource("{itemId}")
        item_resource.add_method("GET", lambda_integration)

        return api

    def _create_retraining_schedule(self) -> None:
        """Create EventBridge rule for automated retraining."""
        rule = events.Rule(
            self,
            "RetrainingSchedule",
            rule_name=f"personalize-retraining-{self.random_suffix}",
            description="Trigger Personalize model retraining weekly",
            schedule=events.Schedule.rate(Duration.days(7)),
            enabled=True
        )

        # Add Lambda target
        rule.add_target(
            targets.LambdaFunction(
                self.retraining_function,
                retry_attempts=2
            )
        )

        # Grant EventBridge permission to invoke Lambda
        self.retraining_function.add_permission(
            "AllowEventBridge",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            source_arn=rule.rule_arn,
            action="lambda:InvokeFunction"
        )

    def _create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring recommendation system."""
        dashboard = cloudwatch.Dashboard(
            self,
            "PersonalizeDashboard",
            dashboard_name=f"PersonalizeRecommendations-{self.random_suffix}"
        )

        # Lambda metrics
        lambda_widget = cloudwatch.GraphWidget(
            title="Lambda Function Metrics",
            width=12,
            height=6,
            left=[
                self.recommendation_function.metric_invocations(),
                self.recommendation_function.metric_errors(),
                self.recommendation_function.metric_duration()
            ]
        )

        # API Gateway metrics
        api_widget = cloudwatch.GraphWidget(
            title="API Gateway Metrics",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/ApiGateway",
                    metric_name="Count",
                    dimensions_map={"ApiName": self.api.rest_api_name}
                ),
                cloudwatch.Metric(
                    namespace="AWS/ApiGateway",
                    metric_name="Latency",
                    dimensions_map={"ApiName": self.api.rest_api_name}
                )
            ]
        )

        # A/B Testing metrics
        ab_test_widget = cloudwatch.GraphWidget(
            title="A/B Testing Metrics",
            width=24,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="PersonalizeABTest",
                    metric_name="RecommendationRequests",
                    dimensions_map={"Strategy": "user_personalization"}
                ),
                cloudwatch.Metric(
                    namespace="PersonalizeABTest",
                    metric_name="RecommendationRequests",
                    dimensions_map={"Strategy": "similar_items"}
                ),
                cloudwatch.Metric(
                    namespace="PersonalizeABTest",
                    metric_name="RecommendationRequests",
                    dimensions_map={"Strategy": "trending_now"}
                ),
                cloudwatch.Metric(
                    namespace="PersonalizeABTest",
                    metric_name="RecommendationRequests",
                    dimensions_map={"Strategy": "popularity"}
                )
            ]
        )

        dashboard.add_widgets(lambda_widget, api_widget, ab_test_widget)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for training data and batch outputs"
        )

        CfnOutput(
            self,
            "PersonalizeServiceRoleArn",
            value=self.personalize_role.role_arn,
            description="IAM role ARN for Amazon Personalize service"
        )

        CfnOutput(
            self,
            "RecommendationAPIEndpoint",
            value=self.api.url,
            description="API Gateway endpoint for recommendation API"
        )

        CfnOutput(
            self,
            "RecommendationFunctionName",
            value=self.recommendation_function.function_name,
            description="Lambda function name for recommendation API"
        )

        CfnOutput(
            self,
            "RetrainingFunctionName",
            value=self.retraining_function.function_name,
            description="Lambda function name for automated retraining"
        )

        CfnOutput(
            self,
            "DatasetGroupName",
            value=self.dataset_group_name,
            description="Amazon Personalize dataset group name"
        )

    def _get_recommendation_function_code(self) -> str:
        """Return the recommendation Lambda function code."""
        return '''
import json
import boto3
import os
import random
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

personalize_runtime = boto3.client('personalize-runtime')
cloudwatch = boto3.client('cloudwatch')

# A/B Testing Configuration
AB_TEST_CONFIG = {
    'user_personalization': 0.4,  # 40% traffic
    'similar_items': 0.2,         # 20% traffic
    'trending_now': 0.2,          # 20% traffic
    'popularity': 0.2             # 20% traffic
}

def get_recommendation_strategy(user_id):
    """Determine recommendation strategy based on A/B testing"""
    hash_value = hash(user_id) % 100
    cumulative_prob = 0
    
    for strategy, probability in AB_TEST_CONFIG.items():
        cumulative_prob += probability * 100
        if hash_value < cumulative_prob:
            return strategy
    
    return 'user_personalization'  # Default fallback

def get_recommendations(campaign_arn, user_id, num_results=10, filter_arn=None, filter_values=None):
    """Get recommendations from Personalize campaign"""
    try:
        params = {
            'campaignArn': campaign_arn,
            'userId': user_id,
            'numResults': num_results
        }
        
        if filter_arn and filter_values:
            params['filterArn'] = filter_arn
            params['filterValues'] = filter_values
        
        response = personalize_runtime.get_recommendations(**params)
        return response
        
    except Exception as e:
        logger.error(f"Error getting recommendations: {str(e)}")
        return None

def get_similar_items(campaign_arn, item_id, num_results=10):
    """Get similar items recommendations"""
    try:
        response = personalize_runtime.get_recommendations(
            campaignArn=campaign_arn,
            itemId=item_id,
            numResults=num_results
        )
        return response
        
    except Exception as e:
        logger.error(f"Error getting similar items: {str(e)}")
        return None

def send_ab_test_metrics(strategy, user_id, response_time, num_results):
    """Send A/B testing metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='PersonalizeABTest',
            MetricData=[
                {
                    'MetricName': 'RecommendationRequests',
                    'Dimensions': [
                        {'Name': 'Strategy', 'Value': strategy}
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'ResponseTime',
                    'Dimensions': [
                        {'Name': 'Strategy', 'Value': strategy}
                    ],
                    'Value': response_time,
                    'Unit': 'Milliseconds'
                },
                {
                    'MetricName': 'NumResults',
                    'Dimensions': [
                        {'Name': 'Strategy', 'Value': strategy}
                    ],
                    'Value': num_results,
                    'Unit': 'Count'
                }
            ]
        )
    except Exception as e:
        logger.error(f"Error sending metrics: {str(e)}")

def lambda_handler(event, context):
    start_time = datetime.now()
    
    try:
        # Extract parameters
        path_params = event.get('pathParameters', {})
        query_params = event.get('queryStringParameters') or {}
        
        user_id = path_params.get('userId')
        item_id = path_params.get('itemId')
        recommendation_type = path_params.get('type', 'personalized')
        
        num_results = int(query_params.get('numResults', 10))
        category = query_params.get('category')
        min_price = query_params.get('minPrice')
        max_price = query_params.get('maxPrice')
        
        # Determine strategy based on A/B testing
        if recommendation_type == 'personalized' and user_id:
            strategy = get_recommendation_strategy(user_id)
        else:
            strategy = recommendation_type
        
        # Map strategies to campaign ARNs
        campaign_mapping = {
            'user_personalization': os.environ.get('USER_PERSONALIZATION_CAMPAIGN_ARN'),
            'similar_items': os.environ.get('SIMILAR_ITEMS_CAMPAIGN_ARN'),
            'trending_now': os.environ.get('TRENDING_NOW_CAMPAIGN_ARN'),
            'popularity': os.environ.get('POPULARITY_CAMPAIGN_ARN')
        }
        
        # Handle different recommendation types
        if strategy == 'similar_items' and item_id:
            response = get_similar_items(
                campaign_mapping[strategy], 
                item_id, 
                num_results
            )
        elif user_id:
            # Apply filters if specified
            filter_arn = None
            filter_values = {}
            
            if category:
                filter_arn = os.environ.get('CATEGORY_FILTER_ARN')
                filter_values['$CATEGORY'] = f'"{category}"'
            
            if min_price and max_price:
                filter_arn = os.environ.get('PRICE_FILTER_ARN')
                filter_values['$MIN_PRICE'] = min_price
                filter_values['$MAX_PRICE'] = max_price
            
            response = get_recommendations(
                campaign_mapping[strategy],
                user_id,
                num_results,
                filter_arn,
                filter_values
            )
        else:
            raise ValueError("Missing required parameters")
        
        if not response:
            raise Exception("Failed to get recommendations")
        
        # Calculate response time
        response_time = (datetime.now() - start_time).total_seconds() * 1000
        
        # Send A/B testing metrics
        send_ab_test_metrics(strategy, user_id, response_time, len(response.get('itemList', [])))
        
        # Format response
        recommendations = []
        for item in response.get('itemList', []):
            recommendations.append({
                'itemId': item['itemId'],
                'score': item.get('score', 0)
            })
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'userId': user_id,
                'itemId': item_id,
                'strategy': strategy,
                'recommendations': recommendations,
                'responseTime': response_time,
                'requestId': context.aws_request_id
            })
        }
        
    except Exception as e:
        logger.error(f"Error in recommendation handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }
'''

    def _get_retraining_function_code(self) -> str:
        """Return the retraining Lambda function code."""
        return '''
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

personalize = boto3.client('personalize')

def lambda_handler(event, context):
    """Automated retraining function"""
    
    solutions = [
        os.environ.get('USER_PERSONALIZATION_ARN'),
        os.environ.get('SIMILAR_ITEMS_ARN'),
        os.environ.get('TRENDING_NOW_ARN'),
        os.environ.get('POPULARITY_ARN')
    ]
    
    retraining_results = []
    
    for solution_arn in solutions:
        if solution_arn:
            try:
                # Create new solution version for retraining
                response = personalize.create_solution_version(
                    solutionArn=solution_arn,
                    trainingMode='UPDATE'  # Incremental training
                )
                
                retraining_results.append({
                    'solutionArn': solution_arn,
                    'solutionVersionArn': response['solutionVersionArn'],
                    'status': 'INITIATED'
                })
                
                logger.info(f"Initiated retraining for {solution_arn}")
                
            except Exception as e:
                logger.error(f"Error retraining {solution_arn}: {str(e)}")
                retraining_results.append({
                    'solutionArn': solution_arn,
                    'status': 'FAILED',
                    'error': str(e)
                })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Retraining process initiated',
            'results': retraining_results
        })
    }
'''


class PersonalizeRecommendationApp(cdk.App):
    """CDK Application for Amazon Personalize Recommendation System."""
    
    def __init__(self):
        super().__init__()
        
        # Create the main stack
        PersonalizeRecommendationStack(
            self,
            "PersonalizeRecommendationStack",
            description="Comprehensive recommendation system using Amazon Personalize with A/B testing and automated retraining",
            env=cdk.Environment(
                account=os.getenv('CDK_DEFAULT_ACCOUNT'),
                region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
            )
        )


# Create and run the application
app = PersonalizeRecommendationApp()
app.synth()