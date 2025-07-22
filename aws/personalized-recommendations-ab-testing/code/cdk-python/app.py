#!/usr/bin/env python3
"""
CDK Application for Real-Time Recommendations with Personalize and A/B Testing

This CDK application deploys a comprehensive real-time recommendation platform
using Amazon Personalize for ML-powered recommendations, combined with
sophisticated A/B testing frameworks and real-time analytics.

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_apigatewayv2 as apigatewayv2,
    aws_apigatewayv2_integrations as integrations,
    aws_dynamodb as dynamodb,
    aws_kinesis as kinesis,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_stepfunctions as stepfunctions,
    aws_stepfunctions_tasks as tasks,
    aws_events as events,
    aws_events_targets as targets,
)
from constructs import Construct


class PersonalizeRecommendationStack(Stack):
    """
    CDK Stack for Real-Time Recommendations with Personalize and A/B Testing
    
    This stack creates:
    - S3 bucket for training datasets
    - DynamoDB tables for user profiles, items, A/B assignments, and events
    - Lambda functions for A/B testing, recommendations, event tracking, and Personalize management
    - API Gateway for REST endpoints
    - Kinesis streams for real-time analytics
    - CloudWatch dashboards and alarms
    - Step Functions for model training orchestration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:]

        # Create S3 bucket for Personalize datasets
        self.data_bucket = self._create_data_bucket(unique_suffix)

        # Create DynamoDB tables
        self.tables = self._create_dynamodb_tables(unique_suffix)

        # Create IAM roles
        self.roles = self._create_iam_roles(unique_suffix)

        # Create Kinesis streams for analytics
        self.analytics_stream = self._create_kinesis_streams(unique_suffix)

        # Create Lambda functions
        self.lambda_functions = self._create_lambda_functions(unique_suffix)

        # Create API Gateway
        self.api = self._create_api_gateway(unique_suffix)

        # Create Step Functions for model training orchestration
        self.training_workflow = self._create_training_workflow(unique_suffix)

        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard(unique_suffix)

        # Create outputs
        self._create_outputs()

    def _create_data_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for Personalize training datasets"""
        bucket = s3.Bucket(
            self,
            "PersonalizeDataBucket",
            bucket_name=f"personalize-data-{suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TrainingDataLifecycle",
                    enabled=True,
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

        # Add CORS configuration for web uploads
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000
        )

        return bucket

    def _create_dynamodb_tables(self, suffix: str) -> Dict[str, dynamodb.Table]:
        """Create DynamoDB tables for the recommendation system"""
        tables = {}

        # User profiles table
        tables['users'] = dynamodb.Table(
            self,
            "UsersTable",
            table_name=f"personalize-ab-{suffix}-users",
            partition_key=dynamodb.Attribute(
                name="UserId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )

        # Items catalog table with GSI for category queries
        tables['items'] = dynamodb.Table(
            self,
            "ItemsTable",
            table_name=f"personalize-ab-{suffix}-items",
            partition_key=dynamodb.Attribute(
                name="ItemId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        # Add GSI for category-based queries
        tables['items'].add_global_secondary_index(
            index_name="CategoryIndex",
            partition_key=dynamodb.Attribute(
                name="Category",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # A/B test assignments table
        tables['ab_assignments'] = dynamodb.Table(
            self,
            "ABAssignmentsTable",
            table_name=f"personalize-ab-{suffix}-ab-assignments",
            partition_key=dynamodb.Attribute(
                name="UserId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="TestName",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        # Real-time events table
        tables['events'] = dynamodb.Table(
            self,
            "EventsTable",
            table_name=f"personalize-ab-{suffix}-events",
            partition_key=dynamodb.Attribute(
                name="UserId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            time_to_live_attribute="TTL",
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )

        return tables

    def _create_iam_roles(self, suffix: str) -> Dict[str, iam.Role]:
        """Create IAM roles for various services"""
        roles = {}

        # Personalize service role
        roles['personalize'] = iam.Role(
            self,
            "PersonalizeServiceRole",
            role_name=f"PersonalizeABTestRole-{suffix}",
            assumed_by=iam.ServicePrincipal("personalize.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonPersonalizeFullAccess")
            ]
        )

        # Add S3 access for Personalize
        roles['personalize'].add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*"
                ]
            )
        )

        # Lambda execution role
        roles['lambda'] = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"PersonalizeLambdaRole-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add permissions for Lambda functions
        roles['lambda'].add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Scan",
                    "dynamodb:Query"
                ],
                resources=[table.table_arn for table in self.tables.values()]
            )
        )

        roles['lambda'].add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "personalize:GetRecommendations",
                    "personalize:DescribeCampaign",
                    "personalize:DescribeSolution",
                    "personalize:CreateDataset*",
                    "personalize:CreateSolution*",
                    "personalize:CreateCampaign",
                    "personalize:PutEvents"
                ],
                resources=["*"]
            )
        )

        roles['lambda'].add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:PutRecord",
                    "kinesis:PutRecords"
                ],
                resources=["*"]
            )
        )

        # Step Functions execution role
        roles['stepfunctions'] = iam.Role(
            self,
            "StepFunctionsRole",
            role_name=f"PersonalizeStepFunctionsRole-{suffix}",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSStepFunctionsFullAccess")
            ]
        )

        roles['stepfunctions'].add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=["*"]
            )
        )

        return roles

    def _create_kinesis_streams(self, suffix: str) -> kinesis.Stream:
        """Create Kinesis streams for real-time analytics"""
        stream = kinesis.Stream(
            self,
            "AnalyticsStream",
            stream_name=f"personalize-analytics-{suffix}",
            shard_count=2,
            retention_period=Duration.days(7),
            encryption=kinesis.StreamEncryption.MANAGED
        )

        return stream

    def _create_lambda_functions(self, suffix: str) -> Dict[str, lambda_.Function]:
        """Create Lambda functions for the recommendation system"""
        functions = {}

        # Common environment variables
        common_env = {
            "ITEMS_TABLE": self.tables['items'].table_name,
            "USERS_TABLE": self.tables['users'].table_name,
            "EVENTS_TABLE": self.tables['events'].table_name,
            "AB_ASSIGNMENTS_TABLE": self.tables['ab_assignments'].table_name,
            "ANALYTICS_STREAM": self.analytics_stream.stream_name,
            "DATA_BUCKET": self.data_bucket.bucket_name
        }

        # A/B Test Router Lambda
        functions['ab_router'] = lambda_.Function(
            self,
            "ABTestRouter",
            function_name=f"personalize-ab-{suffix}-ab-test-router",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_ab_router_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment=common_env,
            role=self.roles['lambda'],
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Recommendation Engine Lambda
        functions['recommendation'] = lambda_.Function(
            self,
            "RecommendationEngine",
            function_name=f"personalize-ab-{suffix}-recommendation-engine",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_recommendation_code()),
            timeout=Duration.seconds(30),
            memory_size=512,
            environment=common_env,
            role=self.roles['lambda'],
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Event Tracker Lambda
        functions['event_tracker'] = lambda_.Function(
            self,
            "EventTracker",
            function_name=f"personalize-ab-{suffix}-event-tracker",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_event_tracker_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment=common_env,
            role=self.roles['lambda'],
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Personalize Manager Lambda
        functions['personalize_manager'] = lambda_.Function(
            self,
            "PersonalizeManager",
            function_name=f"personalize-ab-{suffix}-personalize-manager",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_personalize_manager_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            environment=common_env,
            role=self.roles['lambda'],
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Analytics Lambda
        functions['analytics'] = lambda_.Function(
            self,
            "AnalyticsProcessor",
            function_name=f"personalize-ab-{suffix}-analytics",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_analytics_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            environment=common_env,
            role=self.roles['lambda'],
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Grant DynamoDB permissions to all Lambda functions
        for table in self.tables.values():
            for function in functions.values():
                table.grant_read_write_data(function)

        # Grant Kinesis permissions
        self.analytics_stream.grant_write(functions['event_tracker'])
        self.analytics_stream.grant_read(functions['analytics'])

        return functions

    def _create_api_gateway(self, suffix: str) -> apigatewayv2.HttpApi:
        """Create API Gateway for the recommendation service"""
        api = apigatewayv2.HttpApi(
            self,
            "RecommendationAPI",
            api_name=f"personalize-ab-{suffix}-recommendation-api",
            description="Real-time recommendation API with A/B testing",
            cors_preflight=apigatewayv2.CorsPreflightOptions(
                allow_origins=["*"],
                allow_methods=[apigatewayv2.CorsHttpMethod.GET, apigatewayv2.CorsHttpMethod.POST],
                allow_headers=["content-type", "authorization"]
            )
        )

        # Create integrations
        ab_router_integration = integrations.HttpLambdaIntegration(
            "ABRouterIntegration",
            self.lambda_functions['ab_router']
        )

        recommendation_integration = integrations.HttpLambdaIntegration(
            "RecommendationIntegration",
            self.lambda_functions['recommendation']
        )

        event_tracker_integration = integrations.HttpLambdaIntegration(
            "EventTrackerIntegration",
            self.lambda_functions['event_tracker']
        )

        # Create routes
        api.add_routes(
            path="/ab-test",
            methods=[apigatewayv2.HttpMethod.POST],
            integration=ab_router_integration
        )

        api.add_routes(
            path="/recommendations",
            methods=[apigatewayv2.HttpMethod.POST],
            integration=recommendation_integration
        )

        api.add_routes(
            path="/events",
            methods=[apigatewayv2.HttpMethod.POST],
            integration=event_tracker_integration
        )

        return api

    def _create_training_workflow(self, suffix: str) -> stepfunctions.StateMachine:
        """Create Step Functions workflow for model training orchestration"""
        
        # Define tasks
        create_dataset_group_task = tasks.LambdaInvoke(
            self,
            "CreateDatasetGroup",
            lambda_function=self.lambda_functions['personalize_manager'],
            payload=stepfunctions.TaskInput.from_object({
                "action": "create_dataset_group",
                "dataset_group_name": f"personalize-ab-{suffix}"
            }),
            result_path="$.datasetGroup"
        )

        import_data_task = tasks.LambdaInvoke(
            self,
            "ImportData",
            lambda_function=self.lambda_functions['personalize_manager'],
            payload=stepfunctions.TaskInput.from_object({
                "action": "import_data",
                "dataset_arn": stepfunctions.JsonPath.string_at("$.datasetGroup.Payload.dataset_arn"),
                "job_name": f"import-job-{suffix}",
                "s3_data_source": f"s3://{self.data_bucket.bucket_name}/training-data/",
                "role_arn": self.roles['personalize'].role_arn
            }),
            result_path="$.importJob"
        )

        create_solution_task = tasks.LambdaInvoke(
            self,
            "CreateSolution",
            lambda_function=self.lambda_functions['personalize_manager'],
            payload=stepfunctions.TaskInput.from_object({
                "action": "create_solution",
                "solution_name": f"solution-{suffix}",
                "dataset_group_arn": stepfunctions.JsonPath.string_at("$.datasetGroup.Payload.dataset_group_arn"),
                "recipe_arn": "arn:aws:personalize:::recipe/aws-user-personalization"
            }),
            result_path="$.solution"
        )

        create_campaign_task = tasks.LambdaInvoke(
            self,
            "CreateCampaign",
            lambda_function=self.lambda_functions['personalize_manager'],
            payload=stepfunctions.TaskInput.from_object({
                "action": "create_campaign",
                "campaign_name": f"campaign-{suffix}",
                "solution_version_arn": stepfunctions.JsonPath.string_at("$.solution.Payload.solution_version_arn"),
                "min_provisioned_tps": 1
            }),
            result_path="$.campaign"
        )

        # Create workflow definition
        definition = create_dataset_group_task.next(
            import_data_task
        ).next(
            create_solution_task
        ).next(
            create_campaign_task
        )

        # Create state machine
        state_machine = stepfunctions.StateMachine(
            self,
            "ModelTrainingWorkflow",
            state_machine_name=f"personalize-training-{suffix}",
            definition=definition,
            role=self.roles['stepfunctions'],
            timeout=Duration.hours(6)
        )

        return state_machine

    def _create_cloudwatch_dashboard(self, suffix: str) -> None:
        """Create CloudWatch dashboard for monitoring"""
        dashboard = cloudwatch.Dashboard(
            self,
            "PersonalizeDashboard",
            dashboard_name=f"Personalize-AB-Testing-{suffix}"
        )

        # Add widgets for Lambda function metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Invocations",
                left=[
                    self.lambda_functions['ab_router'].metric_invocations(),
                    self.lambda_functions['recommendation'].metric_invocations(),
                    self.lambda_functions['event_tracker'].metric_invocations()
                ],
                width=12
            )
        )

        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Errors",
                left=[
                    self.lambda_functions['ab_router'].metric_errors(),
                    self.lambda_functions['recommendation'].metric_errors(),
                    self.lambda_functions['event_tracker'].metric_errors()
                ],
                width=12
            )
        )

        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Duration",
                left=[
                    self.lambda_functions['ab_router'].metric_duration(),
                    self.lambda_functions['recommendation'].metric_duration(),
                    self.lambda_functions['event_tracker'].metric_duration()
                ],
                width=12
            )
        )

        # Add widgets for DynamoDB metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="DynamoDB Read/Write Capacity",
                left=[
                    self.tables['users'].metric_consumed_read_capacity_units(),
                    self.tables['items'].metric_consumed_read_capacity_units(),
                    self.tables['events'].metric_consumed_read_capacity_units()
                ],
                right=[
                    self.tables['users'].metric_consumed_write_capacity_units(),
                    self.tables['items'].metric_consumed_write_capacity_units(),
                    self.tables['events'].metric_consumed_write_capacity_units()
                ],
                width=12
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        CfnOutput(
            self,
            "APIEndpoint",
            value=self.api.api_endpoint,
            description="API Gateway endpoint for recommendation service"
        )

        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for Personalize training data"
        )

        CfnOutput(
            self,
            "PersonalizeRoleArn",
            value=self.roles['personalize'].role_arn,
            description="IAM role ARN for Personalize service"
        )

        CfnOutput(
            self,
            "TrainingWorkflowArn",
            value=self.training_workflow.state_machine_arn,
            description="Step Functions state machine for model training"
        )

        CfnOutput(
            self,
            "AnalyticsStreamName",
            value=self.analytics_stream.stream_name,
            description="Kinesis stream for real-time analytics"
        )

        # Output table names
        for table_type, table in self.tables.items():
            CfnOutput(
                self,
                f"{table_type.title()}TableName",
                value=table.table_name,
                description=f"DynamoDB table name for {table_type}"
            )

    def _get_ab_router_code(self) -> str:
        """Return A/B test router Lambda function code"""
        return '''
import json
import boto3
import hashlib
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Route users to A/B test variants using consistent hashing"""
    try:
        body = json.loads(event.get('body', '{}'))
        user_id = body.get('user_id')
        test_name = body.get('test_name', 'default_recommendation_test')
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'user_id is required'})
            }
        
        # Get or assign A/B test variant
        variant = get_or_assign_variant(user_id, test_name)
        
        # Get recommendation model configuration for variant
        model_config = get_model_config(variant)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'user_id': user_id,
                'test_name': test_name,
                'variant': variant,
                'model_config': model_config
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_or_assign_variant(user_id, test_name):
    """Get existing assignment or create new one"""
    table = dynamodb.Table(os.environ['AB_ASSIGNMENTS_TABLE'])
    
    try:
        response = table.get_item(
            Key={'UserId': user_id, 'TestName': test_name}
        )
        
        if 'Item' in response:
            return response['Item']['Variant']
    except Exception:
        pass
    
    # Assign new variant using consistent hashing
    variant = assign_variant(user_id, test_name)
    
    # Store assignment
    table.put_item(
        Item={
            'UserId': user_id,
            'TestName': test_name,
            'Variant': variant,
            'AssignmentTimestamp': int(datetime.now().timestamp())
        }
    )
    
    return variant

