#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53targets from 'aws-cdk-lib/aws-route53-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';

/**
 * Properties for the SecureStaticWebsiteStack
 */
export interface SecureStaticWebsiteStackProps extends cdk.StackProps {
  /**
   * The domain name for the website (e.g., 'example.com')
   */
  readonly domainName: string;

  /**
   * The subdomain for the website (e.g., 'www.example.com')
   * @default 'www.' + domainName
   */
  readonly subdomain?: string;

  /**
   * The hosted zone ID for the domain
   * If not provided, the stack will attempt to look it up
   */
  readonly hostedZoneId?: string;

  /**
   * The hosted zone name for the domain
   * If not provided, uses the domainName
   */
  readonly hostedZoneName?: string;

  /**
   * Whether to create sample website content
   * @default true
   */
  readonly createSampleContent?: boolean;

  /**
   * Custom error page configuration
   * @default 'error.html'
   */
  readonly errorPagePath?: string;

  /**
   * Custom index page configuration
   * @default 'index.html'
   */
  readonly indexPagePath?: string;

  /**
   * CloudFront price class
   * @default PriceClass.PRICE_CLASS_100 (North America and Europe)
   */
  readonly priceClass?: cloudfront.PriceClass;

  /**
   * Minimum TLS version for CloudFront
   * @default SecurityPolicyProtocol.TLS_V1_2_2021
   */
  readonly minimumProtocolVersion?: cloudfront.SecurityPolicyProtocol;
}

/**
 * CDK Stack for Securing Websites with SSL Certificates, CloudFront, and S3
 * 
 * This stack creates:
 * - S3 bucket for static website hosting with security best practices
 * - SSL/TLS certificate from AWS Certificate Manager with automatic renewal
 * - CloudFront distribution with Origin Access Control (OAC) for secure S3 access
 * - Route 53 DNS records for custom domain mapping
 * - Sample website content (optional)
 * 
 * Security features:
 * - S3 bucket is not publicly accessible (only via CloudFront)
 * - SSL/TLS encryption with modern protocols (TLS 1.2+)
 * - Origin Access Control ensures secure communication between CloudFront and S3
 * - Automatic HTTPS redirection for all HTTP requests
 * - Content Security Policy headers for enhanced browser security
 */
export class SecureStaticWebsiteStack extends cdk.Stack {
  /**
   * The S3 bucket containing the static website content
   */
  public readonly websiteBucket: s3.Bucket;

  /**
   * The SSL/TLS certificate from AWS Certificate Manager
   */
  public readonly certificate: certificatemanager.Certificate;

  /**
   * The CloudFront distribution serving the website
   */
  public readonly distribution: cloudfront.Distribution;

  /**
   * The Route 53 hosted zone for DNS management
   */
  public readonly hostedZone: route53.IHostedZone;

  /**
   * The CloudFront Origin Access Control for secure S3 access
   */
  public readonly originAccessControl: cloudfront.OriginAccessControl;

  constructor(scope: Construct, id: string, props: SecureStaticWebsiteStackProps) {
    super(scope, id, props);

    // Validate required properties
    if (!props.domainName) {
      throw new Error('domainName is required');
    }

    // Set default values
    const subdomain = props.subdomain || `www.${props.domainName}`;
    const createSampleContent = props.createSampleContent ?? true;
    const errorPagePath = props.errorPagePath || 'error.html';
    const indexPagePath = props.indexPagePath || 'index.html';
    const priceClass = props.priceClass || cloudfront.PriceClass.PRICE_CLASS_100;
    const minimumProtocolVersion = props.minimumProtocolVersion || cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021;

    // Create S3 bucket for static website hosting
    this.websiteBucket = new s3.Bucket(this, 'WebsiteBucket', {
      // Generate unique bucket name using domain and account
      bucketName: `static-website-${props.domainName.replace(/\./g, '-')}-${cdk.Aws.ACCOUNT_ID}`.toLowerCase(),
      
      // Security configurations
      publicReadAccess: false, // Bucket is not publicly accessible
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL, // Block all public access
      encryption: s3.BucketEncryption.S3_MANAGED, // Server-side encryption
      enforceSSL: true, // Require SSL for all requests
      versioned: true, // Enable versioning for backup and recovery
      
      // Lifecycle configuration for cost optimization
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],

      // Removal policy - use RETAIN for production
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true, // For demo purposes only
    });

    // Add bucket notification for monitoring (optional)
    // This can be used for logging access patterns or triggering Lambda functions
    
