#!/usr/bin/env python3
"""
Multi-Region Active-Active Applications with AWS Global Accelerator
CDK Python implementation for deploying a globally distributed application
with DynamoDB Global Tables, Lambda functions, and Application Load Balancers.
"""

import os
from typing import Dict, List, Optional
import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
)
from aws_cdk import aws_dynamodb as dynamodb
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_elasticloadbalancingv2 as elbv2
from aws_cdk import aws_elasticloadbalancingv2_targets as targets
from aws_cdk import aws_globalaccelerator as globalaccelerator
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as _lambda
from constructs import Construct


class GlobalAcceleratorAppStack(Stack):
    """
    Main stack for multi-region active-active application with Global Accelerator.
    
    This stack creates:
    - DynamoDB Global Tables for data consistency
    - Lambda functions for serverless compute
    - Application Load Balancers for regional endpoints
    - AWS Global Accelerator for intelligent traffic routing
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        region_config: Dict[str, str],
        is_primary_region: bool = False,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration variables
        self.region_config = region_config
        self.is_primary_region = is_primary_region
        self.app_name = "global-app"
        self.table_name = f"GlobalUserData-{region_config['region_suffix']}"
        
        # Tags for all resources
        self.common_tags = {
            "Application": "GlobalActiveActiveApp",
            "Environment": "production",
            "Region": region_config["region_name"],
            "ManagedBy": "CDK"
        }

        # Create resources
        self.lambda_role = self._create_lambda_execution_role()
        self.dynamodb_table = self._create_dynamodb_table()
        self.vpc = self._get_default_vpc()
        self.lambda_function = self._create_lambda_function()
        self.alb = self._create_application_load_balancer()
        self.target_group = self._create_target_group()
        self._configure_alb_listener()
        
        # Create Global Accelerator only in primary region
        if self.is_primary_region:
            self.global_accelerator = self._create_global_accelerator()

        # Add outputs
        self._create_outputs()

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda function with DynamoDB permissions."""
        
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Global App Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add DynamoDB permissions for Global Tables
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                ],
                resources=[
                    f"arn:aws:dynamodb:*:{self.account}:table/{self.table_name}",
                    f"arn:aws:dynamodb:*:{self.account}:table/{self.table_name}/*",
                ],
            )
        )

        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["arn:aws:logs:*:*:*"],
            )
        )

        # Apply tags
        for key, value in self.common_tags.items():
            cdk.Tags.of(role).add(key, value)

        return role

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """Create DynamoDB table with Global Tables configuration."""
        
        table = dynamodb.Table(
            self,
            "GlobalUserDataTable",
            table_name=self.table_name,
            partition_key=dynamodb.Attribute(
                name="userId", type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp", type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            point_in_time_recovery=True,
            # Enable Global Tables replication
            replication_regions=self._get_replication_regions(),
        )

        # Apply tags
        for key, value in self.common_tags.items():
            cdk.Tags.of(table).add(key, value)

        return table

    def _get_replication_regions(self) -> List[str]:
        """Get list of regions for DynamoDB Global Tables replication."""
        # Define all regions for Global Tables
        # Note: In production, you might want to make this configurable
        regions = ["us-east-1", "eu-west-1", "ap-southeast-1"]
        
        # Remove current region from replication list
        current_region = self.region
        if current_region in regions:
            regions.remove(current_region)
            
        return regions

    def _get_default_vpc(self) -> ec2.IVpc:
        """Get the default VPC for the region."""
        return ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)

    def _create_lambda_function(self) -> _lambda.Function:
        """Create Lambda function for the application backend."""
        
        # Lambda function code
        lambda_code = '''
import json
import boto3
import time
import os
from decimal import Decimal

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table_name = os.environ['TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    """
    Multi-region active-active application handler
    Supports CRUD operations with automatic regional optimization
    """
    
    try:
        # Get HTTP method and path
        method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        
        # Parse request body for POST/PUT requests
        body = {}
        if event.get('body'):
            body = json.loads(event['body'])
        
        # Get AWS region from context
        region = context.invoked_function_arn.split(':')[3]
        
        # Route based on HTTP method and path
        if method == 'GET' and path == '/health':
            return health_check(region)
        elif method == 'GET' and path.startswith('/user/'):
            user_id = path.split('/')[-1]
            return get_user_data(user_id, region)
        elif method == 'POST' and path == '/user':
            return create_user_data(body, region)
        elif method == 'PUT' and path.startswith('/user/'):
            user_id = path.split('/')[-1]
            return update_user_data(user_id, body, region)
        elif method == 'GET' and path == '/users':
            return list_users(region)
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Not found'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e), 'region': region})
        }

def health_check(region):
    """Health check endpoint for load balancer"""
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'status': 'healthy',
            'region': region,
            'timestamp': int(time.time())
        })
    }

def get_user_data(user_id, region):
    """Get user data with regional context"""
    try:
        # Get latest record for user
        response = table.query(
            KeyConditionExpression='userId = :userId',
            ExpressionAttributeValues={':userId': user_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        if response['Items']:
            item = response['Items'][0]
            # Convert Decimal to float for JSON serialization
            item = json.loads(json.dumps(item, default=decimal_default))
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'user': item,
                    'served_from_region': region
                })
            }
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'User not found'})
            }
            
    except Exception as e:
        raise Exception(f"Error getting user data: {str(e)}")

def create_user_data(body, region):
    """Create new user data with regional tracking"""
    try:
        user_id = body.get('userId')
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'userId is required'})
            }
        
        timestamp = int(time.time() * 1000)  # milliseconds for better precision
        
        item = {
            'userId': user_id,
            'timestamp': timestamp,
            'data': body.get('data', {}),
            'created_region': region,
            'last_updated': timestamp,
            'version': 1
        }
        
        table.put_item(Item=item)
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'User created successfully',
                'userId': user_id,
                'created_in_region': region,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        raise Exception(f"Error creating user data: {str(e)}")

def update_user_data(user_id, body, region):
    """Update user data with conflict resolution"""
    try:
        timestamp = int(time.time() * 1000)
        
        # Use atomic update with version control
        response = table.update_item(
            Key={'userId': user_id, 'timestamp': timestamp},
            UpdateExpression='SET #data = :data, last_updated = :timestamp, updated_region = :region ADD version :inc',
            ExpressionAttributeNames={'#data': 'data'},
            ExpressionAttributeValues={
                ':data': body.get('data', {}),
                ':timestamp': timestamp,
                ':region': region,
                ':inc': 1
            },
            ReturnValues='ALL_NEW'
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'User updated successfully',
                'userId': user_id,
                'updated_in_region': region,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        raise Exception(f"Error updating user data: {str(e)}")

def list_users(region):
    """List users with pagination support"""
    try:
        # Simple scan with limit (in production, use GSI for better performance)
        response = table.scan(Limit=20)
        
        users = []
        processed_users = set()
        
        for item in response['Items']:
            user_id = item['userId']
            if user_id not in processed_users:
                users.append({
                    'userId': user_id,
                    'last_updated': int(item['last_updated']),
                    'version': int(item.get('version', 1))
                })
                processed_users.add(user_id)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'users': users,
                'count': len(users),
                'served_from_region': region
            })
        }
        
    except Exception as e:
        raise Exception(f"Error listing users: {str(e)}")

def decimal_default(obj):
    """JSON serializer for objects not serializable by default json code"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
'''

        function = _lambda.Function(
            self,
            "GlobalAppFunction",
            function_name=f"{self.app_name}-{self.region_config['region_suffix']}",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "TABLE_NAME": self.table_name,
                "REGION": self.region,
            },
            description=f"Global App Lambda function for {self.region_config['region_name']}",
        )

        # Apply tags
        for key, value in self.common_tags.items():
            cdk.Tags.of(function).add(key, value)

        return function

    def _create_application_load_balancer(self) -> elbv2.ApplicationLoadBalancer:
        """Create Application Load Balancer for the regional endpoint."""
        
        alb = elbv2.ApplicationLoadBalancer(
            self,
            "GlobalAppALB",
            load_balancer_name=f"{self.app_name}-{self.region_config['region_suffix']}-alb",
            vpc=self.vpc,
            internet_facing=True,
            scheme=elbv2.ApplicationLoadBalancerScheme.INTERNET_FACING,
        )

        # Apply tags
        for key, value in self.common_tags.items():
            cdk.Tags.of(alb).add(key, value)

        return alb

    def _create_target_group(self) -> elbv2.ApplicationTargetGroup:
        """Create target group for Lambda function."""
        
        target_group = elbv2.ApplicationTargetGroup(
            self,
            "GlobalAppTargetGroup",
            target_group_name=f"{self.app_name}-{self.region_config['region_suffix']}-tg",
            targets=[targets.LambdaTarget(self.lambda_function)],
            target_type=elbv2.TargetType.LAMBDA,
            health_check=elbv2.HealthCheck(
                enabled=True,
                path="/health",
                healthy_threshold_count=3,
                unhealthy_threshold_count=3,
                timeout=Duration.seconds(5),
                interval=Duration.seconds(30),
                healthy_http_codes="200",
            ),
        )

        # Apply tags
        for key, value in self.common_tags.items():
            cdk.Tags.of(target_group).add(key, value)

        return target_group

    def _configure_alb_listener(self) -> None:
        """Configure ALB listener to route traffic to Lambda target group."""
        
        elbv2.ApplicationListener(
            self,
            "GlobalAppListener",
            load_balancer=self.alb,
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_action=elbv2.ListenerAction.forward([self.target_group]),
        )

    def _create_global_accelerator(self) -> globalaccelerator.Accelerator:
        """
        Create AWS Global Accelerator (only in primary region).
        
        Note: Global Accelerator is a global service, so it should only be created once,
        typically in the primary region.
        """
        
        accelerator = globalaccelerator.Accelerator(
            self,
            "GlobalAccelerator",
            accelerator_name=f"GlobalAccelerator-{self.app_name}",
            enabled=True,
        )

        # Create listener for HTTP traffic
        listener = globalaccelerator.Listener(
            self,
            "GlobalAcceleratorListener",
            accelerator=accelerator,
            port_ranges=[
                globalaccelerator.PortRange(from_port=80, to_port=80)
            ],
            protocol=globalaccelerator.ConnectionProtocol.TCP,
        )

        # Note: Endpoint groups need to be added separately for each region
        # This would typically be done through cross-stack references or
        # separate stacks for each region

        # Apply tags
        for key, value in self.common_tags.items():
            cdk.Tags.of(accelerator).add(key, value)

        return accelerator

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.dynamodb_table.table_name,
            description="DynamoDB table name for user data",
            export_name=f"{self.stack_name}-DynamoDBTableName",
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="Lambda function ARN",
            export_name=f"{self.stack_name}-LambdaFunctionArn",
        )

        CfnOutput(
            self,
            "ALBArn",
            value=self.alb.load_balancer_arn,
            description="Application Load Balancer ARN",
            export_name=f"{self.stack_name}-ALBArn",
        )

        CfnOutput(
            self,
            "ALBDNSName",
            value=self.alb.load_balancer_dns_name,
            description="Application Load Balancer DNS name",
            export_name=f"{self.stack_name}-ALBDNSName",
        )

        CfnOutput(
            self,
            "TargetGroupArn",
            value=self.target_group.target_group_arn,
            description="Target Group ARN",
            export_name=f"{self.stack_name}-TargetGroupArn",
        )

        if self.is_primary_region and hasattr(self, 'global_accelerator'):
            CfnOutput(
                self,
                "GlobalAcceleratorArn",
                value=self.global_accelerator.accelerator_arn,
                description="Global Accelerator ARN",
                export_name=f"{self.stack_name}-GlobalAcceleratorArn",
            )

            CfnOutput(
                self,
                "GlobalAcceleratorDNS",
                value=self.global_accelerator.accelerator_dns_name,
                description="Global Accelerator DNS name",
                export_name=f"{self.stack_name}-GlobalAcceleratorDNS",
            )


def main():
    """Main function to create and deploy the CDK application."""
    
    app = App()

    # Configuration for each region
    regions_config = {
        "us-east-1": {
            "region_name": "US East (N. Virginia)",
            "region_suffix": "us",
            "is_primary": True,
        },
        "eu-west-1": {
            "region_name": "Europe (Ireland)",
            "region_suffix": "eu",
            "is_primary": False,
        },
        "ap-southeast-1": {
            "region_name": "Asia Pacific (Singapore)",
            "region_suffix": "asia",
            "is_primary": False,
        },
    }

    # Create stacks for each region
    for region, config in regions_config.items():
        stack_name = f"GlobalAcceleratorApp-{config['region_suffix']}"
        
        GlobalAcceleratorAppStack(
            app,
            stack_name,
            region_config=config,
            is_primary_region=config["is_primary"],
            env=Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=region,
            ),
            description=f"Multi-region active-active application stack for {config['region_name']}",
        )

    # Add global tags to the entire app
    cdk.Tags.of(app).add("Project", "GlobalAcceleratorApp")
    cdk.Tags.of(app).add("Owner", "DevOps Team")
    cdk.Tags.of(app).add("CostCenter", "Engineering")

    app.synth()


if __name__ == "__main__":
    main()