def assign_variant(user_id, test_name):
    """Assign variant using consistent hashing"""
    hash_input = f"{user_id}-{test_name}".encode('utf-8')
    hash_value = int(hashlib.md5(hash_input).hexdigest(), 16)
    
    # Define test configuration
    test_config = {
        'default_recommendation_test': {
            'variant_a': 0.33,  # User-Personalization
            'variant_b': 0.33,  # Similar-Items
            'variant_c': 0.34   # Popularity-Count
        }
    }
    
    config = test_config.get(test_name, test_config['default_recommendation_test'])
    
    # Determine variant based on hash
    normalized_hash = (hash_value % 10000) / 10000.0
    
    cumulative = 0
    for variant, probability in config.items():
        cumulative += probability
        if normalized_hash <= cumulative:
            return variant
    
    return 'variant_a'  # Fallback

def get_model_config(variant):
    """Get model configuration for variant"""
    configs = {
        'variant_a': {
            'recipe': 'aws-user-personalization',
            'campaign_arn': os.environ.get('CAMPAIGN_A_ARN'),
            'description': 'User-Personalization Algorithm'
        },
        'variant_b': {
            'recipe': 'aws-sims',
            'campaign_arn': os.environ.get('CAMPAIGN_B_ARN'),
            'description': 'Item-to-Item Similarity Algorithm'
        },
        'variant_c': {
            'recipe': 'aws-popularity-count',
            'campaign_arn': os.environ.get('CAMPAIGN_C_ARN'),
            'description': 'Popularity-Based Algorithm'
        }
    }
    
    return configs.get(variant, configs['variant_a'])