    // Get or create hosted zone for DNS management
    this.hostedZone = props.hostedZoneId 
      ? route53.HostedZone.fromHostedZoneAttributes(this, 'HostedZone', {
          hostedZoneId: props.hostedZoneId,
          zoneName: props.hostedZoneName || props.domainName,
        })
      : route53.HostedZone.fromLookup(this, 'HostedZone', {
          domainName: props.domainName,
        });

    // Create SSL/TLS certificate using AWS Certificate Manager
    // Note: Certificate must be created in us-east-1 for CloudFront
    this.certificate = new certificatemanager.Certificate(this, 'SslCertificate', {
      domainName: props.domainName,
      subjectAlternativeNames: [subdomain],
      validation: certificatemanager.CertificateValidation.fromDns(this.hostedZone),
      certificateName: `ssl-cert-${props.domainName}`,
    });

    // Create Origin Access Control (OAC) for secure CloudFront to S3 communication
    // OAC is the modern replacement for Origin Access Identity (OAI)
    this.originAccessControl = new cloudfront.OriginAccessControl(this, 'OriginAccessControl', {
      description: `OAC for ${props.domainName} static website`,
      originAccessControlOriginType: cloudfront.OriginAccessControlOriginType.S3,
      signingBehavior: cloudfront.OriginAccessControlSigningBehavior.ALWAYS,
      signingProtocol: cloudfront.OriginAccessControlSigningProtocol.SIGV4,
    });

    // Create CloudFront distribution for global content delivery
    this.distribution = new cloudfront.Distribution(this, 'WebsiteDistribution', {
      // Default behavior configuration
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.websiteBucket, {
          originAccessControl: this.originAccessControl,
        }),
        
        // Security and performance settings
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS, // Force HTTPS
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
        compress: true, // Enable compression for better performance
        
        // Cache policy for static content
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        
        // Response headers policy for security
        responseHeadersPolicy: new cloudfront.ResponseHeadersPolicy(this, 'SecurityHeadersPolicy', {
          comment: 'Security headers for static website',
          securityHeadersBehavior: {
            // Content Type Options - prevents MIME type sniffing
            contentTypeOptions: { override: true },
            
            // Frame Options - prevents clickjacking attacks
            frameOptions: { frameOption: cloudfront.HeadersFrameOption.DENY, override: true },
            
            // Referrer Policy - controls referrer information
            referrerPolicy: { referrerPolicy: cloudfront.HeadersReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN, override: true },
            
            // Strict Transport Security - enforces HTTPS
            strictTransportSecurity: {
              accessControlMaxAge: cdk.Duration.seconds(31536000), // 1 year
              includeSubdomains: true,
              preload: true,
              override: true,
            },
          },
          customHeadersBehavior: {
            // Content Security Policy for XSS protection
            'Content-Security-Policy': {
              value: "default-src 'self'; img-src 'self' data: https:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com;",
              override: true,
            },
            // Permissions Policy for feature control
            'Permissions-Policy': {
              value: 'geolocation=(), microphone=(), camera=()',
              override: true,
            },
          },
        }),
      },

      // Domain and certificate configuration
      domainNames: [props.domainName, subdomain],
      certificate: this.certificate,
      minimumProtocolVersion: minimumProtocolVersion,
      
      // Global distribution settings
      priceClass: priceClass,
      
      // Default root object (index page)
      defaultRootObject: indexPagePath,
      
      // Custom error responses
      errorResponses: [
        {
          httpStatus: 403,
          responseHttpStatus: 200,
          responsePagePath: `/${indexPagePath}`, // SPA routing support
          ttl: cdk.Duration.minutes(5),
        },
        {
          httpStatus: 404,
          responseHttpStatus: 404,
          responsePagePath: `/${errorPagePath}`,
          ttl: cdk.Duration.minutes(5),
        },
      ],

      // Additional security and performance settings
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3, // Support HTTP/2 and HTTP/3
      comment: `CloudFront distribution for ${props.domainName}`,
      
