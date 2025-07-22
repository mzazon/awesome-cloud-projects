const AWS = require('aws-sdk');
const cloudfront = new AWS.CloudFront();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const sqs = new AWS.SQS();

// Environment variables and configuration
const TABLE_NAME = process.env.DDB_TABLE_NAME || '${DDB_TABLE_NAME}';
const QUEUE_URL = process.env.QUEUE_URL || '${QUEUE_URL}';
const DISTRIBUTION_ID = process.env.DISTRIBUTION_ID || '${DISTRIBUTION_ID}';
const DLQ_URL = process.env.DLQ_URL || '${DLQ_URL}';
const BATCH_SIZE = 10; // CloudFront allows max 15 paths per invalidation

/**
 * Main Lambda handler for intelligent CloudFront invalidation
 * Processes events from EventBridge and SQS to create optimized invalidations
 */
exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        // Process different event sources
        let invalidationPaths = [];
        
        if (event.source === 'aws.s3') {
            invalidationPaths = await processS3Event(event);
        } else if (event.source === 'aws.codedeploy' || event.source === 'custom.app') {
            invalidationPaths = await processDeploymentEvent(event);
        } else if (event.Records) {
            // SQS batch processing
            invalidationPaths = await processSQSBatch(event);
        }
        
        if (invalidationPaths.length === 0) {
            console.log('No invalidation paths to process');
            return { statusCode: 200, body: 'No invalidation needed' };
        }
        
        // Optimize paths using intelligent grouping
        const optimizedPaths = optimizeInvalidationPaths(invalidationPaths);
        console.log('Optimized paths:', optimizedPaths);
        
        // Create invalidation batches
        const batches = createBatches(optimizedPaths, BATCH_SIZE);
        console.log(`Created ${batches.length} batches for invalidation`);
        
        const results = [];
        for (const batch of batches) {
            const result = await createInvalidation(batch);
            results.push(result);
            
            // Log invalidation to DynamoDB
            await logInvalidation(result.Invalidation.Id, batch, event);
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Invalidations created successfully',
                invalidations: results.length,
                paths: optimizedPaths.length,
                results: results.map(r => ({
                    id: r.Invalidation.Id,
                    status: r.Invalidation.Status,
                    paths: r.Invalidation.InvalidationBatch.Paths.Items.length
                }))
            })
        };
        
    } catch (error) {
        console.error('Error processing invalidation:', error);
        
        // Send failed paths to DLQ for retry
        if (event.source && invalidationPaths && invalidationPaths.length > 0) {
            await sendToDeadLetterQueue(invalidationPaths, error);
        }
        
        throw error;
    }
};

/**
 * Process S3 object change events
 * Implements intelligent path selection based on content type
 */
async function processS3Event(event) {
    const paths = [];
    
    if (event.detail && event.detail.object) {
        const objectKey = event.detail.object.key;
        const eventName = event['detail-type'];
        
        console.log(`Processing S3 event: ${eventName} for object: ${objectKey}`);
        
        // Smart path invalidation based on content type
        if (objectKey.endsWith('.html')) {
            paths.push(`/${objectKey}`);
            // Also invalidate directory index
            if (objectKey.includes('/')) {
                const dir = objectKey.substring(0, objectKey.lastIndexOf('/'));
                paths.push(`/${dir}/`);
            }
        } else if (objectKey.match(/\.(css|js|json)$/)) {
            // Invalidate specific asset
            paths.push(`/${objectKey}`);
            
            // For CSS/JS changes, also invalidate HTML pages that might reference them
            if (objectKey.includes('css/') || objectKey.includes('js/')) {
                paths.push('/index.html');
                paths.push('/');
            }
        } else if (objectKey.match(/\.(jpg|jpeg|png|gif|webp|svg)$/)) {
            // Image invalidation
            paths.push(`/${objectKey}`);
        } else {
            // Generic file - invalidate the specific path
            paths.push(`/${objectKey}`);
        }
    }
    
    return [...new Set(paths)]; // Remove duplicates
}