'''

    def _get_recommendation_code(self) -> str:
        """Return recommendation engine Lambda function code"""
        return '''
import json
import boto3
import os
from datetime import datetime

personalize_runtime = boto3.client('personalize-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Generate personalized recommendations"""
    try:
        body = json.loads(event.get('body', '{}'))
        user_id = body.get('user_id')
        model_config = body.get('model_config', {})
        num_results = body.get('num_results', 10)
        context_data = body.get('context', {})
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'user_id is required'})
            }
        
        try:
            # Get recommendations from Personalize
            recommendations = get_personalize_recommendations(
                user_id, model_config, num_results, context_data
            )
            
            # Enrich recommendations with item metadata
            enriched_recommendations = enrich_recommendations(recommendations)
            
            # Track recommendation request
            track_recommendation_request(user_id, model_config, enriched_recommendations)
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'user_id': user_id,
                    'recommendations': enriched_recommendations,
                    'algorithm': model_config.get('description', 'Unknown'),
                    'timestamp': datetime.now().isoformat()
                })
            }
            
        except Exception as e:
            # Fallback to popularity-based recommendations
            fallback_recommendations = get_fallback_recommendations(num_results)
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'user_id': user_id,
                    'recommendations': fallback_recommendations,
                    'algorithm': 'Fallback - Popularity Based',
                    'error': str(e),
                    'timestamp': datetime.now().isoformat()
                })
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_personalize_recommendations(user_id, model_config, num_results, context_data):
    """Get recommendations from Personalize"""
    campaign_arn = model_config.get('campaign_arn')
    
    if not campaign_arn:
        raise ValueError("No campaign ARN provided")
    
    request_params = {
        'campaignArn': campaign_arn,
        'userId': user_id,
        'numResults': num_results
    }
    
    if context_data:
        request_params['context'] = context_data
    
    response = personalize_runtime.get_recommendations(**request_params)
    return response['itemList']

