const AWS = require('aws-sdk');

const cloudwatch = new AWS.CloudWatch();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const kinesis = new AWS.Kinesis();

const METRICS_TABLE = process.env.METRICS_TABLE;
const PROCESSED_STREAM = process.env.PROCESSED_STREAM;
const TTL_DAYS = parseInt(process.env.TTL_DAYS || '7');

/**
 * Lambda handler for processing CloudFront real-time logs
 * Processes log entries, enriches data, and sends metrics to various outputs
 */
exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const processedRecords = [];
    const metrics = {
        totalRequests: 0,
        totalBytes: 0,
        errors4xx: 0,
        errors5xx: 0,
        cacheMisses: 0,
        regionCounts: {},
        statusCodes: {},
        userAgents: {},
        edgeLocations: {}
    };
    
    try {
        for (const record of event.Records) {
            try {
                // Decode Kinesis data
                const data = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
                const logEntries = data.trim().split('\n');
                
                for (const logEntry of logEntries) {
                    const processedLog = await processLogEntry(logEntry, metrics);
                    if (processedLog) {
                        processedRecords.push(processedLog);
                    }
                }
            } catch (error) {
                console.error('Error processing record:', error);
            }
        }
        
        // Send processed records to output stream
        if (processedRecords.length > 0) {
            await sendToKinesis(processedRecords);
        }
        
        // Store aggregated metrics
        await storeMetrics(metrics);
        
        // Send CloudWatch metrics
        await sendCloudWatchMetrics(metrics);
        
        return {
            statusCode: 200,
            processedRecords: processedRecords.length,
            metrics: {
                totalRequests: metrics.totalRequests,
                totalBytes: metrics.totalBytes,
                errors4xx: metrics.errors4xx,
                errors5xx: metrics.errors5xx,
                cacheMisses: metrics.cacheMisses
            }
        };
        
    } catch (error) {
        console.error('Handler error:', error);
        throw error;
    }
};

/**
 * Process individual CloudFront log entry
 * Parses tab-separated format and enriches with geographic and analytics data
 */
async function processLogEntry(logEntry, metrics) {
    try {
        // Skip comment lines and empty lines
        if (!logEntry || logEntry.startsWith('#') || logEntry.trim() === '') {
            return null;
        }
        
        // Parse CloudFront log format (tab-separated)
        const fields = logEntry.split('\t');
        
        if (fields.length < 20) {
            console.warn('Invalid log entry (insufficient fields):', logEntry);
            return null;
        }
        
        const timestamp = `${fields[0]} ${fields[1]}`;
        const edgeLocation = fields[2] || 'Unknown';
        const bytesDownloaded = parseInt(fields[3]) || 0;
        const clientIp = fields[4] || '';
        const method = fields[5] || '';
        const host = fields[6] || '';
        const uri = fields[7] || '';
        const status = parseInt(fields[8]) || 0;
        const referer = fields[9] || '';
        const userAgent = fields[10] || '';
        const queryString = fields[11] || '';
        const cookie = fields[12] || '';
        const edgeResultType = fields[13] || '';
        const edgeRequestId = fields[14] || '';
        const hostHeader = fields[15] || '';
        const protocol = fields[16] || '';
        const bytesUploaded = parseInt(fields[17]) || 0;
        const timeTaken = parseFloat(fields[18]) || 0;
        const forwardedFor = fields[19] || '';
        
        // Basic geographic information from IP (simplified approach)
        const geoData = getGeoDataFromIP(clientIp);
        
        // Update metrics
        metrics.totalRequests++;
        metrics.totalBytes += bytesDownloaded;
        
        if (status >= 400 && status < 500) {
            metrics.errors4xx++;
        } else if (status >= 500) {
            metrics.errors5xx++;
        }
        
        if (edgeResultType === 'Miss') {
            metrics.cacheMisses++;
        }
        
        // Count by edge location
        const region = edgeLocation.substring(0, 3); // First 3 chars typically indicate region
        metrics.regionCounts[region] = (metrics.regionCounts[region] || 0) + 1;
        metrics.edgeLocations[edgeLocation] = (metrics.edgeLocations[edgeLocation] || 0) + 1;
        
        // Count status codes
        metrics.statusCodes[status] = (metrics.statusCodes[status] || 0) + 1;
        
        // Simplified user agent tracking
        const uaCategory = categorizeUserAgent(userAgent);
        metrics.userAgents[uaCategory] = (metrics.userAgents[uaCategory] || 0) + 1;
        
        // Create enriched log entry
        const enrichedLog = {
            timestamp: new Date(timestamp).toISOString(),
            edgeLocation,
            clientIp: anonymizeIP(clientIp), // Anonymize for privacy
            method,
            host,
            uri,
            status,
            bytesDownloaded,
            bytesUploaded,
            timeTaken,
            edgeResultType,
            userAgent: uaCategory,
            country: geoData.country,
            region: geoData.region,
            city: geoData.city,
            referer: referer !== '-' ? referer : null,
            queryString: queryString !== '-' ? queryString : null,
            protocol,
            edgeRequestId,
            cacheHit: edgeResultType !== 'Miss',
            isError: status >= 400,
            responseSize: bytesDownloaded,
            requestSize: bytesUploaded,
            processingTime: Date.now(),
            // Additional analytics fields
            isBot: isBot(userAgent),
            contentType: getContentTypeFromUri(uri),
            httpVersion: protocol.includes('HTTP/') ? protocol : 'HTTP/1.1',
            isSecure: protocol.toLowerCase().includes('https') || protocol.toLowerCase().includes('ssl')
        };
        
        return enrichedLog;
        
    } catch (error) {
        console.error('Error parsing log entry:', error, 'Entry:', logEntry);
        return null;
    }
}

