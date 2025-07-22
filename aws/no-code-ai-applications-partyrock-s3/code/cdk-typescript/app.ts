#!/usr/bin/env node

/**
 * CDK TypeScript Application for No-Code AI Applications with PartyRock and S3
 * 
 * This application creates the infrastructure needed to host PartyRock AI applications
 * using Amazon S3 for static website hosting and Amazon CloudFront for global content delivery.
 * 
 * Architecture:
 * - S3 Bucket with static website hosting configuration
 * - CloudFront Distribution for global content delivery with HTTPS
 * - Origin Access Control (OAC) for secure S3 access
 * - Proper security configurations and best practices
 */

import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

/**
 * Properties for the PartyRock Application Stack
 */
interface PartyRockAppStackProps extends cdk.StackProps {
  /** 
   * Environment prefix for resource naming 
   * @default 'dev'
   */
  readonly environmentName?: string;
  
  /** 
   * Enable versioning on the S3 bucket 
   * @default true
   */
  readonly enableVersioning?: boolean;
  
  /** 
   * Enable access logging for CloudFront 
   * @default false
   */
  readonly enableAccessLogging?: boolean;
  
  /** 
   * Custom domain name for the CloudFront distribution 
   * @default undefined
   */
  readonly customDomain?: string;
  
  /** 
   * Deploy sample HTML content 
   * @default true
   */
  readonly deploySampleContent?: boolean;
}

/**
 * CDK Stack for PartyRock AI Application Infrastructure
 * 
 * This stack creates:
 * 1. S3 bucket for static website hosting with security best practices
 * 2. CloudFront distribution with Origin Access Control
 * 3. Appropriate IAM policies for secure access
 * 4. Optional sample HTML content deployment
 */
class PartyRockAppStack extends cdk.Stack {
  /** The S3 bucket hosting the static website */
  public readonly websiteBucket: s3.Bucket;
  
  /** The CloudFront distribution */
  public readonly distribution: cloudfront.Distribution;
  
  /** The Origin Access Control for secure S3 access */
  public readonly originAccessControl: cloudfront.CfnOriginAccessControl;

  constructor(scope: Construct, id: string, props: PartyRockAppStackProps = {}) {
    super(scope, id, props);

    const {
      environmentName = 'dev',
      enableVersioning = true,
      enableAccessLogging = false,
      customDomain,
      deploySampleContent = true,
    } = props;

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();
    
    // Create S3 bucket for static website hosting
    this.websiteBucket = this.createWebsiteBucket(environmentName, uniqueSuffix, enableVersioning);
    
    // Create Origin Access Control for secure CloudFront to S3 access
    this.originAccessControl = this.createOriginAccessControl();
    
    // Create CloudFront distribution
    this.distribution = this.createCloudFrontDistribution(
      this.websiteBucket,
      this.originAccessControl,
      enableAccessLogging,
      customDomain
    );
    
    // Update S3 bucket policy to allow CloudFront access
    this.updateBucketPolicyForCloudFront(this.websiteBucket, this.distribution);
    
    // Deploy sample content if requested
    if (deploySampleContent) {
      this.deploySampleWebsiteContent(this.websiteBucket);
    }
    
    // Create stack outputs
    this.createOutputs();
    
    // Add tags to all resources
    this.addResourceTags(environmentName);
  }

  /**
   * Creates an S3 bucket configured for static website hosting with security best practices
   */
  private createWebsiteBucket(environmentName: string, uniqueSuffix: string, enableVersioning: boolean): s3.Bucket {
    const bucket = new s3.Bucket(this, 'WebsiteBucket', {
      bucketName: `partyrock-app-${environmentName}-${uniqueSuffix}`,
      
      // Security configurations
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      
      // Versioning and lifecycle
      versioned: enableVersioning,
      
      // Lifecycle rules for cost optimization
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      
      // Cleanup on stack deletion (for development environments)
      removalPolicy: environmentName === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: environmentName !== 'prod',
    });

    // Add notification configuration for monitoring (optional)
    if (environmentName === 'prod') {
      // In production, you might want to add CloudWatch alarms or SNS notifications
      // This is left as an exercise for production deployments
    }

    return bucket;
  }

