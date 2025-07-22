#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as amplify from 'aws-cdk-lib/aws-amplify';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Configuration interface for the Progressive Web App Stack
 */
interface ProgressiveWebAppStackProps extends cdk.StackProps {
  /** The name of the Amplify application */
  readonly appName?: string;
  /** GitHub repository URL for the PWA source code */
  readonly repositoryUrl?: string;
  /** GitHub access token for repository access */
  readonly githubAccessToken?: string;
  /** Custom domain name for the PWA */
  readonly domainName?: string;
  /** Subdomain prefix for the PWA */
  readonly subdomainPrefix?: string;
  /** Environment name (dev, staging, prod) */
  readonly environmentName?: string;
  /** Enable auto branch creation for feature branches */
  readonly enableAutoBranchCreation?: boolean;
  /** Enable pull request previews */
  readonly enablePullRequestPreview?: boolean;
}

/**
 * AWS CDK Stack for deploying Progressive Web Apps with Amplify Hosting
 * 
 * This stack creates:
 * - AWS Amplify application with PWA optimizations
 * - Custom domain configuration with SSL certificates
 * - CI/CD pipeline for automated deployments
 * - CloudWatch monitoring and logging
 * - Performance optimization headers
 * - Security headers for PWA compliance
 */
export class ProgressiveWebAppStack extends cdk.Stack {
  /** The Amplify application instance */
  public readonly amplifyApp: amplify.CfnApp;
  
  /** The main branch for production deployments */
  public readonly mainBranch: amplify.CfnBranch;
  
  /** SSL certificate for custom domain (if configured) */
  public readonly certificate?: acm.Certificate;
  
  /** Custom domain association (if configured) */
  public readonly domainAssociation?: amplify.CfnDomainAssociation;

  constructor(scope: Construct, id: string, props: ProgressiveWebAppStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with sensible defaults
    const appName = props.appName || 'progressive-web-app';
    const environmentName = props.environmentName || 'production';
    const enableAutoBranchCreation = props.enableAutoBranchCreation ?? true;
    const enablePullRequestPreview = props.enablePullRequestPreview ?? true;

    // Create IAM service role for Amplify
    const amplifyServiceRole = this.createAmplifyServiceRole();

    // Create the Amplify application
    this.amplifyApp = this.createAmplifyApplication(
      appName,
      amplifyServiceRole,
      props.repositoryUrl,
      props.githubAccessToken,
      enableAutoBranchCreation,
      enablePullRequestPreview
    );

    // Create the main branch
    this.mainBranch = this.createMainBranch(environmentName);

    // Configure custom domain if provided
    if (props.domainName) {
      const { certificate, domainAssociation } = this.configureDomain(
        props.domainName,
        props.subdomainPrefix || 'pwa'
      );
      this.certificate = certificate;
      this.domainAssociation = domainAssociation;
    }

    // Create CloudWatch log group for monitoring
    this.createMonitoringResources(appName);

    // Add stack outputs
    this.createOutputs(props.domainName, props.subdomainPrefix);

    // Add tags to all resources
    this.addStackTags(appName, environmentName);
  }

