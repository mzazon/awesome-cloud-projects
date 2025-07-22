const AWS = require('aws-sdk');
const geoip = require('geoip-lite');

const cloudwatch = new AWS.CloudWatch();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const kinesis = new AWS.Kinesis();

const METRICS_TABLE = process.env.METRICS_TABLE;
const PROCESSED_STREAM = process.env.PROCESSED_STREAM;

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
        userAgents: {}
    };
    
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
        processedRecords: processedRecords.length
    };
};

async function processLogEntry(logEntry, metrics) {
    try {
        // Parse CloudFront log format (tab-separated)
        const fields = logEntry.split('\t');
        
        if (fields.length < 20) {
            return null; // Invalid log entry
        }
        
        const timestamp = `${fields[0]} ${fields[1]}`;
        const edgeLocation = fields[2];
        const bytesDownloaded = parseInt(fields[3]) || 0;
        const clientIp = fields[4];
        const method = fields[5];
        const host = fields[6];
        const uri = fields[7];
        const status = parseInt(fields[8]) || 0;
        const referer = fields[9];
        const userAgent = fields[10];
        const queryString = fields[11];
        const cookie = fields[12];
        const edgeResultType = fields[13];
        const edgeRequestId = fields[14];
        const hostHeader = fields[15];
        const protocol = fields[16];
        const bytesUploaded = parseInt(fields[17]) || 0;
        const timeTaken = parseFloat(fields[18]) || 0;
        const forwardedFor = fields[19];
        
        // Geo-locate client IP
        const geoData = geoip.lookup(clientIp) || {};
        
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
        
        // Count by region
        const region = geoData.region || 'Unknown';
        metrics.regionCounts[region] = (metrics.regionCounts[region] || 0) + 1;
        
        // Count status codes
        metrics.statusCodes[status] = (metrics.statusCodes[status] || 0) + 1;
        
        // Simplified user agent tracking
        const uaCategory = categorizeUserAgent(userAgent);
        metrics.userAgents[uaCategory] = (metrics.userAgents[uaCategory] || 0) + 1;
        
        // Create enriched log entry
        const enrichedLog = {
            timestamp: new Date(timestamp).toISOString(),
            edgeLocation,
            clientIp,
            method,
            host,
            uri,
            status,
            bytesDownloaded,
            bytesUploaded,
            timeTaken,
            edgeResultType,
            userAgent: uaCategory,
            country: geoData.country || 'Unknown',
            region: geoData.region || 'Unknown',
            city: geoData.city || 'Unknown',
            referer: referer !== '-' ? referer : null,
            queryString: queryString !== '-' ? queryString : null,
            protocol,
            edgeRequestId,
            cacheHit: edgeResultType !== 'Miss',
            isError: status >= 400,
            responseSize: bytesDownloaded,
            requestSize: bytesUploaded,
            processingTime: Date.now()
        };
        
        return enrichedLog;
        
    } catch (error) {
        console.error('Error parsing log entry:', error);
        return null;
    }
}

function categorizeUserAgent(userAgent) {
    if (!userAgent || userAgent === '-') return 'Unknown';
    
    const ua = userAgent.toLowerCase();
    if (ua.includes('chrome')) return 'Chrome';
    if (ua.includes('firefox')) return 'Firefox';
    if (ua.includes('safari') && !ua.includes('chrome')) return 'Safari';
    if (ua.includes('edge')) return 'Edge';
    if (ua.includes('bot') || ua.includes('crawler')) return 'Bot';
    if (ua.includes('mobile')) return 'Mobile';
    
    return 'Other';
}

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
        } catch (error) {
            console.error('Error sending to Kinesis:', error);
        }
    }
}

async function storeMetrics(metrics) {
    const timestamp = new Date().toISOString();
    const ttl = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60); // 7 days
    
    try {
        await dynamodb.put({
            TableName: METRICS_TABLE,
            Item: {
                MetricId: `metrics-${Date.now()}`,
                Timestamp: timestamp,
                TotalRequests: metrics.totalRequests,
                TotalBytes: metrics.totalBytes,
                Errors4xx: metrics.errors4xx,
                Errors5xx: metrics.errors5xx,
                CacheMisses: metrics.cacheMisses,
                RegionCounts: metrics.regionCounts,
                StatusCodes: metrics.statusCodes,
                UserAgents: metrics.userAgents,
                TTL: ttl
            }
        }).promise();
    } catch (error) {
        console.error('Error storing metrics:', error);
    }
}

async function sendCloudWatchMetrics(metrics) {
    const metricData = [
        {
            MetricName: 'RequestCount',
            Value: metrics.totalRequests,
            Unit: 'Count',
            Timestamp: new Date()
        },
        {
            MetricName: 'BytesDownloaded',
            Value: metrics.totalBytes,
            Unit: 'Bytes',
            Timestamp: new Date()
        },
        {
            MetricName: 'ErrorRate4xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors4xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        },
        {
            MetricName: 'ErrorRate5xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors5xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        },
        {
            MetricName: 'CacheMissRate',
            Value: metrics.totalRequests > 0 ? (metrics.cacheMisses / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        }
    ];
    
    try {
        await cloudwatch.putMetricData({
            Namespace: 'CloudFront/RealTime',
            MetricData: metricData
        }).promise();
    } catch (error) {
        console.error('Error sending CloudWatch metrics:', error);
    }
}