#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

/**
 * Configuration interface for the Parameter Store stack
 */
interface ParameterStoreConfigProps {
  /**
   * The application name prefix for parameter organization
   * @default 'myapp'
   */
  readonly appName?: string;

  /**
   * Environment identifier (dev, staging, prod)
   * @default 'dev'
   */
  readonly environment?: string;

  /**
   * Whether to create a custom KMS key for SecureString parameters
   * @default false (uses AWS managed key)
   */
  readonly useCustomKmsKey?: boolean;

  /**
   * Tags to apply to all resources
   */
  readonly tags?: { [key: string]: string };
}

/**
 * CDK Stack for Simple Configuration Management with Parameter Store
 * 
 * This stack creates a comprehensive Parameter Store configuration setup including:
 * - Standard String parameters for non-sensitive configuration
 * - SecureString parameters for sensitive data with KMS encryption
 * - StringList parameters for multi-value configuration
 * - Optional custom KMS key for enhanced security
 * - IAM role for CloudShell/application access
 */
class ParameterStoreConfigStack extends cdk.Stack {
  /**
   * The application name used for parameter prefixes
   */
  public readonly appName: string;

  /**
   * The parameter prefix path
   */
  public readonly parameterPrefix: string;

  /**
   * KMS key used for SecureString parameters (if custom key is enabled)
   */
  public readonly kmsKey?: kms.Key;

  /**
   * IAM role for accessing parameters
   */
  public readonly accessRole: iam.Role;

  constructor(scope: Construct, id: string, props: ParameterStoreConfigProps = {}) {
    super(scope, id);

    // Set configuration defaults
    this.appName = props.appName || 'myapp';
    const environment = props.environment || 'dev';
    this.parameterPrefix = `/${this.appName}-${environment}`;

    // Apply tags to all resources in the stack
    if (props.tags) {
      Object.entries(props.tags).forEach(([key, value]) => {
        cdk.Tags.of(this).add(key, value);
      });
    }

    // Add default tags
    cdk.Tags.of(this).add('Application', this.appName);
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'ConfigurationManagement');

    // Create custom KMS key if requested
    if (props.useCustomKmsKey) {
      this.kmsKey = this.createKmsKey();
    }

    // Create IAM role for parameter access
    this.accessRole = this.createAccessRole();

    // Create parameter groups
    this.createDatabaseParameters();
    this.createApplicationParameters();
    this.createSecurityParameters();
    this.createFeatureParameters();
    this.createDeploymentParameters();