/**
 * Process deployment events
 * Implements comprehensive invalidation for application deployments
 */
async function processDeploymentEvent(event) {
    console.log('Processing deployment event');
    
    // For deployment events, invalidate common paths
    const deploymentPaths = [
        '/',
        '/index.html',
        '/css/*',
        '/js/*',
        '/api/*'
    ];
    
    // If deployment includes specific file changes, add them
    if (event.detail && event.detail.changedFiles) {
        event.detail.changedFiles.forEach(file => {
            deploymentPaths.push(`/${file}`);
        });
    }
    
    return deploymentPaths;
}

/**
 * Process SQS batch messages
 * Aggregates invalidation paths from multiple messages
 */
async function processSQSBatch(event) {
    const paths = [];
    
    for (const record of event.Records) {
        try {
            const body = JSON.parse(record.body);
            if (body.paths && Array.isArray(body.paths)) {
                paths.push(...body.paths);
            }
        } catch (error) {
            console.error('Error parsing SQS message:', error);
        }
    }
    
    return [...new Set(paths)];
}

/**
 * Optimize invalidation paths to reduce costs
 * Removes redundant paths and applies intelligent grouping
 */
function optimizeInvalidationPaths(paths) {
    // Remove redundant paths and optimize patterns
    const optimized = new Set();
    const sorted = paths.sort();
    
    for (const path of sorted) {
        let isRedundant = false;
        
        // Check if this path is covered by an existing wildcard
        for (const existing of optimized) {
            if (existing.endsWith('/*') && path.startsWith(existing.slice(0, -1))) {
                isRedundant = true;
                break;
            }
        }
        
        if (!isRedundant) {
            optimized.add(path);
        }
    }
    
    return Array.from(optimized);
}

/**
 * Create batches of paths for invalidation
 * Ensures batches don't exceed CloudFront limits
 */
function createBatches(paths, batchSize) {
    const batches = [];
    for (let i = 0; i < paths.length; i += batchSize) {
        batches.push(paths.slice(i, i + batchSize));
    }
    return batches;
}

/**
 * Create CloudFront invalidation
 * Uses AWS SDK to create invalidation with proper error handling
 */
async function createInvalidation(paths) {
    const params = {
        DistributionId: DISTRIBUTION_ID,
        InvalidationBatch: {
            Paths: {
                Quantity: paths.length,
                Items: paths
            },
            CallerReference: `invalidation-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
        }
    };
    
    console.log('Creating invalidation for paths:', paths);
    return await cloudfront.createInvalidation(params).promise();
}

/**
 * Log invalidation details to DynamoDB
 * Creates audit trail for cost tracking and analysis
 */
async function logInvalidation(invalidationId, paths, originalEvent) {
    const params = {
        TableName: TABLE_NAME,
        Item: {
            InvalidationId: invalidationId,
            Timestamp: new Date().toISOString(),
            Paths: paths,
            PathCount: paths.length,
            Source: originalEvent.source || 'unknown',
            EventType: originalEvent['detail-type'] || 'unknown',
            Status: 'InProgress',
            CreatedAt: new Date().toISOString(),
            TTL: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) // 30 days
        }
    };
    
    console.log('Logging invalidation to DynamoDB:', invalidationId);
    return await dynamodb.put(params).promise();
}

/**
 * Send failed invalidation paths to dead letter queue
 * Enables retry and manual intervention for failed invalidations
 */
async function sendToDeadLetterQueue(paths, error) {
    const message = {
        paths: paths,
        error: error.message,
        timestamp: new Date().toISOString(),
        retryable: true
    };
    
    const params = {
        QueueUrl: DLQ_URL,
        MessageBody: JSON.stringify(message)
    };
    
    console.log('Sending failed paths to DLQ:', paths);
    return await sqs.sendMessage(params).promise();
}