def enrich_recommendations(recommendations):
    """Enrich recommendations with item metadata"""
    items_table = dynamodb.Table(os.environ['ITEMS_TABLE'])
    
    enriched = []
    for item in recommendations:
        item_id = item['itemId']
        
        try:
            response = items_table.get_item(Key={'ItemId': item_id})
            
            if 'Item' in response:
                item_data = response['Item']
                enriched.append({
                    'item_id': item_id,
                    'score': item.get('score', 0),
                    'category': item_data.get('Category', 'Unknown'),
                    'price': float(item_data.get('Price', 0)),
                    'brand': item_data.get('Brand', 'Unknown')
                })
            else:
                enriched.append({
                    'item_id': item_id,
                    'score': item.get('score', 0),
                    'category': 'Unknown',
                    'price': 0,
                    'brand': 'Unknown'
                })
                
        except Exception as e:
            enriched.append({
                'item_id': item_id,
                'score': item.get('score', 0),
                'error': str(e)
            })
    
    return enriched

def get_fallback_recommendations(num_results):
    """Get fallback recommendations"""
    items_table = dynamodb.Table(os.environ['ITEMS_TABLE'])
    
    try:
        response = items_table.scan(Limit=num_results)
        items = response.get('Items', [])
        
        fallback = []
        for item in items:
            fallback.append({
                'item_id': item['ItemId'],
                'score': 0.5,
                'category': item.get('Category', 'Unknown'),
                'price': float(item.get('Price', 0)),
                'brand': item.get('Brand', 'Unknown')
            })
        
        return fallback
        
    except Exception:
        return []