    // Create stack outputs
    this.createOutputs();
  }

  /**
   * Creates a custom KMS key for SecureString parameter encryption
   */
  private createKmsKey(): kms.Key {
    const key = new kms.Key(this, 'ParameterStoreKmsKey', {
      description: `KMS key for ${this.appName} Parameter Store SecureString encryption`,
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      policy: new iam.PolicyDocument({
        statements: [
          // Allow root account full access
          new iam.PolicyStatement({
            sid: 'EnableRootAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          // Allow Systems Manager service to use the key
          new iam.PolicyStatement({
            sid: 'AllowSystemsManagerAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('ssm.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:DescribeKey',
              'kms:Encrypt',
              'kms:GenerateDataKey*',
              'kms:ReEncrypt*',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create alias for easier reference
    new kms.Alias(this, 'ParameterStoreKmsKeyAlias', {
      aliasName: `alias/${this.appName}-parameter-store`,
      targetKey: key,
    });

    return key;
  }

  /**
   * Creates IAM role for accessing Parameter Store parameters
   */
  private createAccessRole(): iam.Role {
    const role = new iam.Role(this, 'ParameterStoreAccessRole', {
      roleName: `${this.appName}-parameter-store-access-role`,
      description: `IAM role for accessing ${this.appName} Parameter Store parameters`,
      assumedBy: new iam.CompositePrincipal(
        // Allow EC2 instances to assume this role
        new iam.ServicePrincipal('ec2.amazonaws.com'),
        // Allow Lambda functions to assume this role
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        // Allow current account users to assume this role (for CloudShell)
        new iam.AccountPrincipal(this.account)
      ),
      managedPolicies: [
        // Basic CloudWatch logs access
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ParameterStoreAccess: new iam.PolicyDocument({
          statements: [
            // Allow reading parameters under the application prefix
            new iam.PolicyStatement({
              sid: 'AllowParameterStoreRead',
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:GetParameter',
                'ssm:GetParameters',
                'ssm:GetParametersByPath',
                'ssm:DescribeParameters',
              ],
              resources: [
                `arn:aws:ssm:${this.region}:${this.account}:parameter${this.parameterPrefix}*`,
              ],
            }),
            // Allow writing parameters under the application prefix (for automation)
            new iam.PolicyStatement({
              sid: 'AllowParameterStoreWrite',
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:PutParameter',
                'ssm:DeleteParameter',
                'ssm:AddTagsToResource',
                'ssm:RemoveTagsFromResource',
              ],
              resources: [
                `arn:aws:ssm:${this.region}:${this.account}:parameter${this.parameterPrefix}*`,
              ],
            }),
            // Allow KMS access for SecureString parameters
            new iam.PolicyStatement({
              sid: 'AllowKmsAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:DescribeKey',
              ],
              resources: [
                // Allow access to default SSM key
                `arn:aws:kms:${this.region}:${this.account}:key/alias/aws/ssm`,
                // Allow access to custom key if created
                ...(this.kmsKey ? [this.kmsKey.keyArn] : []),
              ],
            }),
          ],
        }),
      },
    });

    // Create instance profile for EC2 use
    new iam.CfnInstanceProfile(this, 'ParameterStoreInstanceProfile', {
      instanceProfileName: `${this.appName}-parameter-store-instance-profile`,
      roles: [role.roleName],
    });

    return role;
  }

  /**
   * Creates database-related configuration parameters
   */
  private createDatabaseParameters(): void {
    // Database connection URL (non-sensitive)
    new ssm.StringParameter(this, 'DatabaseUrlParameter', {
      parameterName: `${this.parameterPrefix}/database/url`,
      stringValue: 'postgresql://db.example.com:5432/myapp',
      description: `Database connection URL for ${this.appName}`,
      tier: ssm.ParameterTier.STANDARD,
    });

    // Database password (sensitive - encrypted)
    new ssm.StringParameter(this, 'DatabasePasswordParameter', {
      parameterName: `${this.parameterPrefix}/database/password`,
      stringValue: 'super-secure-password-123',
      description: `Database password for ${this.appName}`,
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.kmsKey?.keyArn || 'alias/aws/ssm',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Database connection pool settings (non-sensitive)
    new ssm.StringParameter(this, 'DatabaseMaxConnectionsParameter', {
      parameterName: `${this.parameterPrefix}/database/max-connections`,
      stringValue: '20',
      description: 'Maximum database connections in pool',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Database timeout settings
    new ssm.StringParameter(this, 'DatabaseTimeoutParameter', {
      parameterName: `${this.parameterPrefix}/database/timeout`,
      stringValue: '30000',
      description: 'Database connection timeout in milliseconds',
      tier: ssm.ParameterTier.STANDARD,
    });
  }

  /**
   * Creates application-level configuration parameters
   */
  private createApplicationParameters(): void {
    // Application environment
    new ssm.StringParameter(this, 'ApplicationEnvironmentParameter', {
      parameterName: `${this.parameterPrefix}/config/environment`,
      stringValue: 'development',
      description: 'Application environment setting',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Application log level
    new ssm.StringParameter(this, 'ApplicationLogLevelParameter', {
      parameterName: `${this.parameterPrefix}/config/log-level`,
      stringValue: 'INFO',
      description: 'Application logging level',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Application port
    new ssm.StringParameter(this, 'ApplicationPortParameter', {
      parameterName: `${this.parameterPrefix}/config/port`,
      stringValue: '3000',
      description: 'Application listening port',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Application session timeout
    new ssm.StringParameter(this, 'ApplicationSessionTimeoutParameter', {
      parameterName: `${this.parameterPrefix}/config/session-timeout`,
      stringValue: '3600',
      description: 'User session timeout in seconds',
      tier: ssm.ParameterTier.STANDARD,
    });
  }

  /**
   * Creates security-related configuration parameters
   */
  private createSecurityParameters(): void {
    // Third-party API key (sensitive - encrypted)
    new ssm.StringParameter(this, 'ThirdPartyApiKeyParameter', {
      parameterName: `${this.parameterPrefix}/api/third-party-key`,
      stringValue: 'api-key-12345-secret-value',
      description: `Third-party API key for ${this.appName}`,
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.kmsKey?.keyArn || 'alias/aws/ssm',
      tier: ssm.ParameterTier.STANDARD,
    });

    // JWT secret (sensitive - encrypted)
    new ssm.StringParameter(this, 'JwtSecretParameter', {
      parameterName: `${this.parameterPrefix}/security/jwt-secret`,
      stringValue: 'jwt-secret-key-very-secure-string',
      description: 'JWT token signing secret',
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.kmsKey?.keyArn || 'alias/aws/ssm',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Encryption key (sensitive - encrypted)
    new ssm.StringParameter(this, 'EncryptionKeyParameter', {
      parameterName: `${this.parameterPrefix}/security/encryption-key`,
      stringValue: 'app-encryption-key-32-character-string',
      description: 'Application data encryption key',
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.kmsKey?.keyArn || 'alias/aws/ssm',
      tier: ssm.ParameterTier.STANDARD,
    });

    // CORS allowed origins (StringList)
    new ssm.StringListParameter(this, 'CorsAllowedOriginsParameter', {
      parameterName: `${this.parameterPrefix}/api/allowed-origins`,
      stringListValue: [
        'https://app.example.com',
        'https://admin.example.com',
        'https://mobile.example.com'
      ],
      description: `CORS allowed origins for ${this.appName}`,
      tier: ssm.ParameterTier.STANDARD,
    });
  }

  /**
   * Creates feature flag and configuration parameters
   */
  private createFeatureParameters(): void {
    // Debug mode feature flag
    new ssm.StringParameter(this, 'DebugModeParameter', {
      parameterName: `${this.parameterPrefix}/features/debug-mode`,
      stringValue: 'true',
      description: 'Debug mode feature flag',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Maintenance mode feature flag
    new ssm.StringParameter(this, 'MaintenanceModeParameter', {
      parameterName: `${this.parameterPrefix}/features/maintenance-mode`,
      stringValue: 'false',
      description: 'Maintenance mode feature flag',
      tier: ssm.ParameterTier.STANDARD,
    });

    // New feature rollout percentage
    new ssm.StringParameter(this, 'FeatureRolloutParameter', {
      parameterName: `${this.parameterPrefix}/features/new-feature-rollout`,
      stringValue: '25',
      description: 'Percentage of users to receive new feature',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Cache TTL configuration
    new ssm.StringParameter(this, 'CacheTtlParameter', {
      parameterName: `${this.parameterPrefix}/config/cache-ttl`,
      stringValue: '300',
      description: 'Cache time-to-live in seconds',
      tier: ssm.ParameterTier.STANDARD,
    });
  }

  /**
   * Creates deployment and operational parameters
   */
  private createDeploymentParameters(): void {
    // Supported deployment regions (StringList)
    new ssm.StringListParameter(this, 'SupportedRegionsParameter', {
      parameterName: `${this.parameterPrefix}/deployment/regions`,
      stringListValue: ['us-east-1', 'us-west-2', 'eu-west-1'],
      description: 'Supported deployment regions',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Health check endpoint
    new ssm.StringParameter(this, 'HealthCheckEndpointParameter', {
      parameterName: `${this.parameterPrefix}/config/health-check-endpoint`,
      stringValue: '/health',
      description: 'Application health check endpoint path',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Monitoring configuration
    new ssm.StringParameter(this, 'MonitoringEnabledParameter', {
      parameterName: `${this.parameterPrefix}/config/monitoring-enabled`,
      stringValue: 'true',
      description: 'Enable application monitoring',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Backup schedule
    new ssm.StringParameter(this, 'BackupScheduleParameter', {
      parameterName: `${this.parameterPrefix}/config/backup-schedule`,
      stringValue: '0 2 * * *',
      description: 'Backup schedule in cron format',
      tier: ssm.ParameterTier.STANDARD,
    });
  }

  /**
   * Creates CloudFormation outputs for key resources
   */
  private createOutputs(): void {
    // Application configuration
    new cdk.CfnOutput(this, 'ApplicationName', {
      value: this.appName,
      description: 'Application name used for parameter organization',
      exportName: `${this.stackName}-ApplicationName`,
    });

    new cdk.CfnOutput(this, 'ParameterPrefix', {
      value: this.parameterPrefix,
      description: 'Parameter Store path prefix for all application parameters',
      exportName: `${this.stackName}-ParameterPrefix`,
    });

    // IAM resources
    new cdk.CfnOutput(this, 'AccessRoleArn', {
      value: this.accessRole.roleArn,
      description: 'IAM role ARN for accessing Parameter Store parameters',
      exportName: `${this.stackName}-AccessRoleArn`,
    });

    new cdk.CfnOutput(this, 'AccessRoleName', {
      value: this.accessRole.roleName,
      description: 'IAM role name for accessing Parameter Store parameters',
      exportName: `${this.stackName}-AccessRoleName`,
    });

    // KMS key (if created)
    if (this.kmsKey) {
      new cdk.CfnOutput(this, 'KmsKeyId', {
        value: this.kmsKey.keyId,
        description: 'KMS key ID for SecureString parameter encryption',
        exportName: `${this.stackName}-KmsKeyId`,
      });

      new cdk.CfnOutput(this, 'KmsKeyArn', {
        value: this.kmsKey.keyArn,
        description: 'KMS key ARN for SecureString parameter encryption',
        exportName: `${this.stackName}-KmsKeyArn`,
      });
    }

    // Usage instructions
    new cdk.CfnOutput(this, 'GetAllParametersCommand', {
      value: `aws ssm get-parameters-by-path --path "${this.parameterPrefix}" --recursive --with-decryption`,
      description: 'AWS CLI command to retrieve all application parameters',
    });

    new cdk.CfnOutput(this, 'AssumeRoleCommand', {
      value: `aws sts assume-role --role-arn "${this.accessRole.roleArn}" --role-session-name "parameter-store-access"`,
      description: 'AWS CLI command to assume the parameter access role',
    });
  }
}

/**
 * CDK Application entry point
 */
class ParameterStoreApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from context or environment variables
    const appName = this.node.tryGetContext('appName') || process.env.APP_NAME || 'myapp';
    const environment = this.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
    const useCustomKmsKey = this.node.tryGetContext('useCustomKmsKey') === 'true' || 
                            process.env.USE_CUSTOM_KMS_KEY === 'true';

    // Create the stack
    const stack = new ParameterStoreConfigStack(this, 'ParameterStoreConfigStack', {
      appName,
      environment,
      useCustomKmsKey,
      tags: {
        Project: 'SimpleConfigurationManagement',
        Owner: 'CDK',
        CostCenter: 'Development',
        Recipe: 'simple-configuration-management-parameter-store-cloudshell',
      },
    });

    // Add stack-level tags
    cdk.Tags.of(stack).add('StackType', 'ParameterStore');
    cdk.Tags.of(stack).add('DeploymentMethod', 'CDK');
  }
}

// Create and run the application
const app = new ParameterStoreApp();

// Add global tags to the entire application
cdk.Tags.of(app).add('CreatedBy', 'CDK-TypeScript');
cdk.Tags.of(app).add('Repository', 'recipes');

export { ParameterStoreConfigStack, ParameterStoreApp };