/**
 * Categorize user agent into broad categories
 */
function categorizeUserAgent(userAgent) {
    if (!userAgent || userAgent === '-' || userAgent === '') return 'Unknown';
    
    const ua = userAgent.toLowerCase();
    
    // Bot detection
    if (ua.includes('bot') || ua.includes('crawler') || ua.includes('spider') || 
        ua.includes('scraper') || ua.includes('indexer')) {
        return 'Bot';
    }
    
    // Browser detection
    if (ua.includes('chrome') && !ua.includes('edge')) return 'Chrome';
    if (ua.includes('firefox')) return 'Firefox';
    if (ua.includes('safari') && !ua.includes('chrome')) return 'Safari';
    if (ua.includes('edge')) return 'Edge';
    if (ua.includes('opera')) return 'Opera';
    
    // Platform detection
    if (ua.includes('mobile') || ua.includes('android') || ua.includes('iphone')) return 'Mobile';
    if (ua.includes('tablet') || ua.includes('ipad')) return 'Tablet';
    
    // API clients
    if (ua.includes('curl') || ua.includes('wget') || ua.includes('postman')) return 'API Client';
    
    return 'Other';
}

/**
 * Simple geographic data extraction (placeholder implementation)
 * In production, use a proper GeoIP service or database
 */
function getGeoDataFromIP(ip) {
    // This is a simplified implementation
    // In production, integrate with MaxMind GeoIP2 or similar service
    
    if (!ip || ip === '-') {
        return { country: 'Unknown', region: 'Unknown', city: 'Unknown' };
    }
    
    // Basic IP range detection for common patterns
    if (ip.startsWith('10.') || ip.startsWith('192.168.') || ip.startsWith('172.')) {
        return { country: 'Private', region: 'Private', city: 'Private' };
    }
    
    // Simplified geographic inference (this is not accurate, just for demo)
    const firstOctet = parseInt(ip.split('.')[0]);
    if (firstOctet >= 1 && firstOctet <= 50) {
        return { country: 'US', region: 'North America', city: 'Unknown' };
    } else if (firstOctet >= 51 && firstOctet <= 100) {
        return { country: 'EU', region: 'Europe', city: 'Unknown' };
    } else if (firstOctet >= 101 && firstOctet <= 150) {
        return { country: 'AS', region: 'Asia', city: 'Unknown' };
    }
    
    return { country: 'Unknown', region: 'Unknown', city: 'Unknown' };
}

/**
 * Anonymize IP address for privacy compliance
 */
function anonymizeIP(ip) {
    if (!ip || ip === '-') return 'Unknown';
    
    const parts = ip.split('.');
    if (parts.length === 4) {
        // Zero out the last octet for IPv4
        return `${parts[0]}.${parts[1]}.${parts[2]}.0`;
    }
    
    // For IPv6 or other formats, return first part only
    return ip.split(':')[0] + ':xxxx';
}

/**
 * Detect if user agent represents a bot/crawler
 */
function isBot(userAgent) {
    if (!userAgent || userAgent === '-') return false;
    
    const ua = userAgent.toLowerCase();
    const botKeywords = [
        'bot', 'crawler', 'spider', 'scraper', 'indexer', 'fetcher',
        'googlebot', 'bingbot', 'slurp', 'duckduckbot', 'baiduspider',
        'yandexbot', 'facebookexternalhit', 'twitterbot', 'linkedinbot'
    ];
    
    return botKeywords.some(keyword => ua.includes(keyword));
}

/**
 * Infer content type from URI
 */
