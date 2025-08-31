#!/usr/bin/env python3
"""
AWS Service Catalog Portfolio with CloudFormation Templates

This CDK application deploys a Service Catalog portfolio with standardized
CloudFormation templates for S3 buckets and Lambda functions, providing
governed self-service infrastructure deployment capabilities.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_servicecatalog as servicecatalog,
    aws_s3 as s3,
    aws_iam as iam,
    aws_s3_deployment as s3deploy,
    RemovalPolicy,
    CfnOutput,
    Duration,
)
from constructs import Construct
import json
from typing import Dict, Any


class ServiceCatalogPortfolioStack(Stack):
    """
    CDK Stack that creates a Service Catalog portfolio with CloudFormation
    template products for standardized S3 bucket and Lambda function deployment.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Create S3 bucket for CloudFormation templates
        template_bucket = s3.Bucket(
            self, "TemplateBucket",
            bucket_name=f"service-catalog-templates-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Deploy CloudFormation templates to S3
        self._deploy_templates(template_bucket, unique_suffix)

        # Create Service Catalog portfolio
        portfolio = servicecatalog.Portfolio(
            self, "Portfolio",
            display_name=f"enterprise-infrastructure-{unique_suffix}",
            description="Enterprise infrastructure templates for development teams",
            provider_name="IT Infrastructure Team",
        )

        # Create IAM role for launch constraints
        launch_role = self._create_launch_role(unique_suffix)

        # Create Service Catalog products
        s3_product = self._create_s3_product(template_bucket, unique_suffix)
        lambda_product = self._create_lambda_product(template_bucket, unique_suffix)

        # Add products to portfolio
        portfolio.add_product(s3_product)
        portfolio.add_product(lambda_product)

        # Apply launch constraints
        servicecatalog.CfnLaunchRoleConstraint(
            self, "S3LaunchConstraint",
            portfolio_id=portfolio.portfolio_id,
            product_id=s3_product.product_id,
            role_arn=launch_role.role_arn,
        )

        servicecatalog.CfnLaunchRoleConstraint(
            self, "LambdaLaunchConstraint",
            portfolio_id=portfolio.portfolio_id,
            product_id=lambda_product.product_id,
            role_arn=launch_role.role_arn,
        )

        # Grant portfolio access to current user/role
        self._grant_portfolio_access(portfolio)

        # Outputs
        CfnOutput(
            self, "PortfolioId",
            value=portfolio.portfolio_id,
            description="Service Catalog Portfolio ID",
        )

        CfnOutput(
            self, "PortfolioName",
            value=portfolio.display_name,
            description="Service Catalog Portfolio Name",
        )

        CfnOutput(
            self, "S3ProductId",
            value=s3_product.product_id,
            description="S3 Bucket Product ID",
        )

        CfnOutput(
            self, "LambdaProductId",
            value=lambda_product.product_id,
            description="Lambda Function Product ID",
        )

        CfnOutput(
            self, "LaunchRoleArn",
            value=launch_role.role_arn,
            description="Launch Role ARN for Service Catalog constraints",
        )

        CfnOutput(
            self, "TemplateBucketName",
            value=template_bucket.bucket_name,
            description="S3 bucket containing CloudFormation templates",
        )

    def _deploy_templates(self, bucket: s3.Bucket, suffix: str) -> None:
        """
        Deploy CloudFormation templates to S3 bucket for Service Catalog products.
        
        Args:
            bucket: S3 bucket to store templates
            suffix: Unique suffix for resource naming
        """
        # S3 Bucket CloudFormation Template
        s3_template = self._get_s3_template()
        
        # Lambda Function CloudFormation Template
        lambda_template = self._get_lambda_template()

        # Deploy templates to S3
        s3deploy.BucketDeployment(
            self, "TemplateDeployment",
            sources=[
                s3deploy.Source.data("s3-bucket-template.yaml", s3_template),
                s3deploy.Source.data("lambda-function-template.yaml", lambda_template),
            ],
            destination_bucket=bucket,
        )

    def _create_launch_role(self, suffix: str) -> iam.Role:
        """
        Create IAM role for Service Catalog launch constraints.
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            IAM role for launch constraints
        """
        launch_role = iam.Role(
            self, "LaunchRole",
            role_name=f"ServiceCatalogLaunchRole-{suffix}",
            assumed_by=iam.ServicePrincipal("servicecatalog.amazonaws.com"),
            description="IAM role for Service Catalog product launch constraints",
        )

        # Create inline policy with necessary permissions
        launch_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:CreateBucket",
                        "s3:DeleteBucket",
                        "s3:PutBucketEncryption",
                        "s3:PutBucketVersioning",
                        "s3:PutBucketPublicAccessBlock",
                        "s3:PutBucketTagging",
                        "s3:GetBucketLocation",
                        "s3:ListBucket",
                        "lambda:CreateFunction",
                        "lambda:DeleteFunction",
                        "lambda:UpdateFunctionCode",
                        "lambda:UpdateFunctionConfiguration",
                        "lambda:TagResource",
                        "lambda:UntagResource",
                        "lambda:GetFunction",
                        "lambda:ListTags",
                        "iam:CreateRole",
                        "iam:DeleteRole",
                        "iam:AttachRolePolicy",
                        "iam:DetachRolePolicy",
                        "iam:PassRole",
                        "iam:TagRole",
                        "iam:UntagRole",
                        "iam:GetRole",
                        "iam:ListRolePolicies",
                        "iam:ListAttachedRolePolicies",
                    ],
                    resources=["*"],
                )
            ]
        )

        launch_role.attach_inline_policy(
            iam.Policy(
                self, "LaunchPolicy",
                document=launch_policy,
            )
        )

        return launch_role

    def _create_s3_product(self, bucket: s3.Bucket, suffix: str) -> servicecatalog.CloudFormationProduct:
        """
        Create Service Catalog product for S3 bucket deployment.
        
        Args:
            bucket: S3 bucket containing CloudFormation templates
            suffix: Unique suffix for resource naming
            
        Returns:
            Service Catalog CloudFormation product
        """
        return servicecatalog.CloudFormationProduct(
            self, "S3Product",
            product_name=f"managed-s3-bucket-{suffix}",
            description="Managed S3 bucket with security best practices",
            owner="IT Infrastructure Team",
            product_versions=[
                servicecatalog.CloudFormationProductVersion(
                    product_version_name="v1.0",
                    cloud_formation_template=servicecatalog.CloudFormationTemplate.from_url(
                        f"https://{bucket.bucket_name}.s3.{self.region}.amazonaws.com/s3-bucket-template.yaml"
                    ),
                    description="Initial version with encryption and versioning",
                )
            ],
        )

    def _create_lambda_product(self, bucket: s3.Bucket, suffix: str) -> servicecatalog.CloudFormationProduct:
        """
        Create Service Catalog product for Lambda function deployment.
        
        Args:
            bucket: S3 bucket containing CloudFormation templates
            suffix: Unique suffix for resource naming
            
        Returns:
            Service Catalog CloudFormation product
        """
        return servicecatalog.CloudFormationProduct(
            self, "LambdaProduct",
            product_name=f"serverless-function-{suffix}",
            description="Managed Lambda function with IAM role and logging",
            owner="IT Infrastructure Team",
            product_versions=[
                servicecatalog.CloudFormationProductVersion(
                    product_version_name="v1.0",
                    cloud_formation_template=servicecatalog.CloudFormationTemplate.from_url(
                        f"https://{bucket.bucket_name}.s3.{self.region}.amazonaws.com/lambda-function-template.yaml"
                    ),
                    description="Initial version with execution role",
                )
            ],
        )

    def _grant_portfolio_access(self, portfolio: servicecatalog.Portfolio) -> None:
        """
        Grant portfolio access to the current AWS account root.
        
        Args:
            portfolio: Service Catalog portfolio
        """
        # Grant access to the account root - in practice, you would grant access
        # to specific IAM users, groups, or roles
        servicecatalog.CfnPortfolioPrincipalAssociation(
            self, "PortfolioAccess",
            portfolio_id=portfolio.portfolio_id,
            principal_arn=f"arn:aws:iam::{self.account}:root",
            principal_type="IAM",
        )

    def _get_s3_template(self) -> str:
        """
        Get S3 bucket CloudFormation template content.
        
        Returns:
            CloudFormation template as YAML string
        """
        return """AWSTemplateFormatVersion: '2010-09-09'
Description: 'Managed S3 bucket with security best practices'

Parameters:
  BucketName:
    Type: String
    Description: 'Name for the S3 bucket'
    AllowedPattern: '^[a-z0-9][a-z0-9-]*[a-z0-9]$'
    ConstraintDescription: 'Bucket name must be lowercase alphanumeric with hyphens'

  Environment:
    Type: String
    Default: 'development'
    AllowedValues: ['development', 'staging', 'production']
    Description: 'Environment for resource tagging'

Resources:
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref BucketName
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      VersioningConfiguration:
        Status: Enabled
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

Outputs:
  BucketName:
    Description: 'Name of the created S3 bucket'
    Value: !Ref S3Bucket
  BucketArn:
    Description: 'ARN of the created S3 bucket'
    Value: !GetAtt S3Bucket.Arn"""

    def _get_lambda_template(self) -> str:
        """
        Get Lambda function CloudFormation template content.
        
        Returns:
            CloudFormation template as YAML string
        """
        return """AWSTemplateFormatVersion: '2010-09-09'
Description: 'Managed Lambda function with IAM role and CloudWatch logging'

Parameters:
  FunctionName:
    Type: String
    Description: 'Name for the Lambda function'
    AllowedPattern: '^[a-zA-Z0-9-_]+$'

  Runtime:
    Type: String
    Default: 'python3.12'
    AllowedValues: ['python3.12', 'python3.11', 'nodejs20.x', 'nodejs22.x']
    Description: 'Runtime environment for the function'

  Environment:
    Type: String
    Default: 'development'
    AllowedValues: ['development', 'staging', 'production']
    Description: 'Environment for resource tagging'

Resources:
  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

  LambdaFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Ref FunctionName
      Runtime: !Ref Runtime
      Handler: 'index.handler'
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          def handler(event, context):
              return {
                  'statusCode': 200,
                  'body': 'Hello from Service Catalog managed Lambda!'
              }
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

Outputs:
  FunctionName:
    Description: 'Name of the created Lambda function'
    Value: !Ref LambdaFunction
  FunctionArn:
    Description: 'ARN of the created Lambda function'
    Value: !GetAtt LambdaFunction.Arn"""


# CDK App
app = cdk.App()

# Create the Service Catalog Portfolio stack
ServiceCatalogPortfolioStack(
    app, "ServiceCatalogPortfolioStack",
    description="AWS Service Catalog Portfolio with CloudFormation Templates",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

app.synth()