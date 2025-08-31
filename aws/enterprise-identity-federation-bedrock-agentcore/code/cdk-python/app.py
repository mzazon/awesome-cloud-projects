#!/usr/bin/env python3
"""
Enterprise Identity Federation with Bedrock AgentCore CDK Application

This CDK application creates a comprehensive enterprise identity federation system
that integrates Bedrock AgentCore with Cognito User Pools for SAML federation
with corporate identity providers.

Author: AWS Solutions Architects
Version: 1.0
Last Updated: 2025-01-16
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_cognito as cognito,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_ssm as ssm,
    aws_logs as logs,
)
from constructs import Construct


class EnterpriseIdentityFederationStack(Stack):
    """
    CDK Stack for Enterprise Identity Federation with Bedrock AgentCore.
    
    This stack creates:
    - Cognito User Pool with SAML federation
    - Lambda function for custom authentication flows
    - IAM roles and policies for agent access control
    - Integration configuration for AgentCore workload identities
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        enterprise_idp_metadata_url: Optional[str] = None,
        enterprise_domain: str = "@company.com",
        **kwargs
    ) -> None:
        """
        Initialize the Enterprise Identity Federation Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            enterprise_idp_metadata_url: URL for enterprise SAML IdP metadata
            enterprise_domain: Email domain for enterprise users
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.enterprise_idp_metadata_url = enterprise_idp_metadata_url or "https://your-enterprise-idp.com/metadata"
        self.enterprise_domain = enterprise_domain

        # Generate unique suffix for resource names
        self.unique_suffix = cdk.Fn.select(
            2, cdk.Fn.split("/", self.stack_id)
        )[:8].lower()

        # Create the infrastructure components
        self._create_cognito_user_pool()
        self._create_lambda_auth_handler()
        self._create_agent_iam_roles()
        self._create_integration_config()
        self._create_outputs()

    def _create_cognito_user_pool(self) -> None:
        """Create Cognito User Pool with enterprise federation settings."""
        
        # Create User Pool with enterprise security settings
        self.user_pool = cognito.UserPool(
            self,
            "EnterpriseUserPool",
            user_pool_name=f"enterprise-ai-agents-{self.unique_suffix}",
            password_policy=cognito.PasswordPolicy(
                min_length=12,
                require_uppercase=True,
                require_lowercase=True,
                require_digits=True,
                require_symbols=True,
            ),
            mfa=cognito.Mfa.OPTIONAL,
            mfa_second_factor=cognito.MfaSecondFactor(
                sms=True,
                otp=True,
            ),
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            removal_policy=RemovalPolicy.DESTROY,
            advanced_security_mode=cognito.AdvancedSecurityMode.ENFORCED,
            device_tracking=cognito.DeviceTracking(
                challenge_required_on_new_device=True,
                device_only_remembered_on_user_prompt=True,
            ),
        )

        # Add SAML Identity Provider
        self.saml_provider = cognito.UserPoolIdentityProviderSaml(
            self,
            "EnterpriseSSO",
            user_pool=self.user_pool,
            name="EnterpriseSSO",
            metadata=cognito.UserPoolIdentityProviderSamlMetadata.url(
                self.enterprise_idp_metadata_url
            ),
            attribute_mapping=cognito.AttributeMapping(
                email=cognito.ProviderAttribute.other("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"),
                given_name=cognito.ProviderAttribute.other("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname"),
                family_name=cognito.ProviderAttribute.other("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"),
                custom={
                    "department": cognito.ProviderAttribute.other("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/department")
                }
            ),
        )

        # Create User Pool Client for OAuth flows
        self.user_pool_client = cognito.UserPoolClient(
            self,
            "AgentCoreEnterpriseClient",
            user_pool=self.user_pool,
            user_pool_client_name="AgentCore-Enterprise-Client",
            generate_secret=True,
            supported_identity_providers=[
                cognito.UserPoolClientIdentityProvider.cognito(),
                cognito.UserPoolClientIdentityProvider.custom("EnterpriseSSO"),
            ],
            o_auth=cognito.OAuthSettings(
                flows=cognito.OAuthFlows(
                    authorization_code_grant=True,
                    implicit_code_grant=True,
                ),
                scopes=[
                    cognito.OAuthScope.OPENID,
                    cognito.OAuthScope.EMAIL,
                    cognito.OAuthScope.PROFILE,
                    cognito.OAuthScope.COGNITO_ADMIN,
                ],
                callback_urls=[
                    "https://your-app.company.com/oauth/callback",
                    "https://localhost:8080/callback",
                ],
                logout_urls=[
                    "https://your-app.company.com/logout",
                ],
            ),
            auth_flows=cognito.AuthFlow(
                user_password=True,
                user_srp=True,
                custom=True,
                admin_user_password=True,
            ),
            access_token_validity=Duration.hours(1),
            id_token_validity=Duration.hours(1),
            refresh_token_validity=Duration.days(30),
        )

        # Ensure client depends on identity provider
        self.user_pool_client.node.add_dependency(self.saml_provider)

        # Add tags for resource management
        cdk.Tags.of(self.user_pool).add("Environment", "Production")
        cdk.Tags.of(self.user_pool).add("Purpose", "Enterprise-AI-Identity")
        cdk.Tags.of(self.user_pool).add("Project", "BedrockAgentCore")

    def _create_lambda_auth_handler(self) -> None:
        """Create Lambda function for custom authentication flows."""
        
        # Create IAM role for Lambda execution
        lambda_role = iam.Role(
            self,
            "AuthHandlerLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "CognitoAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cognito-idp:AdminGetUser",
                                "cognito-idp:AdminUpdateUserAttributes",
                                "cognito-idp:DescribeUserPool",
                            ],
                            resources=[self.user_pool.user_pool_arn],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ssm:GetParameter",
                                "ssm:GetParameters",
                            ],
                            resources=[
                                f"arn:aws:ssm:{self.region}:{self.account}:parameter/enterprise/agentcore/*"
                            ],
                        ),
                    ]
                )
            },
        )

        # Create CloudWatch Log Group for Lambda
        log_group = logs.LogGroup(
            self,
            "AuthHandlerLogGroup",
            log_group_name=f"/aws/lambda/agent-auth-handler-{self.unique_suffix}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Lambda function
        self.auth_handler = lambda_.Function(
            self,
            "AuthHandler",
            function_name=f"agent-auth-handler-{self.unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "USER_POOL_ID": self.user_pool.user_pool_id,
                "AGENTCORE_IDENTITY_NAME": f"enterprise-agent-{self.unique_suffix}",
                "ENTERPRISE_DOMAIN": self.enterprise_domain,
            },
            log_group=log_group,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
        )

        # Configure Cognito Lambda triggers
        self.user_pool.add_trigger(
            cognito.UserPoolOperation.PRE_AUTHENTICATION,
            self.auth_handler,
        )
        self.user_pool.add_trigger(
            cognito.UserPoolOperation.POST_AUTHENTICATION,
            self.auth_handler,
        )
        self.user_pool.add_trigger(
            cognito.UserPoolOperation.CUSTOM_MESSAGE,
            self.auth_handler,
        )

    def _create_agent_iam_roles(self) -> None:
        """Create IAM roles and policies for AI agent access control."""
        
        # Create IAM policy for AgentCore access
        self.agentcore_policy = iam.ManagedPolicy(
            self,
            "AgentCoreAccessPolicy",
            managed_policy_name=f"AgentCoreAccessPolicy-{self.unique_suffix}",
            description="Access policy for Bedrock AgentCore AI agents",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "bedrock:InvokeModel",
                        "bedrock:InvokeModelWithResponseStream",
                        "bedrock:ListFoundationModels",
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            "aws:RequestedRegion": self.region
                        }
                    },
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                    ],
                    resources=[
                        "arn:aws:s3:::enterprise-ai-data-*/*"
                    ],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                    ],
                    resources=[
                        f"arn:aws:logs:{self.region}:{self.account}:*"
                    ],
                ),
            ],
        )

        # Create IAM role for AI agents
        self.agent_execution_role = iam.Role(
            self,
            "AgentCoreExecutionRole",
            role_name=f"AgentCoreExecutionRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("bedrock-agentcore.amazonaws.com"),
            managed_policies=[self.agentcore_policy],
            conditions={
                "StringEquals": {
                    "aws:SourceAccount": self.account
                }
            },
        )

        # Add tags for resource management
        cdk.Tags.of(self.agentcore_policy).add("Purpose", "AI-Agent-Access")
        cdk.Tags.of(self.agent_execution_role).add("Purpose", "AI-Agent-Execution")

    def _create_integration_config(self) -> None:
        """Create integration configuration for cross-service communication."""
        
        # Store integration configuration in Systems Manager Parameter Store
        integration_config = {
            "enterpriseIntegration": {
                "cognitoUserPool": self.user_pool.user_pool_id,
                "agentCoreIdentity": f"enterprise-agent-{self.unique_suffix}",
                "authenticationFlow": "enterprise-saml-oauth",
                "permissionMapping": {
                    "engineering": {
                        "maxAgents": 10,
                        "allowedActions": ["create", "read", "update", "delete"],
                        "resourceAccess": ["bedrock", "s3", "lambda"]
                    },
                    "security": {
                        "maxAgents": 5,
                        "allowedActions": ["create", "read", "update", "delete", "audit"],
                        "resourceAccess": ["bedrock", "iam", "cloudtrail"]
                    },
                    "general": {
                        "maxAgents": 2,
                        "allowedActions": ["read"],
                        "resourceAccess": ["bedrock"]
                    }
                }
            }
        }

        self.integration_parameter = ssm.StringParameter(
            self,
            "IntegrationConfig",
            parameter_name="/enterprise/agentcore/integration-config",
            string_value=cdk.Fn.to_json_string(integration_config),
            description="Enterprise AI agent integration configuration",
            tier=ssm.ParameterTier.STANDARD,
        )

        # Add tags
        cdk.Tags.of(self.integration_parameter).add("Environment", "Production")
        cdk.Tags.of(self.integration_parameter).add("Purpose", "AgentCore-Integration")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        
        CfnOutput(
            self,
            "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID for enterprise federation",
            export_name=f"EnterpriseUserPoolId-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "UserPoolClientId",
            value=self.user_pool_client.user_pool_client_id,
            description="Cognito User Pool Client ID for OAuth flows",
            export_name=f"EnterpriseUserPoolClientId-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "AuthHandlerFunctionName",
            value=self.auth_handler.function_name,
            description="Lambda function name for authentication handling",
            export_name=f"AuthHandlerFunctionName-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "AgentExecutionRoleArn",
            value=self.agent_execution_role.role_arn,
            description="IAM role ARN for AI agent execution",
            export_name=f"AgentExecutionRoleArn-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "AgentCorePolicyArn",
            value=self.agentcore_policy.managed_policy_arn,
            description="IAM policy ARN for AgentCore access",
            export_name=f"AgentCorePolicyArn-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "IntegrationConfigParameter",
            value=self.integration_parameter.parameter_name,
            description="SSM parameter name for integration configuration",
            export_name=f"IntegrationConfigParameter-{self.unique_suffix}",
        )

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for authentication handling."""
        return '''
import json
import boto3
import logging
import os
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Custom authentication handler for enterprise AI agent identity management.
    Validates enterprise user context and determines agent access permissions.
    """
    try:
        trigger_source = event.get('triggerSource')
        user_attributes = event.get('request', {}).get('userAttributes', {})
        
        logger.info(f"Processing trigger: {trigger_source}")
        logger.info(f"User attributes: {json.dumps(user_attributes, default=str)}")
        
        if trigger_source == 'PostAuthentication_Authentication':
            # Process successful enterprise authentication
            email = user_attributes.get('email', '')
            department = user_attributes.get('custom:department', 'general')
            
            # Determine agent access based on department
            agent_permissions = determine_agent_permissions(department)
            
            # Store user session context for AgentCore access
            response = event
            response['response'] = {
                'agentPermissions': agent_permissions,
                'sessionDuration': 3600  # 1 hour session
            }
            
            logger.info(f"Authentication successful for {email} with permissions: {agent_permissions}")
            return response
            
        elif trigger_source == 'PreAuthentication_Authentication':
            # Validate user eligibility for AI agent access
            email = user_attributes.get('email', '')
            
            # Check if user is authorized for AI agent management
            if not is_authorized_for_ai_agents(email):
                raise Exception("User not authorized for AI agent access")
            
            return event
            
        elif trigger_source == 'CustomMessage_Authentication':
            # Customize authentication messages
            message = event.get('request', {}).get('codeParameter', '')
            event['response'] = {
                'smsMessage': f'Your enterprise AI agent verification code is {message}',
                'emailMessage': f'Your enterprise AI agent verification code is {message}',
                'emailSubject': 'Enterprise AI Agent Access Verification'
            }
            return event
            
        return event
        
    except Exception as e:
        logger.error(f"Authentication error: {str(e)}")
        raise e

def determine_agent_permissions(department: str) -> Dict[str, Any]:
    """Determine AI agent access permissions based on user department."""
    permission_map = {
        'engineering': {
            'canCreateAgents': True,
            'canDeleteAgents': True,
            'maxAgents': 10,
            'allowedServices': ['bedrock', 's3', 'lambda']
        },
        'security': {
            'canCreateAgents': True,
            'canDeleteAgents': True,
            'maxAgents': 5,
            'allowedServices': ['bedrock', 'iam', 'cloudtrail']
        },
        'general': {
            'canCreateAgents': False,
            'canDeleteAgents': False,
            'maxAgents': 2,
            'allowedServices': ['bedrock']
        }
    }
    
    return permission_map.get(department, permission_map['general'])

def is_authorized_for_ai_agents(email: str) -> bool:
    """Check if user is authorized for AI agent management."""
    # Get enterprise domain from environment
    enterprise_domain = os.environ.get('ENTERPRISE_DOMAIN', '@company.com')
    
    # Check if email belongs to authorized domain
    if not email.endswith(enterprise_domain):
        return False
    
    # Additional authorization logic could be implemented here
    # This could check against DynamoDB, external APIs, etc.
    return True
'''


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get configuration from context or environment variables
    enterprise_idp_metadata_url = app.node.try_get_context("enterpriseIdpMetadataUrl")
    enterprise_domain = app.node.try_get_context("enterpriseDomain") or "@company.com"
    
    # Create the stack
    EnterpriseIdentityFederationStack(
        app,
        "EnterpriseIdentityFederationStack",
        enterprise_idp_metadata_url=enterprise_idp_metadata_url,
        enterprise_domain=enterprise_domain,
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION"),
        ),
        description="Enterprise Identity Federation with Bedrock AgentCore - CDK Python Stack",
    )

    app.synth()


if __name__ == "__main__":
    main()