def track_recommendation_request(user_id, model_config, recommendations):
    """Track recommendation serving for analytics"""
    events_table = dynamodb.Table(os.environ['EVENTS_TABLE'])
    
    try:
        events_table.put_item(
            Item={
                'UserId': user_id,
                'Timestamp': int(datetime.now().timestamp() * 1000),
                'EventType': 'recommendation_served',
                'Algorithm': model_config.get('description', 'Unknown'),
                'ItemCount': len(recommendations),
                'Items': json.dumps([r['item_id'] for r in recommendations])
            }
        )
    except Exception as e:
        print(f"Failed to track recommendation request: {str(e)}")
'''

    def _get_event_tracker_code(self) -> str:
        """Return event tracker Lambda function code"""
        return '''
import json
import boto3
import os
from datetime import datetime

personalize_events = boto3.client('personalize-events')
dynamodb = boto3.resource('dynamodb')
kinesis = boto3.client('kinesis')

def lambda_handler(event, context):
    """Track user interaction events"""
    try:
        body = json.loads(event.get('body', '{}'))
        user_id = body.get('user_id')
        session_id = body.get('session_id', user_id)
        event_type = body.get('event_type')
        item_id = body.get('item_id')
        recommendation_id = body.get('recommendation_id')
        properties = body.get('properties', {})
        
        if not all([user_id, event_type]):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'user_id and event_type are required'})
            }
        
        # Store event in DynamoDB for analytics
        store_event_analytics(body)
        
        # Send event to Kinesis for real-time processing
        send_to_kinesis(body)
        
        # Send event to Personalize (if real-time tracking is enabled)
        if os.environ.get('EVENT_TRACKER_ARN') and item_id:
            send_to_personalize(user_id, session_id, event_type, item_id, properties)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'message': 'Event tracked successfully'})
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def store_event_analytics(event_data):
    """Store detailed event for analytics"""
    events_table = dynamodb.Table(os.environ['EVENTS_TABLE'])
    
    events_table.put_item(
        Item={
            'UserId': event_data['user_id'],
            'Timestamp': int(datetime.now().timestamp() * 1000),
            'EventType': event_data['event_type'],
            'ItemId': event_data.get('item_id', ''),
            'SessionId': event_data.get('session_id', ''),
            'RecommendationId': event_data.get('recommendation_id', ''),
            'Properties': json.dumps(event_data.get('properties', {})),
            'TTL': int(datetime.now().timestamp()) + (90 * 24 * 60 * 60)  # 90 days TTL
        }
    )