  /**
   * Creates Origin Access Control for secure CloudFront to S3 access
   */
  private createOriginAccessControl(): cloudfront.CfnOriginAccessControl {
    return new cloudfront.CfnOriginAccessControl(this, 'OriginAccessControl', {
      originAccessControlConfig: {
        name: `partyrock-oac-${this.node.addr}`,
        originAccessControlOriginType: 's3',
        signingBehavior: 'always',
        signingProtocol: 'sigv4',
        description: 'Origin Access Control for PartyRock AI Application S3 bucket',
      },
    });
  }

  /**
   * Creates CloudFront distribution with security and performance optimizations
   */
  private createCloudFrontDistribution(
    bucket: s3.Bucket,
    oac: cloudfront.CfnOriginAccessControl,
    enableAccessLogging: boolean,
    customDomain?: string
  ): cloudfront.Distribution {
    
    // Create S3 origin with Origin Access Control
    const s3Origin = new origins.S3Origin(bucket, {
      originAccessIdentity: undefined, // Use OAC instead of OAI
    });

    // CloudFront distribution configuration
    const distributionProps: cloudfront.DistributionProps = {
      defaultBehavior: {
        origin: s3Origin,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
        compress: true,
        
        // Cache policy for static websites
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        
        // Origin request policy
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        
        // Response headers policy for security
        responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
      },
      
      // Default root object
      defaultRootObject: 'index.html',
      
      // Error pages configuration
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: '/index.html', // SPA fallback
          ttl: cdk.Duration.minutes(5),
        },
        {
          httpStatus: 403,
          responseHttpStatus: 200,
          responsePagePath: '/index.html', // SPA fallback
          ttl: cdk.Duration.minutes(5),
        },
      ],
      
      // Geographic restrictions (if needed)
      geoRestriction: cloudfront.GeoRestriction.denylist(), // No restrictions by default
      
      // Price class for cost optimization
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100, // US, Canada, Europe
      
      // HTTP version
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      
      // Security
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      
      // Custom domain (if provided)
      domainNames: customDomain ? [customDomain] : undefined,
      
      // Access logging (if enabled)
      enableLogging: enableAccessLogging,
      