      // Logging configuration (uncomment for production)
      // logBucket: new s3.Bucket(this, 'LoggingBucket', {
      //   encryption: s3.BucketEncryption.S3_MANAGED,
      //   blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // }),
      // logFilePrefix: 'cloudfront-logs/',
      // logIncludesCookies: false,
    });

    // Update S3 bucket policy to allow CloudFront access via OAC
    const bucketPolicyStatement = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
      actions: ['s3:GetObject'],
      resources: [this.websiteBucket.arnForObjects('*')],
      conditions: {
        StringEquals: {
          'AWS:SourceArn': `arn:aws:cloudfront::${cdk.Aws.ACCOUNT_ID}:distribution/${this.distribution.distributionId}`,
        },
      },
    });

    this.websiteBucket.addToResourcePolicy(bucketPolicyStatement);

    // Create Route 53 DNS records for domain mapping
    new route53.ARecord(this, 'ApexRecord', {
      zone: this.hostedZone,
      recordName: props.domainName,
      target: route53.RecordTarget.fromAlias(new route53targets.CloudFrontTarget(this.distribution)),
      comment: `Apex domain record for ${props.domainName}`,
    });

    new route53.ARecord(this, 'SubdomainRecord', {
      zone: this.hostedZone,
      recordName: subdomain,
      target: route53.RecordTarget.fromAlias(new route53targets.CloudFrontTarget(this.distribution)),
      comment: `Subdomain record for ${subdomain}`,
    });

    // Deploy sample website content if requested
    if (createSampleContent) {
      new s3deploy.BucketDeployment(this, 'DeployWebsiteContent', {
        sources: [
          s3deploy.Source.data('index.html', this.generateIndexHtml(props.domainName)),
          s3deploy.Source.data('error.html', this.generateErrorHtml()),
        ],
        destinationBucket: this.websiteBucket,
        distribution: this.distribution,
        distributionPaths: ['/*'], // Invalidate cache after deployment
        
        // Security settings for deployment
        memoryLimit: 512, // Optimize Lambda memory for deployment
        ephemeralStorageSize: cdk.Size.gibibytes(1), // Optimize storage
      });
    }

    // Add CDK Nag suppressions for known acceptable configurations
    this.addNagSuppressions();

    // Output important information
    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: `https://${props.domainName}`,
      description: 'Website URL',
      exportName: `${this.stackName}-WebsiteURL`,
    });

    new cdk.CfnOutput(this, 'DistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront Distribution ID',
      exportName: `${this.stackName}-DistributionId`,
    });

    new cdk.CfnOutput(this, 'DistributionDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront Distribution Domain Name',
      exportName: `${this.stackName}-DistributionDomainName`,
    });

    new cdk.CfnOutput(this, 'CertificateArn', {
      value: this.certificate.certificateArn,
      description: 'SSL Certificate ARN',
      exportName: `${this.stackName}-CertificateArn`,
    });

    new cdk.CfnOutput(this, 'BucketName', {
      value: this.websiteBucket.bucketName,
      description: 'S3 Bucket Name',
      exportName: `${this.stackName}-BucketName`,
    });
  }

  /**
   * Generate sample index.html content
   */
  private generateIndexHtml(domainName: string): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Secure Static Website - ${domainName}</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .container {
            background: white;
            padding: 3rem;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 600px;
            width: 90%;
        }
        
        .secure-badge {
            display: inline-block;
            background: #28a745;
            color: white;
            padding: 0.5rem 1rem;
            border-radius: 20px;
            font-size: 0.9rem;
            font-weight: bold;
            margin-bottom: 1rem;
        }
        
        h1 {
            color: #2c3e50;
            margin-bottom: 1rem;
            font-size: 2.5rem;
        }
        
        .highlight {
            color: #28a745;
            font-weight: bold;
        }
        
        .features {
            margin: 2rem 0;
            text-align: left;
        }
        
        .feature {
            display: flex;
            align-items: center;
            margin: 1rem 0;
            padding: 0.5rem;
            background: #f8f9fa;
            border-radius: 5px;
        }
        
        .feature-icon {
            color: #28a745;
            margin-right: 1rem;
            font-size: 1.2rem;
        }
        
        .technical-info {
            background: #e9ecef;
            padding: 1.5rem;
            border-radius: 5px;
            margin-top: 2rem;
            text-align: left;
        }
        
        .tech-title {
            font-weight: bold;
            color: #495057;
            margin-bottom: 0.5rem;
        }
        
        .footer {
            margin-top: 2rem;
            padding-top: 1rem;
            border-top: 1px solid #dee2e6;
            color: #6c757d;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="secure-badge">🔒 HTTPS Secured</div>
        <h1>Welcome to Your <span class="highlight">Secure</span> Website</h1>
        <p>This website is served over HTTPS using AWS Certificate Manager and CloudFront.</p>
        
        <div class="features">
            <div class="feature">
                <span class="feature-icon">🛡️</span>
                <span>SSL/TLS certificate automatically managed by AWS ACM</span>
            </div>
            <div class="feature">
                <span class="feature-icon">🚀</span>
                <span>Global content delivery via CloudFront CDN</span>
            </div>
            <div class="feature">
                <span class="feature-icon">🔐</span>
                <span>Origin Access Control for secure S3 access</span>
            </div>
            <div class="feature">
                <span class="feature-icon">⚡</span>
                <span>HTTP/2 and HTTP/3 support for optimal performance</span>
            </div>
            <div class="feature">
                <span class="feature-icon">🎯</span>
                <span>Security headers for enhanced protection</span>
            </div>
        </div>
        
        <div class="technical-info">
            <div class="tech-title">Technical Implementation:</div>
            <ul>
                <li><strong>Domain:</strong> ${domainName}</li>
                <li><strong>Certificate:</strong> AWS Certificate Manager (ACM)</li>
                <li><strong>CDN:</strong> Amazon CloudFront</li>
                <li><strong>Storage:</strong> Amazon S3 with encryption</li>
                <li><strong>DNS:</strong> Amazon Route 53</li>
                <li><strong>Security:</strong> Origin Access Control (OAC)</li>
            </ul>
        </div>
        
        <div class="footer">
            <p>Deployed using AWS CDK with infrastructure as code best practices.</p>
            <p>Last updated: ${new Date().toISOString().split('T')[0]}</p>
        </div>
    </div>
</body>
</html>`;
  }

  /**
   * Generate sample error.html content
   */
  private generateErrorHtml(): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - 404 Error</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .container {
            background: white;
            padding: 3rem;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 500px;
            width: 90%;
        }
        
        .error-code {
            font-size: 6rem;
            font-weight: bold;
            color: #e74c3c;
            margin-bottom: 1rem;
        }
        
        h1 {
            color: #2c3e50;
            margin-bottom: 1rem;
            font-size: 2rem;
        }
        
        p {
            margin-bottom: 1.5rem;
            color: #6c757d;
        }
        
        .btn-home {
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 0.75rem 1.5rem;
            text-decoration: none;
            border-radius: 5px;
            transition: background 0.3s ease;
        }
        
        .btn-home:hover {
            background: #5a6fd8;
        }
        
        .footer {
            margin-top: 2rem;
            padding-top: 1rem;
            border-top: 1px solid #dee2e6;
            color: #6c757d;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">404</div>
        <h1>Page Not Found</h1>
        <p>The requested page could not be found. It may have been moved, deleted, or you entered the wrong URL.</p>
        <a href="/" class="btn-home">Return to Home</a>
        <div class="footer">
            <p>This error page is served securely via HTTPS from Amazon CloudFront.</p>
        </div>
    </div>
</body>
</html>`;
  }

  /**
   * Add CDK Nag suppressions for acceptable configurations
   */
  private addNagSuppressions(): void {
    // Suppress S3 bucket access logging warning - not needed for static website hosting
    NagSuppressions.addResourceSuppressions(
      this.websiteBucket,
      [
        {
          id: 'AwsSolutions-S1',
          reason: 'S3 access logging not required for static website hosting. CloudFront logging can be enabled if needed.',
        },
      ]
    );

    // Suppress CloudFront origin failover warning - single origin is acceptable for static websites
    NagSuppressions.addResourceSuppressions(
      this.distribution,
      [
        {
          id: 'AwsSolutions-CFR1',
          reason: 'Origin failover not required for static website hosting from single S3 bucket.',
        },
        {
          id: 'AwsSolutions-CFR2',
          reason: 'WAF not required for static website hosting. Can be added if additional protection is needed.',
        },
      ]
    );
  }
}