def send_to_kinesis(event_data):
    """Send event to Kinesis for real-time analytics"""
    try:
        kinesis.put_record(
            StreamName=os.environ['ANALYTICS_STREAM'],
            Data=json.dumps({
                **event_data,
                'timestamp': datetime.now().isoformat()
            }),
            PartitionKey=event_data['user_id']
        )
    except Exception as e:
        print(f"Failed to send to Kinesis: {str(e)}")

def send_to_personalize(user_id, session_id, event_type, item_id, properties):
    """Send event to Personalize for model training"""
    event_tracker_arn = os.environ['EVENT_TRACKER_ARN']
    
    personalize_event = {
        'userId': user_id,
        'sessionId': session_id,
        'eventType': event_type,
        'sentAt': datetime.now().timestamp()
    }
    
    if item_id:
        personalize_event['itemId'] = item_id
    
    if properties:
        personalize_event['properties'] = json.dumps(properties)
    
    try:
        personalize_events.put_events(
            trackingId=event_tracker_arn.split('/')[-1],
            userId=user_id,
            sessionId=session_id,
            eventList=[personalize_event]
        )
    except Exception as e:
        print(f"Failed to send to Personalize: {str(e)}")
'''

    def _get_personalize_manager_code(self) -> str:
        """Return Personalize manager Lambda function code"""
        return '''
import json
import boto3
import os
from datetime import datetime

personalize = boto3.client('personalize')

def lambda_handler(event, context):
    """Manage Personalize resources"""
    action = event.get('action')
    
    try:
        if action == 'create_dataset_group':
            return create_dataset_group(event)
        elif action == 'import_data':
            return import_data(event)
        elif action == 'create_solution':
            return create_solution(event)
        elif action == 'create_campaign':
            return create_campaign(event)
        elif action == 'check_status':
            return check_status(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_dataset_group(event):
    """Create Personalize dataset group"""
    dataset_group_name = event['dataset_group_name']
    
    response = personalize.create_dataset_group(
        name=dataset_group_name,
        domain='ECOMMERCE'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'dataset_group_arn': response['datasetGroupArn']
        })
    }

