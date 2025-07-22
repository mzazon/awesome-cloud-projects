#!/usr/bin/env python3
"""
CDK Python Application for Savings Plans Recommendations with Cost Explorer

This application creates infrastructure to automatically analyze AWS spending patterns
and generate personalized Savings Plans recommendations using Cost Explorer APIs.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_s3 as s3,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
)
from constructs import Construct
import json


class SavingsPlansRecommendationStack(Stack):
    """
    CDK Stack for automated Savings Plans recommendations analysis.
    
    This stack creates:
    - S3 bucket for storing recommendations reports
    - Lambda function for Cost Explorer analysis
    - IAM role with necessary permissions
    - EventBridge rule for automated monthly analysis
    - CloudWatch dashboard for monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get account ID and region for resource naming
        account_id = self.account
        region = self.region

        # Create S3 bucket for storing recommendations
        self.recommendations_bucket = s3.Bucket(
            self,
            "RecommendationsBucket",
            bucket_name=f"cost-recommendations-{account_id}-{construct_id.lower()}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldRecommendations",
                    enabled=True,
                    expiration=Duration.days(365),  # Keep recommendations for 1 year
                    noncurrent_version_expiration=Duration.days(90),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create IAM role for Lambda function
        self.lambda_role = iam.Role(
            self,
            "SavingsPlansAnalyzerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "CostExplorerAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ce:GetSavingsPlansPurchaseRecommendation",
                                "ce:StartSavingsPlansPurchaseRecommendationGeneration",
                                "ce:GetCostAndUsage",
                                "ce:GetDimensionValues",
                                "ce:GetUsageReport",
                                "savingsplans:DescribeSavingsPlans",
                                "savingsplans:DescribeSavingsPlansOfferings",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:GetObject",
                            ],
                            resources=[
                                self.recommendations_bucket.bucket_arn,
                                f"{self.recommendations_bucket.bucket_arn}/*",
                            ],
                        ),
                    ]
                )
            },
        )

        # Create Lambda function for savings plans analysis
        self.analyzer_function = _lambda.Function(
            self,
            "SavingsPlansAnalyzer",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "BUCKET_NAME": self.recommendations_bucket.bucket_name,
                "REGION": region,
            },
            description="Analyzes AWS usage patterns and generates Savings Plans recommendations",
        )

        # Create CloudWatch Log Group with retention policy
        self.log_group = logs.LogGroup(
            self,
            "AnalyzerLogGroup",
            log_group_name=f"/aws/lambda/{self.analyzer_function.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create EventBridge rule for monthly analysis
        self.monthly_analysis_rule = events.Rule(
            self,
            "MonthlyAnalysisRule",
            schedule=events.Schedule.rate(Duration.days(30)),
            description="Triggers monthly Savings Plans analysis",
        )

        # Add Lambda function as target for EventBridge rule
        self.monthly_analysis_rule.add_target(
            targets.LambdaFunction(
                self.analyzer_function,
                event=events.RuleTargetInput.from_object({
                    "lookback_days": "SIXTY_DAYS",
                    "term_years": "ONE_YEAR",
                    "payment_option": "NO_UPFRONT",
                    "bucket_name": self.recommendations_bucket.bucket_name,
                }),
            )
        )

        # Create CloudWatch Dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "SavingsPlansRecommendationsDashboard",
            dashboard_name="SavingsPlansRecommendations",
        )

        # Add Lambda metrics to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Performance",
                left=[
                    self.analyzer_function.metric_duration(
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                    self.analyzer_function.metric_invocations(
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    self.analyzer_function.metric_errors(
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
                width=12,
            ),
            cloudwatch.LogQueryWidget(
                title="Recent Analysis Logs",
                log_groups=[self.log_group],
                query_lines=[
                    "fields @timestamp, @message",
                    "sort @timestamp desc",
                    "limit 50",
                ],
                width=12,
            ),
        )

        # Create outputs
        CfnOutput(
            self,
            "RecommendationsBucketName",
            value=self.recommendations_bucket.bucket_name,
            description="S3 bucket name for storing recommendations",
        )

        CfnOutput(
            self,
            "AnalyzerFunctionName",
            value=self.analyzer_function.function_name,
            description="Lambda function name for manual invocation",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for monitoring",
        )

        CfnOutput(
            self,
            "MonthlyAnalysisRuleName",
            value=self.monthly_analysis_rule.rule_name,
            description="EventBridge rule name for monthly analysis",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code for Savings Plans analysis.
        
        Returns:
            str: Complete Lambda function code as a string
        """
        return '''
import json
import boto3
import datetime
import os
import logging
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for analyzing Savings Plans recommendations.
    
    Args:
        event: Lambda event containing analysis parameters
        context: Lambda context object
        
    Returns:
        Dict containing analysis results and S3 report location
    """
    try:
        # Initialize AWS clients
        ce_client = boto3.client('ce')
        s3_client = boto3.client('s3')
        
        # Get configuration from environment and event
        bucket_name = os.environ.get('BUCKET_NAME')
        region = os.environ.get('REGION')
        
        # Define analysis parameters with defaults
        lookback_days = event.get('lookback_days', 'SIXTY_DAYS')
        term_years = event.get('term_years', 'ONE_YEAR')
        payment_option = event.get('payment_option', 'NO_UPFRONT')
        
        logger.info(f"Starting analysis with parameters: lookback={lookback_days}, term={term_years}, payment={payment_option}")
        
        # Initialize results structure
        results = {
            'analysis_date': datetime.datetime.now().isoformat(),
            'parameters': {
                'lookback_days': lookback_days,
                'term_years': term_years,
                'payment_option': payment_option,
                'region': region
            },
            'recommendations': [],
            'current_savings_plans': []
        }
        
        # Get current Savings Plans commitments
        try:
            sp_client = boto3.client('savingsplans')
            current_plans = sp_client.describe_savings_plans(states=['Active'])
            
            for plan in current_plans.get('SavingsPlans', []):
                results['current_savings_plans'].append({
                    'savings_plan_id': plan.get('SavingsPlanId'),
                    'savings_plan_type': plan.get('SavingsPlanType'),
                    'state': plan.get('State'),
                    'commitment': plan.get('Commitment'),
                    'currency': plan.get('Currency'),
                    'start_date': plan.get('Start', '').isoformat() if plan.get('Start') else None,
                    'end_date': plan.get('End', '').isoformat() if plan.get('End') else None
                })
                
        except Exception as e:
            logger.warning(f"Error retrieving current Savings Plans: {str(e)}")
        
        # Analyze different Savings Plans types
        sp_types = ['COMPUTE_SP', 'EC2_INSTANCE_SP', 'SAGEMAKER_SP']
        
        for sp_type in sp_types:
            try:
                logger.info(f"Analyzing {sp_type} recommendations...")
                
                # Get Savings Plans recommendations
                response = ce_client.get_savings_plans_purchase_recommendation(
                    SavingsPlansType=sp_type,
                    TermInYears=term_years,
                    PaymentOption=payment_option,
                    LookbackPeriodInDays=lookback_days,
                    PageSize=10
                )
                
                # Process recommendation data
                if 'SavingsPlansPurchaseRecommendation' in response:
                    rec = response['SavingsPlansPurchaseRecommendation']
                    summary = rec.get('SavingsPlansPurchaseRecommendationSummary', {})
                    
                    recommendation = {
                        'savings_plan_type': sp_type,
                        'summary': {
                            'estimated_monthly_savings': summary.get('EstimatedMonthlySavingsAmount', '0'),
                            'estimated_roi': summary.get('EstimatedROI', '0'),
                            'estimated_savings_percentage': summary.get('EstimatedSavingsPercentage', '0'),
                            'hourly_commitment': summary.get('HourlyCommitmentToPurchase', '0'),
                            'total_recommendations': summary.get('TotalRecommendationCount', '0')
                        },
                        'details': []
                    }
                    
                    # Add detailed recommendations
                    for detail in rec.get('SavingsPlansPurchaseRecommendationDetails', []):
                        recommendation['details'].append({
                            'account_id': detail.get('AccountId', ''),
                            'currency_code': detail.get('CurrencyCode', 'USD'),
                            'estimated_monthly_savings': detail.get('EstimatedMonthlySavingsAmount', '0'),
                            'estimated_roi': detail.get('EstimatedROI', '0'),
                            'hourly_commitment': detail.get('HourlyCommitmentToPurchase', '0'),
                            'upfront_cost': detail.get('UpfrontCost', '0'),
                            'savings_plans_details': detail.get('SavingsPlansDetails', {})
                        })
                    
                    results['recommendations'].append(recommendation)
                    logger.info(f"Found {len(recommendation['details'])} recommendations for {sp_type}")
                
            except Exception as e:
                logger.error(f"Error analyzing {sp_type}: {str(e)}")
                results['recommendations'].append({
                    'savings_plan_type': sp_type,
                    'error': str(e)
                })
        
        # Calculate total potential savings
        total_monthly_savings = 0
        for rec in results['recommendations']:
            if 'error' not in rec:
                try:
                    savings = float(rec['summary']['estimated_monthly_savings'])
                    total_monthly_savings += savings
                except (ValueError, KeyError):
                    pass
        
        results['total_monthly_savings'] = total_monthly_savings
        results['annual_savings_potential'] = total_monthly_savings * 12
        
        # Save results to S3
        if bucket_name:
            timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
            key = f"savings-plans-recommendations/{timestamp}.json"
            
            s3_client.put_object(
                Bucket=bucket_name,
                Key=key,
                Body=json.dumps(results, indent=2, default=str),
                ContentType='application/json'
            )
            
            results['report_location'] = f"s3://{bucket_name}/{key}"
            logger.info(f"Report saved to {results['report_location']}")
        
        logger.info(f"Analysis complete. Total monthly savings potential: ${total_monthly_savings}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, indent=2, default=str)
        }
        
    except Exception as e:
        logger.error(f"Lambda execution failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'analysis_date': datetime.datetime.now().isoformat()
            })
        }
'''


class SavingsPlansRecommendationApp(cdk.App):
    """
    CDK Application for Savings Plans Recommendations.
    
    This application creates the complete infrastructure needed for
    automated Savings Plans analysis using Cost Explorer APIs.
    """

    def __init__(self):
        super().__init__()

        # Create the main stack
        SavingsPlansRecommendationStack(
            self,
            "SavingsPlansRecommendationStack",
            description="Infrastructure for automated Savings Plans recommendations using Cost Explorer",
            tags={
                "Project": "SavingsPlansRecommendations",
                "Environment": "production",
                "Owner": "cost-optimization-team",
            },
        )


# Entry point for CDK application
if __name__ == "__main__":
    app = SavingsPlansRecommendationApp()
    app.synth()