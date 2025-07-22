-- Stream Analytics Query for Video Content Moderation
-- This query processes video frame events from Event Hubs and applies content moderation logic
-- The query simulates AI Vision API calls and implements configurable threshold-based filtering

-- Step 1: Process incoming video frame events and validate required fields
WITH ProcessedFrames AS (
    SELECT 
        videoId,
        frameUrl,
        timestamp,
        userId,
        channelId,
        CAST(System.Timestamp() AS datetime) AS ProcessingTime
    FROM VideoFrameInput
    WHERE 
        -- Ensure required fields are present and valid
        videoId IS NOT NULL AND
        frameUrl IS NOT NULL AND
        timestamp IS NOT NULL AND
        userId IS NOT NULL AND
        channelId IS NOT NULL AND
        LEN(videoId) > 0 AND
        LEN(frameUrl) > 0
),

-- Step 2: Simulate AI Vision content moderation analysis
-- In production, this would be replaced with UDF calls to Azure AI Vision REST API
ModerationAnalysis AS (
    SELECT 
        videoId,
        frameUrl,
        timestamp,
        userId,
        channelId,
        ProcessingTime,
        
        -- Simulate adult content scoring based on video ID hash
        -- Real implementation would call Azure AI Vision Content Moderation API
        CASE 
            WHEN (LEN(videoId) + DATEDIFF(second, '1970-01-01', ProcessingTime)) % 10 < 2 THEN 0.85  -- 20% flagged as adult
            WHEN (LEN(videoId) + DATEDIFF(second, '1970-01-01', ProcessingTime)) % 10 < 4 THEN 0.60  -- Additional 20% moderate adult
            ELSE 0.15  -- 60% low adult score
        END AS adultScore,
        
        -- Simulate racy content scoring
        CASE 
            WHEN (LEN(videoId) + DATEDIFF(second, '1970-01-01', ProcessingTime)) % 13 < 1 THEN 0.75  -- 8% flagged as racy
            WHEN (LEN(videoId) + DATEDIFF(second, '1970-01-01', ProcessingTime)) % 13 < 3 THEN 0.50  -- Additional 15% moderate racy
            ELSE 0.10  -- 77% low racy score
        END AS racyScore,
        
        -- Simulate violence content scoring
        CASE 
            WHEN (LEN(videoId) + DATEDIFF(second, '1970-01-01', ProcessingTime)) % 15 < 1 THEN 0.80  -- 7% flagged as violent
            ELSE 0.05  -- 93% low violence score
        END AS violenceScore,
        
        -- Calculate confidence level based on frame quality indicators
        CASE 
            WHEN LEN(frameUrl) > 100 THEN 0.95  -- High confidence for detailed URLs
            WHEN LEN(frameUrl) > 50 THEN 0.85   -- Medium confidence
            ELSE 0.70  -- Lower confidence for short URLs
        END AS confidenceLevel
    FROM ProcessedFrames
),

-- Step 3: Apply business rules and determine moderation decisions
ModerationDecisions AS (
    SELECT 
        videoId,
        frameUrl,
        timestamp,
        userId,
        channelId,
        ProcessingTime,
        adultScore,
        racyScore,
        violenceScore,
        confidenceLevel,
        
        -- Determine moderation action based on configurable thresholds
        CASE 
            WHEN adultScore > ${adult_block_threshold} OR 
                 racyScore > ${racy_block_threshold} OR 
                 violenceScore > 0.70 THEN 'BLOCKED'
            WHEN adultScore > ${adult_review_threshold} OR 
                 racyScore > ${racy_review_threshold} OR 
                 violenceScore > 0.50 THEN 'REVIEW'
            ELSE 'APPROVED'
        END AS moderationDecision,
        
        -- Flag requiring immediate action (blocking or escalation)
        CASE 
            WHEN adultScore > ${adult_block_threshold} OR 
                 racyScore > ${racy_block_threshold} OR 
                 violenceScore > 0.70 THEN 1
            ELSE 0
        END AS requiresAction,
        
        -- Generate content flags array based on scores
        CASE 
            WHEN adultScore > ${adult_review_threshold} THEN 'adult'
            ELSE ''
        END AS adultFlag,
        
        CASE 
            WHEN racyScore > ${racy_review_threshold} THEN 'racy'
            ELSE ''
        END AS racyFlag,
        
        CASE 
            WHEN violenceScore > 0.50 THEN 'violence'
            ELSE ''
        END AS violenceFlag,
        
        -- Calculate overall risk score
        (adultScore * 0.4 + racyScore * 0.3 + violenceScore * 0.3) AS overallRiskScore
    FROM ModerationAnalysis
),

-- Step 4: Add metadata and prepare final output
FinalResults AS (
    SELECT 
        videoId,
        frameUrl,
        timestamp,
        userId,
        channelId,
        ProcessingTime,
        adultScore,
        racyScore,
        violenceScore,
        confidenceLevel,
        moderationDecision,
        requiresAction,
        overallRiskScore,
        
        -- Create content flags array (filtering out empty flags)
        ARRAY(
            SELECT value 
            FROM (VALUES (adultFlag), (racyFlag), (violenceFlag)) AS flags(value)
            WHERE value != ''
        ) AS contentFlags,
        
        -- Add processing metadata
        'stream-analytics' AS processedBy,
        'v1.0' AS processingVersion,
        
        -- Add severity level for prioritization
        CASE 
            WHEN overallRiskScore > 0.8 THEN 'CRITICAL'
            WHEN overallRiskScore > 0.6 THEN 'HIGH'
            WHEN overallRiskScore > 0.4 THEN 'MEDIUM'
            ELSE 'LOW'
        END AS severityLevel,
        
        -- Generate unique processing ID for tracking
        CONCAT(videoId, '-', FORMAT(ProcessingTime, 'yyyyMMddHHmmss'), '-', ABS(CHECKSUM(frameUrl)) % 10000) AS processingId
    FROM ModerationDecisions
)

-- Final SELECT: Output processed results with all required fields
SELECT 
    processingId,
    videoId,
    frameUrl,
    timestamp,
    userId,
    channelId,
    ProcessingTime,
    adultScore,
    racyScore,
    violenceScore,
    confidenceLevel,
    moderationDecision,
    requiresAction,
    overallRiskScore,
    contentFlags,
    severityLevel,
    processedBy,
    processingVersion,
    
    -- Add partition information for debugging
    System.Timestamp() AS outputTimestamp,
    
    -- Add batch processing information
    COUNT(*) OVER (
        PARTITION BY TumblingWindow(minute, 1)
    ) AS batchFrameCount,
    
    -- Add flagged content percentage for monitoring
    CAST(SUM(requiresAction) OVER (
        PARTITION BY TumblingWindow(minute, 5)
    ) AS float) / COUNT(*) OVER (
        PARTITION BY TumblingWindow(minute, 5)
    ) AS flaggedContentPercentage

INTO ModerationOutput
FROM FinalResults

-- Add time-based filtering to prevent processing very old events
WHERE ProcessingTime > DATEADD(hour, -24, System.Timestamp())

-- Optional: Add additional outputs for real-time alerting
-- Uncomment and configure Logic App output for immediate alerts

-- SELECT 
--     processingId,
--     videoId,
--     moderationDecision,
--     overallRiskScore,
--     contentFlags,
--     severityLevel,
--     ProcessingTime
-- INTO AlertOutput
-- FROM FinalResults
-- WHERE requiresAction = 1  -- Only send alerts for content requiring action