def import_data(event):
    """Import data into Personalize dataset"""
    dataset_arn = event['dataset_arn']
    job_name = event['job_name']
    s3_data_source = event['s3_data_source']
    role_arn = event['role_arn']
    
    response = personalize.create_dataset_import_job(
        jobName=job_name,
        datasetArn=dataset_arn,
        dataSource={
            's3DataSource': {
                'path': s3_data_source
            }
        },
        roleArn=role_arn
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'dataset_import_job_arn': response['datasetImportJobArn']
        })
    }

def create_solution(event):
    """Create Personalize solution"""
    solution_name = event['solution_name']
    dataset_group_arn = event['dataset_group_arn']
    recipe_arn = event['recipe_arn']
    
    response = personalize.create_solution(
        name=solution_name,
        datasetGroupArn=dataset_group_arn,
        recipeArn=recipe_arn
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'solution_arn': response['solutionArn']
        })
    }

def create_campaign(event):
    """Create Personalize campaign"""
    campaign_name = event['campaign_name']
    solution_version_arn = event['solution_version_arn']
    min_provisioned_tps = event.get('min_provisioned_tps', 1)
    
    response = personalize.create_campaign(
        name=campaign_name,
        solutionVersionArn=solution_version_arn,
        minProvisionedTPS=min_provisioned_tps
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'campaign_arn': response['campaignArn']
        })
    }

def check_status(event):
    """Check status of Personalize resources"""
    resource_arn = event['resource_arn']
    resource_type = event['resource_type']
    
    if resource_type == 'solution':
        response = personalize.describe_solution(solutionArn=resource_arn)
        status = response['solution']['status']
    elif resource_type == 'campaign':
        response = personalize.describe_campaign(campaignArn=resource_arn)
        status = response['campaign']['status']
    elif resource_type == 'dataset_import_job':
        response = personalize.describe_dataset_import_job(datasetImportJobArn=resource_arn)
        status = response['datasetImportJob']['status']
    else:
        raise ValueError(f"Unknown resource type: {resource_type}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'resource_arn': resource_arn,
            'status': status,
            'is_complete': status in ['ACTIVE', 'CREATE FAILED']
        })
    }
'''

    def _get_analytics_code(self) -> str:
        """Return analytics processor Lambda function code"""
        return '''
import json
import boto3
import os
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Process analytics events from Kinesis"""
    try:
        for record in event['Records']:
            # Decode Kinesis record
            payload = json.loads(record['kinesis']['data'])
            
            # Process the event
            process_analytics_event(payload)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Analytics processed successfully'})
        }
        
    except Exception as e:
        print(f"Error processing analytics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_analytics_event(event_data):
    """Process individual analytics event"""
    try:
        # Extract metrics from event
        user_id = event_data.get('user_id')
        event_type = event_data.get('event_type')
        item_id = event_data.get('item_id')
        timestamp = event_data.get('timestamp')
        
        # Send custom metrics to CloudWatch
        if event_type:
            cloudwatch.put_metric_data(
                Namespace='PersonalizeAB/Events',
                MetricData=[
                    {
                        'MetricName': f'{event_type}_count',
                        'Value': 1,
                        'Unit': 'Count',
                        'Timestamp': datetime.now(),
                        'Dimensions': [
                            {
                                'Name': 'EventType',
                                'Value': event_type
                            }
                        ]
                    }
                ]
            )
        
        # Track user engagement metrics
        if user_id:
            cloudwatch.put_metric_data(
                Namespace='PersonalizeAB/Users',
                MetricData=[
                    {
                        'MetricName': 'active_users',
                        'Value': 1,
                        'Unit': 'Count',
                        'Timestamp': datetime.now(),
                        'Dimensions': [
                            {
                                'Name': 'UserId',
                                'Value': user_id
                            }
                        ]
                    }
                ]
            )
    
    except Exception as e:
        print(f"Error processing event: {str(e)}")
'''


def main():
    """Main application entry point"""
    app = cdk.App()
    
    # Get stack name from context or use default
    stack_name = app.node.try_get_context("stack_name") or "PersonalizeRecommendationStack"
    
    # Create the stack
    PersonalizeRecommendationStack(
        app, 
        stack_name,
        description="Real-Time Recommendations with Amazon Personalize and A/B Testing",
        env=cdk.Environment(
            account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
            region=os.environ.get('CDK_DEFAULT_REGION')
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()