      // Comment for identification
      comment: 'CloudFront distribution for PartyRock AI Application',
    };

    const distribution = new cloudfront.Distribution(this, 'Distribution', distributionProps);

    // Associate Origin Access Control with the distribution
    const cfnDistribution = distribution.node.defaultChild as cloudfront.CfnDistribution;
    cfnDistribution.addPropertyOverride('DistributionConfig.Origins.0.S3OriginConfig.OriginAccessIdentity', '');
    cfnDistribution.addPropertyOverride('DistributionConfig.Origins.0.OriginAccessControlId', oac.getAtt('Id'));

    return distribution;
  }

  /**
   * Updates S3 bucket policy to allow CloudFront access through Origin Access Control
   */
  private updateBucketPolicyForCloudFront(bucket: s3.Bucket, distribution: cloudfront.Distribution): void {
    const bucketPolicyStatement = new iam.PolicyStatement({
      sid: 'AllowCloudFrontServicePrincipal',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
      actions: ['s3:GetObject'],
      resources: [bucket.arnForObjects('*')],
      conditions: {
        StringEquals: {
          'AWS:SourceArn': `arn:aws:cloudfront::${this.account}:distribution/${distribution.distributionId}`,
        },
      },
    });

    bucket.addToResourcePolicy(bucketPolicyStatement);
  }

  /**
   * Deploys sample HTML content to demonstrate the PartyRock integration
   */
  private deploySampleWebsiteContent(bucket: s3.Bucket): void {
    // Create sample HTML content
    const htmlContent = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Business Name Generator - PartyRock Application</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            text-align: center;
            color: white;
            margin-bottom: 2rem;
            padding: 2rem 0;
        }
        
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 0.5rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .header p {
            font-size: 1.2rem;
            opacity: 0.9;
        }
        
        .main-content {
            background: white;
            border-radius: 15px;
            padding: 2rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 2rem;
        }
        
        .partyrock-section {
            text-align: center;
            margin: 2rem 0;
            padding: 2rem;
            background: linear-gradient(45deg, #ff9900, #ffb84d);
            border-radius: 10px;
            color: white;
        }
        
        .partyrock-section h2 {
            margin-bottom: 1rem;
            font-size: 2rem;
        }
        
        .btn {
            display: inline-block;
            padding: 15px 30px;
            background: #ff6b00;
            color: white;
            text-decoration: none;
            border-radius: 30px;
            font-weight: bold;
            font-size: 1.1rem;
            transition: all 0.3s ease;
            margin: 10px;
            box-shadow: 0 4px 15px rgba(255, 107, 0, 0.3);
        }
        
        .btn:hover {
            background: #e55a00;
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(255, 107, 0, 0.4);
        }
        
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1.5rem;
            margin: 2rem 0;
        }
        
        .feature {
            text-align: center;
            padding: 1.5rem;
            border-radius: 10px;
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            transition: transform 0.3s ease;
        }
        
        .feature:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        .feature-icon {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        
        .feature h3 {
            color: #495057;
            margin-bottom: 0.5rem;
        }
        
        .tech-stack {
            background: #f8f9fa;
            padding: 2rem;
            border-radius: 10px;
            margin: 2rem 0;
        }
        
        .tech-stack h2 {
            text-align: center;
            color: #495057;
            margin-bottom: 1.5rem;
        }
        
        .tech-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
        }
        
        .tech-item {
            background: white;
            padding: 1rem;
            border-radius: 8px;
            text-align: center;
            border: 2px solid #dee2e6;
        }
        
        .footer {
            text-align: center;
            color: white;
            padding: 2rem 0;
            opacity: 0.8;
        }
        
        @media (max-width: 768px) {
            .header h1 {
                font-size: 2rem;
            }
            
            .container {
                padding: 10px;
            }
            
            .main-content {
                padding: 1rem;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>🚀 AI Business Name Generator</h1>
            <p>Experience the power of generative AI with our no-code application built using Amazon PartyRock</p>
        </header>
        
        <main class="main-content">
            <div class="partyrock-section">
                <h2>🎯 Try the AI Application</h2>
                <p>Click the button below to access our AI-powered business name generator:</p>
                <a href="#" class="btn" onclick="handlePartyRockLaunch()">
                    🤖 Launch AI App
                </a>
                <p style="margin-top: 1rem; font-size: 0.9rem; opacity: 0.8;">
                    Replace this placeholder with your actual PartyRock application URL
                </p>
            </div>
            
            <div class="features">
                <div class="feature">
                    <div class="feature-icon">🧠</div>
                    <h3>AI-Powered Generation</h3>
                    <p>Leverages Amazon Bedrock's advanced language models for creative business name suggestions</p>
                </div>
                
                <div class="feature">
                    <div class="feature-icon">🎯</div>
                    <h3>Industry-Specific</h3>
                    <p>Tailored suggestions based on your industry type and business focus</p>
                </div>
                
                <div class="feature">
                    <div class="feature-icon">👥</div>
                    <h3>Target Audience</h3>
                    <p>Names optimized for your specific target market and customer demographics</p>
                </div>
                
                <div class="feature">
                    <div class="feature-icon">🎨</div>
                    <h3>Visual Concepts</h3>
                    <p>AI-generated logo concepts to complement your business names</p>
                </div>
            </div>
            
            <div class="tech-stack">
                <h2>🛠 Powered by AWS Technologies</h2>
                <div class="tech-grid">
                    <div class="tech-item">
                        <strong>Amazon PartyRock</strong><br>
                        No-code AI application platform
                    </div>
                    <div class="tech-item">
                        <strong>Amazon Bedrock</strong><br>
                        Foundation models for AI
                    </div>
                    <div class="tech-item">
                        <strong>Amazon S3</strong><br>
                        Static website hosting
                    </div>
                    <div class="tech-item">
                        <strong>Amazon CloudFront</strong><br>
                        Global content delivery
                    </div>
                </div>
            </div>
            
            <div style="text-align: center; margin: 2rem 0;">
                <h2>🔧 Getting Started</h2>
                <p>To integrate your PartyRock application:</p>
                <ol style="text-align: left; max-width: 600px; margin: 1rem auto;">
                    <li>Create your AI application in <a href="https://partyrock.aws/" target="_blank">PartyRock</a></li>
                    <li>Make your application public and copy the URL</li>
                    <li>Replace the placeholder link above with your PartyRock URL</li>
                    <li>Deploy your updated website content</li>
                </ol>
            </div>
        </main>
        
        <footer class="footer">
            <p>&copy; 2025 AI Business Name Generator | Powered by AWS PartyRock, S3, and CloudFront</p>
            <p>Built with ❤️ using AWS CDK and modern web technologies</p>
        </footer>
    </div>
    
    <script>
        function handlePartyRockLaunch() {
            // Replace this alert with your actual PartyRock application URL
            alert('Please replace this placeholder with your actual PartyRock application URL in the HTML file.');
            
            // Example of how to open the PartyRock app:
            // window.open('YOUR_PARTYROCK_APP_URL', '_blank');
        }
        
        // Add some interactive effects
        document.addEventListener('DOMContentLoaded', function() {
            // Add fade-in animation to features
            const features = document.querySelectorAll('.feature');
            features.forEach((feature, index) => {
                setTimeout(() => {
                    feature.style.opacity = '0';
                    feature.style.transform = 'translateY(20px)';
                    feature.style.transition = 'all 0.6s ease';
                    
                    setTimeout(() => {
                        feature.style.opacity = '1';
                        feature.style.transform = 'translateY(0)';
                    }, 100);
                }, index * 200);
            });
        });
        
        // Add some analytics tracking (optional)
        function trackPartyRockClick() {
            // Add your analytics tracking code here
            console.log('PartyRock application launched');
        }
    </script>
</body>
</html>`;

    // Deploy the sample content
    new s3deploy.BucketDeployment(this, 'DeployWebsite', {
      sources: [
        s3deploy.Source.data('index.html', htmlContent),
        s3deploy.Source.data('error.html', `
<!DOCTYPE html>
<html>
<head>
    <title>Page Not Found</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #e74c3c; }
        a { color: #3498db; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>404 - Page Not Found</h1>
    <p>The page you're looking for doesn't exist.</p>
    <a href="/">Return to Home</a>
</body>
</html>
        `),
      ],
      destinationBucket: bucket,
      distribution: this.distribution,
      distributionPaths: ['/*'], // Invalidate all cached content
    });
  }

  /**
   * Creates CloudFormation outputs for important resource information
   */
  private createOutputs(): void {
    // S3 bucket outputs
    new cdk.CfnOutput(this, 'WebsiteBucketName', {
      value: this.websiteBucket.bucketName,
      description: 'Name of the S3 bucket hosting the static website',
      exportName: `${this.stackName}-WebsiteBucketName`,
    });

    new cdk.CfnOutput(this, 'WebsiteBucketArn', {
      value: this.websiteBucket.bucketArn,
      description: 'ARN of the S3 bucket hosting the static website',
    });

    // CloudFront distribution outputs
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

    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: `https://${this.distribution.distributionDomainName}`,
      description: 'Website URL (CloudFront Distribution)',
      exportName: `${this.stackName}-WebsiteURL`,
    });

    // Origin Access Control output
    new cdk.CfnOutput(this, 'OriginAccessControlId', {
      value: this.originAccessControl.getAtt('Id').toString(),
      description: 'Origin Access Control ID for CloudFront to S3 access',
    });
  }

  /**
   * Adds consistent tags to all resources in the stack
   */
  private addResourceTags(environmentName: string): void {
    cdk.Tags.of(this).add('Project', 'PartyRockAIApplication');
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'StaticWebsiteHosting');
    cdk.Tags.of(this).add('CostCenter', 'AI-Applications');
    cdk.Tags.of(this).add('Owner', 'Development-Team');
  }
}

/**
 * CDK Application entry point
 */
class PartyRockApp extends cdk.App {
  constructor() {
    super();

    // Get environment configuration from context or environment variables
    const environmentName = this.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
    const enableVersioning = this.node.tryGetContext('enableVersioning') !== false;
    const enableAccessLogging = this.node.tryGetContext('enableAccessLogging') === true;
    const customDomain = this.node.tryGetContext('customDomain') || process.env.CUSTOM_DOMAIN;
    const deploySampleContent = this.node.tryGetContext('deploySampleContent') !== false;

    // Create the main stack
    new PartyRockAppStack(this, `PartyRockAppStack-${environmentName}`, {
      environmentName,
      enableVersioning,
      enableAccessLogging,
      customDomain,
      deploySampleContent,
      
      // Stack configuration
      description: `Infrastructure for PartyRock AI Application hosting (${environmentName})`,
      
      // Environment configuration (optional)
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
      },
      
      // Termination protection for production
      terminationProtection: environmentName === 'prod',
    });
  }
}

// Initialize and run the CDK application
new PartyRockApp();