/**
 * CDK App definition
 */
const app = new cdk.App();

// Apply CDK Nag for security best practices validation
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Get configuration from CDK context
const domainName = app.node.tryGetContext('domainName') || 'example.com';
const subdomain = app.node.tryGetContext('subdomain') || `www.${domainName}`;
const hostedZoneId = app.node.tryGetContext('hostedZoneId');
const createSampleContent = app.node.tryGetContext('createSampleContent') !== 'false';

// Validate domain name
if (domainName === 'example.com') {
  console.warn('⚠️  Using default domain name "example.com". Set domainName in cdk.context.json or use --context domainName=your-domain.com');
}

// Create the stack
new SecureStaticWebsiteStack(app, 'SecureStaticWebsiteStack', {
  domainName,
  subdomain,
  hostedZoneId,
  createSampleContent,
  
  // Stack configuration
  env: {
    // Certificate must be in us-east-1 for CloudFront
    region: 'us-east-1',
    // Use default account from AWS credentials
    account: process.env.CDK_DEFAULT_ACCOUNT,
  },
  
  description: 'Secure static website hosting with AWS Certificate Manager, CloudFront, and S3',
  
  tags: {
    Project: 'SecureStaticWebsite',
    Purpose: 'Demo',
    ManagedBy: 'CDK',
    Domain: domainName,
  },
});

// Synthesize the app
app.synth();