function getContentTypeFromUri(uri) {
    if (!uri || uri === '-') return 'Unknown';
    
    const lowerUri = uri.toLowerCase();
    
    if (lowerUri.includes('.html') || lowerUri.includes('.htm') || uri === '/') return 'HTML';
    if (lowerUri.includes('.css')) return 'CSS';
    if (lowerUri.includes('.js')) return 'JavaScript';
    if (lowerUri.includes('.json')) return 'JSON';
    if (lowerUri.includes('.xml')) return 'XML';
    if (lowerUri.includes('.png') || lowerUri.includes('.jpg') || lowerUri.includes('.jpeg') || 
        lowerUri.includes('.gif') || lowerUri.includes('.webp')) return 'Image';
    if (lowerUri.includes('.mp4') || lowerUri.includes('.avi') || lowerUri.includes('.mov')) return 'Video';
    if (lowerUri.includes('.mp3') || lowerUri.includes('.wav') || lowerUri.includes('.ogg')) return 'Audio';
    if (lowerUri.includes('.pdf')) return 'PDF';
    if (lowerUri.includes('/api/')) return 'API';
    
    return 'Other';
}

/**
 * Send processed records to Kinesis stream
 */
async function sendToKinesis(records) {
    const batchSize = 500; // Kinesis limit
    
    for (let i = 0; i < records.length; i += batchSize) {
        const batch = records.slice(i, i + batchSize);
        const kinesisRecords = batch.map(record => ({
            Data: JSON.stringify(record),
            PartitionKey: record.edgeLocation || 'default'
        }));
        
        try {
            await kinesis.putRecords({
                StreamName: PROCESSED_STREAM,
                Records: kinesisRecords
            }).promise();
            
            console.log(`Sent ${kinesisRecords.length} records to processed stream`);
        } catch (error) {
            console.error('Error sending to Kinesis:', error);
            throw error;
        }
    }
}

/**
 * Store aggregated metrics in DynamoDB
 */
async function storeMetrics(metrics) {
    const timestamp = new Date().toISOString();
    const ttl = Math.floor(Date.now() / 1000) + (TTL_DAYS * 24 * 60 * 60);
    const metricId = `metrics-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    
    try {
        await dynamodb.put({
            TableName: METRICS_TABLE,
            Item: {
                MetricId: metricId,
                Timestamp: timestamp,
                TotalRequests: metrics.totalRequests,
                TotalBytes: metrics.totalBytes,
                Errors4xx: metrics.errors4xx,
                Errors5xx: metrics.errors5xx,
                CacheMisses: metrics.cacheMisses,
                RegionCounts: metrics.regionCounts,
                StatusCodes: metrics.statusCodes,
                UserAgents: metrics.userAgents,
                EdgeLocations: metrics.edgeLocations,
                TTL: ttl,
                ProcessedAt: Date.now()
            }
        }).promise();
        
        console.log(`Stored metrics with ID: ${metricId}`);
    } catch (error) {
        console.error('Error storing metrics:', error);
        throw error;
    }
}

/**
 * Send custom metrics to CloudWatch
 */
async function sendCloudWatchMetrics(metrics) {
    const timestamp = new Date();
    
    const metricData = [
        {
            MetricName: 'RequestCount',
            Value: metrics.totalRequests,
            Unit: 'Count',
            Timestamp: timestamp
        },
        {
            MetricName: 'BytesDownloaded',
            Value: metrics.totalBytes,
            Unit: 'Bytes',
            Timestamp: timestamp
        },
        {
            MetricName: 'ErrorRate4xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors4xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: timestamp
        },
        {
            MetricName: 'ErrorRate5xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors5xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: timestamp
        },
        {
            MetricName: 'CacheMissRate',
            Value: metrics.totalRequests > 0 ? (metrics.cacheMisses / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: timestamp
        },
        {
            MetricName: 'ProcessingLatency',
            Value: Date.now() - timestamp.getTime(),
            Unit: 'Milliseconds',
            Timestamp: timestamp
        }
    ];
    
    // Add region-specific metrics
    Object.entries(metrics.regionCounts).forEach(([region, count]) => {
        metricData.push({
            MetricName: 'RequestsByRegion',
            Value: count,
            Unit: 'Count',
            Dimensions: [
                {
                    Name: 'Region',
                    Value: region
                }
            ],
            Timestamp: timestamp
        });
    });
    
    // Add user agent metrics
    Object.entries(metrics.userAgents).forEach(([userAgent, count]) => {
        metricData.push({
            MetricName: 'RequestsByUserAgent',
            Value: count,
            Unit: 'Count',
            Dimensions: [
                {
                    Name: 'UserAgent',
                    Value: userAgent
                }
            ],
            Timestamp: timestamp
        });
    });
    
    try {
        // CloudWatch has a limit of 20 metrics per request
        const batchSize = 20;
        for (let i = 0; i < metricData.length; i += batchSize) {
            const batch = metricData.slice(i, i + batchSize);
            
            await cloudwatch.putMetricData({
                Namespace: 'CloudFront/RealTime',
                MetricData: batch
            }).promise();
        }
        
        console.log(`Sent ${metricData.length} metrics to CloudWatch`);
    } catch (error) {
        console.error('Error sending CloudWatch metrics:', error);
        throw error;
    }
}