  /**
   * Creates the IAM service role required by Amplify for backend operations
   */
  private createAmplifyServiceRole(): iam.Role {
    const role = new iam.Role(this, 'AmplifyServiceRole', {
      assumedBy: new iam.ServicePrincipal('amplify.amazonaws.com'),
      description: 'Service role for AWS Amplify application backend operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AdministratorAccess-Amplify')
      ],
    });

    // Add additional permissions for CloudWatch and monitoring
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams',
        'cloudwatch:PutMetricData'
      ],
      resources: ['*']
    }));

    return role;
  }

  /**
   * Creates the main Amplify application with PWA-specific configuration
   */
  private createAmplifyApplication(
    appName: string,
    serviceRole: iam.Role,
    repositoryUrl?: string,
    accessToken?: string,
    enableAutoBranchCreation: boolean = true,
    enablePullRequestPreview: boolean = true
  ): amplify.CfnApp {
    
    // Define custom headers for PWA optimization
    const customHeaders = `
customHeaders:
  # Security headers for all files
  - pattern: "**/*"
    headers:
      - key: "X-Frame-Options"
        value: "DENY"
      - key: "X-Content-Type-Options"
        value: "nosniff"
      - key: "X-XSS-Protection"
        value: "1; mode=block"
      - key: "Referrer-Policy"
        value: "strict-origin-when-cross-origin"
      - key: "Strict-Transport-Security"
        value: "max-age=31536000; includeSubDomains"
      # Cache static assets for one year
      - key: "Cache-Control"
        value: "public, max-age=31536000, immutable"
  
  # Dynamic content (HTML) - no cache
  - pattern: "**.html"
    headers:
      - key: "Cache-Control"
        value: "public, max-age=0, must-revalidate"
      - key: "X-Frame-Options"
        value: "DENY"
  
  # Service Worker - never cache
  - pattern: "sw.js"
    headers:
      - key: "Cache-Control"
        value: "public, max-age=0, must-revalidate"
      - key: "Service-Worker-Allowed"
        value: "/"
  
  # PWA Manifest - short cache
  - pattern: "manifest.json"
    headers:
      - key: "Cache-Control"
        value: "public, max-age=300"
      - key: "Content-Type"
        value: "application/manifest+json"
  
  # App icons - long cache
  - pattern: "icon-*.png"
    headers:
      - key: "Cache-Control"
        value: "public, max-age=31536000, immutable"
`;

    // Build specification optimized for PWAs
    const buildSpec = `
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - echo "Starting PWA build process"
        - echo "Node version:" && node --version
        - echo "NPM version:" && npm --version
        # Install PWA validation tools
        - npm install -g pwa-asset-generator lighthouse workbox-cli
    build:
      commands:
        - echo "Building Progressive Web App"
        - echo "Validating PWA requirements"
        # Validate manifest.json exists
        - test -f manifest.json || echo "Warning: manifest.json not found"
        # Validate service worker exists
        - test -f sw.js || echo "Warning: Service worker not found"
        # Check for HTTPS requirement notice
        - echo "PWA features require HTTPS - ensure domain has valid SSL"
        # List all files for debugging
        - find . -type f -name "*.html" -o -name "*.js" -o -name "*.json" -o -name "*.css" | head -20
    postBuild:
      commands:
        - echo "PWA build completed successfully"
        - echo "Validating PWA compliance"
        # Run basic PWA checks
        - echo "Checking for required PWA files:"
        - test -f index.html && echo "✓ index.html found" || echo "✗ index.html missing"
        - test -f manifest.json && echo "✓ manifest.json found" || echo "✗ manifest.json missing"
        - test -f sw.js && echo "✓ Service worker found" || echo "✗ Service worker missing"
  artifacts:
    baseDirectory: .
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
`;

    const app = new amplify.CfnApp(this, 'AmplifyApp', {
      name: appName,
      description: 'Progressive Web App with offline functionality and app-like experience',
      platform: 'WEB',
      iamServiceRole: serviceRole.roleArn,
      buildSpec: buildSpec,
      customHeaders: customHeaders,
      
      // Repository configuration (optional)
      ...(repositoryUrl && {
        repository: repositoryUrl,
        ...(accessToken && { oauthToken: accessToken })
      }),

      // Auto branch creation for feature branches
      enableBranchAutoBuild: enableAutoBranchCreation,
      enableBranchAutoDeletion: true,
      
      // Auto branch creation patterns
      autoBranchCreationConfig: enableAutoBranchCreation ? {
        enableAutoBuild: true,
        enablePullRequestPreview: enablePullRequestPreview,
        environmentVariables: [
          {
            name: 'AMPLIFY_MONOREPO_APP_ROOT',
            value: '.'
          },
          {
            name: '_LIVE_UPDATES',
            value: '[{"pkg":"@aws-amplify/cli","type":"npm","version":"latest"}]'
          }
        ],
        framework: 'Web',
        stage: 'DEVELOPMENT'
      } : undefined,

      // Environment variables for PWA optimization
      environmentVariables: [
        {
          name: 'AMPLIFY_MONOREPO_APP_ROOT',
          value: '.'
        },
        {
          name: '_LIVE_UPDATES',
          value: '[{"pkg":"@aws-amplify/cli","type":"npm","version":"latest"}]'
        },
        {
          name: 'PWA_ENABLED',
          value: 'true'
        },
        {
          name: 'NODE_ENV',
          value: 'production'
        }
      ],

      // Tags for resource management
      tags: [
        {
          key: 'Application',
          value: appName
        },
        {
          key: 'Type',
          value: 'ProgressiveWebApp'
        },
        {
          key: 'Framework',
          value: 'Amplify'
        }
      ]
    });

    return app;
  }

  /**
   * Creates the main production branch with PWA-specific settings
   */
  private createMainBranch(environmentName: string): amplify.CfnBranch {
    const branch = new amplify.CfnBranch(this, 'MainBranch', {
      appId: this.amplifyApp.attrAppId,
      branchName: 'main',
      description: `Main production branch for ${environmentName} environment`,
      enableAutoBuild: true,
      enablePullRequestPreview: false, // Disable for main branch
      framework: 'Web',
      stage: 'PRODUCTION',
      
      // Environment variables specific to production
      environmentVariables: [
        {
          name: 'ENV',
          value: environmentName
        },
        {
          name: 'STAGE',
          value: 'PRODUCTION'
        },
        {
          name: 'PWA_MODE',
          value: 'production'
        }
      ],

      // Tags for the branch
      tags: [
        {
          key: 'Environment',
          value: environmentName
        },
        {
          key: 'Branch',
          value: 'main'
        },
        {
          key: 'Stage',
          value: 'PRODUCTION'
        }
      ]
    });

    return branch;
  }

  /**
   * Configures custom domain with SSL certificate
   */
  private configureDomain(domainName: string, subdomainPrefix: string): {
    certificate: acm.Certificate;
    domainAssociation: amplify.CfnDomainAssociation;
  } {
    const fullDomain = `${subdomainPrefix}.${domainName}`;

    // Create SSL certificate for the domain
    const certificate = new acm.Certificate(this, 'SSLCertificate', {
      domainName: fullDomain,
      subjectAlternativeNames: [`*.${domainName}`],
      validation: acm.CertificateValidation.fromDns(),
      transparencyLoggingEnabled: true,
    });

    // Create domain association
    const domainAssociation = new amplify.CfnDomainAssociation(this, 'DomainAssociation', {
      appId: this.amplifyApp.attrAppId,
      domainName: domainName,
      enableAutoSubDomain: true,
      subDomainSettings: [
        {
          prefix: subdomainPrefix,
          branchName: this.mainBranch.branchName
        }
      ],
      certificateSettings: {
        type: 'AMPLIFY_MANAGED'
      }
    });

    // Add dependency to ensure proper order
    domainAssociation.addDependency(this.mainBranch);

    return { certificate, domainAssociation };
  }

  /**
   * Creates CloudWatch monitoring resources
   */
  private createMonitoringResources(appName: string): void {
    // Create log group for Amplify application logs
    const logGroup = new logs.LogGroup(this, 'AmplifyLogGroup', {
      logGroupName: `/aws/amplify/${appName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Add tags to log group
    cdk.Tags.of(logGroup).add('Application', appName);
    cdk.Tags.of(logGroup).add('Type', 'AmplifyLogs');
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(domainName?: string, subdomainPrefix?: string): void {
    // App ID output
    new cdk.CfnOutput(this, 'AmplifyAppId', {
      value: this.amplifyApp.attrAppId,
      description: 'Amplify Application ID',
      exportName: `${this.stackName}-AppId`
    });

    // App ARN output
    new cdk.CfnOutput(this, 'AmplifyAppArn', {
      value: this.amplifyApp.attrArn,
      description: 'Amplify Application ARN',
      exportName: `${this.stackName}-AppArn`
    });

    // Default domain output
    new cdk.CfnOutput(this, 'AmplifyDefaultDomain', {
      value: this.amplifyApp.attrDefaultDomain,
      description: 'Default Amplify domain',
      exportName: `${this.stackName}-DefaultDomain`
    });

    // Main branch URL
    new cdk.CfnOutput(this, 'MainBranchUrl', {
      value: `https://main.${this.amplifyApp.attrDefaultDomain}`,
      description: 'Main branch URL',
      exportName: `${this.stackName}-MainBranchUrl`
    });

    // Custom domain outputs (if configured)
    if (domainName && subdomainPrefix) {
      new cdk.CfnOutput(this, 'CustomDomainUrl', {
        value: `https://${subdomainPrefix}.${domainName}`,
        description: 'Custom domain URL',
        exportName: `${this.stackName}-CustomDomainUrl`
      });

      if (this.certificate) {
        new cdk.CfnOutput(this, 'SSLCertificateArn', {
          value: this.certificate.certificateArn,
          description: 'SSL Certificate ARN',
          exportName: `${this.stackName}-SSLCertificateArn`
        });
      }
    }

    // CloudWatch logs output
    new cdk.CfnOutput(this, 'LogGroupName', {
      value: `/aws/amplify/${this.amplifyApp.name}`,
      description: 'CloudWatch Log Group name',
      exportName: `${this.stackName}-LogGroupName`
    });
  }

  /**
   * Adds tags to all stack resources
   */
  private addStackTags(appName: string, environmentName: string): void {
    cdk.Tags.of(this).add('Application', appName);
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('Type', 'ProgressiveWebApp');
    cdk.Tags.of(this).add('Framework', 'Amplify');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'PWA-Hosting');
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const appName = app.node.tryGetContext('appName') || process.env.APP_NAME || 'progressive-web-app';
const repositoryUrl = app.node.tryGetContext('repositoryUrl') || process.env.REPOSITORY_URL;
const githubAccessToken = app.node.tryGetContext('githubAccessToken') || process.env.GITHUB_ACCESS_TOKEN;
const domainName = app.node.tryGetContext('domainName') || process.env.DOMAIN_NAME;
const subdomainPrefix = app.node.tryGetContext('subdomainPrefix') || process.env.SUBDOMAIN_PREFIX || 'pwa';
const environmentName = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'production';

// Create the stack
new ProgressiveWebAppStack(app, 'ProgressiveWebAppStack', {
  appName,
  repositoryUrl,
  githubAccessToken,
  domainName,
  subdomainPrefix,
  environmentName,
  enableAutoBranchCreation: true,
  enablePullRequestPreview: true,
  
  // Stack configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  
  description: 'Progressive Web App infrastructure with AWS Amplify Hosting',
  
  tags: {
    Project: 'AWS-Recipes',
    Recipe: 'progressive-web-apps-amplify-hosting',
    CdkVersion: cdk.VERSION
  }
});

// Synthesize the CDK app
app.synth();