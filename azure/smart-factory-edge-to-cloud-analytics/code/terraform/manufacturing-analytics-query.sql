-- Stream Analytics Query for Manufacturing Analytics
-- This query processes real-time manufacturing telemetry data to detect
-- equipment anomalies, calculate OEE metrics, and trigger maintenance alerts

-- Equipment Anomaly Detection with Severity Classification
WITH AnomalyDetection AS (
    SELECT
        deviceId,
        timestamp,
        temperature,
        vibration,
        pressure,
        operationalStatus,
        productionCount,
        qualityScore,
        energyConsumption,
        -- Classify anomaly severity based on sensor thresholds
        CASE 
            WHEN temperature > 90 OR vibration > 1.0 OR pressure > 180 THEN 'CRITICAL'
            WHEN temperature > 80 OR vibration > 0.8 OR pressure > 170 THEN 'WARNING'
            WHEN qualityScore < 0.85 THEN 'QUALITY_ISSUE'
            WHEN energyConsumption > 120 THEN 'EFFICIENCY_CONCERN'
            ELSE 'NORMAL'
        END AS alertLevel,
        -- Calculate equipment health score
        (
            CASE 
                WHEN temperature <= 75 THEN 100
                WHEN temperature <= 85 THEN 85
                WHEN temperature <= 95 THEN 70
                ELSE 50
            END +
            CASE 
                WHEN vibration <= 0.3 THEN 100
                WHEN vibration <= 0.6 THEN 85
                WHEN vibration <= 1.0 THEN 70
                ELSE 50
            END +
            CASE 
                WHEN pressure <= 160 THEN 100
                WHEN pressure <= 170 THEN 85
                WHEN pressure <= 180 THEN 70
                ELSE 50
            END
        ) / 3.0 AS healthScore,
        System.Timestamp() AS processingTime
    FROM ManufacturingTelemetryInput
    WHERE operationalStatus IN ('running', 'warning', 'maintenance')
),

-- Operational Equipment Effectiveness (OEE) Calculation
-- OEE = Availability × Performance × Quality
OEEMetrics AS (
    SELECT
        deviceId,
        System.Timestamp() AS windowEnd,
        -- Availability: Percentage of time equipment is running
        (CAST(SUM(CASE WHEN operationalStatus = 'running' THEN 1 ELSE 0 END) AS float) / 
         CAST(COUNT(*) AS float)) * 100 AS availabilityPercent,
        
        -- Performance: Actual vs. target production rate
        AVG(CAST(productionCount AS float)) AS avgProduction,
        MAX(CAST(productionCount AS float)) AS maxProduction,
        
        -- Quality: Percentage of good parts produced
        AVG(CAST(qualityScore AS float)) * 100 AS qualityPercent,
        
        -- Overall metrics
        COUNT(*) AS totalReadings,
        SUM(CASE WHEN operationalStatus = 'running' THEN 1 ELSE 0 END) AS runningReadings,
        
        -- Energy efficiency metrics
        AVG(CAST(energyConsumption AS float)) AS avgEnergyConsumption,
        
        -- Temperature and vibration trends
        AVG(CAST(temperature AS float)) AS avgTemperature,
        MAX(CAST(temperature AS float)) AS maxTemperature,
        AVG(CAST(vibration AS float)) AS avgVibration,
        MAX(CAST(vibration AS float)) AS maxVibration,
        AVG(CAST(pressure AS float)) AS avgPressure,
        MAX(CAST(pressure AS float)) AS maxPressure
    FROM ManufacturingTelemetryInput
    GROUP BY deviceId, TumblingWindow(minute, 5)
),

-- Equipment Health Trend Analysis
HealthTrends AS (
    SELECT
        deviceId,
        AVG(healthScore) AS avgHealthScore,
        MIN(healthScore) AS minHealthScore,
        MAX(healthScore) AS maxHealthScore,
        -- Detect declining health trends
        CASE 
            WHEN AVG(healthScore) < 70 THEN 'DECLINING'
            WHEN AVG(healthScore) < 85 THEN 'STABLE'
            ELSE 'OPTIMAL'
        END AS healthTrend,
        System.Timestamp() AS windowEnd
    FROM AnomalyDetection
    GROUP BY deviceId, TumblingWindow(minute, 15)
),

-- Production Line Performance Analysis
ProductionLineMetrics AS (
    SELECT
        SUBSTRING(deviceId, 1, 6) AS productionLine, -- Extract line identifier (e.g., 'line-a')
        System.Timestamp() AS windowEnd,
        COUNT(DISTINCT deviceId) AS activeEquipmentCount,
        AVG(CAST(productionCount AS float)) AS lineProductionRate,
        AVG(CAST(qualityScore AS float)) * 100 AS lineQualityScore,
        AVG(CAST(energyConsumption AS float)) AS lineEnergyConsumption,
        SUM(CASE WHEN operationalStatus = 'running' THEN 1 ELSE 0 END) AS runningEquipmentCount
    FROM ManufacturingTelemetryInput
    GROUP BY SUBSTRING(deviceId, 1, 6), TumblingWindow(minute, 5)
)

-- Output 1: Critical and Warning Alerts for Immediate Action
SELECT
    deviceId,
    timestamp,
    alertLevel,
    temperature,
    vibration,
    pressure,
    qualityScore,
    energyConsumption,
    healthScore,
    CASE 
        WHEN alertLevel = 'CRITICAL' THEN 'Equipment requires immediate shutdown and inspection'
        WHEN alertLevel = 'WARNING' THEN 'Equipment shows signs of degradation - schedule maintenance'
        WHEN alertLevel = 'QUALITY_ISSUE' THEN 'Quality control alert - check production parameters'
        WHEN alertLevel = 'EFFICIENCY_CONCERN' THEN 'Energy efficiency issue detected - optimize settings'
        ELSE 'Equipment operating normally'
    END AS alertMessage,
    processingTime
INTO ManufacturingAlertsOutput
FROM AnomalyDetection
WHERE alertLevel IN ('CRITICAL', 'WARNING', 'QUALITY_ISSUE', 'EFFICIENCY_CONCERN');

-- Output 2: OEE Metrics for Dashboard Visualization
SELECT
    deviceId,
    windowEnd,
    availabilityPercent,
    -- Calculate performance as percentage of maximum observed production
    CASE 
        WHEN maxProduction > 0 THEN (avgProduction / maxProduction) * 100
        ELSE 0
    END AS performancePercent,
    qualityPercent,
    -- Calculate overall OEE score
    (availabilityPercent * 
     CASE WHEN maxProduction > 0 THEN (avgProduction / maxProduction) * 100 ELSE 0 END * 
     qualityPercent) / 10000 AS oeeScore,
    avgProduction,
    maxProduction,
    totalReadings,
    runningReadings,
    avgEnergyConsumption,
    avgTemperature,
    maxTemperature,
    avgVibration,
    maxVibration,
    avgPressure,
    maxPressure
INTO OEEMetricsOutput
FROM OEEMetrics;

-- Output 3: Equipment Health Trends for Predictive Maintenance
SELECT
    deviceId,
    avgHealthScore,
    minHealthScore,
    maxHealthScore,
    healthTrend,
    CASE 
        WHEN healthTrend = 'DECLINING' THEN 'Schedule preventive maintenance within 24 hours'
        WHEN healthTrend = 'STABLE' THEN 'Monitor equipment condition closely'
        ELSE 'Equipment health is optimal'
    END AS maintenanceRecommendation,
    windowEnd
INTO HealthTrendsOutput
FROM HealthTrends
WHERE healthTrend IN ('DECLINING', 'STABLE');

-- Output 4: Production Line Performance Summary
SELECT
    productionLine,
    windowEnd,
    activeEquipmentCount,
    runningEquipmentCount,
    -- Calculate line efficiency
    CASE 
        WHEN activeEquipmentCount > 0 THEN 
            (CAST(runningEquipmentCount AS float) / CAST(activeEquipmentCount AS float)) * 100
        ELSE 0
    END AS lineEfficiencyPercent,
    lineProductionRate,
    lineQualityScore,
    lineEnergyConsumption,
    -- Classify line performance
    CASE 
        WHEN lineQualityScore >= 95 AND lineProductionRate >= 120 THEN 'EXCELLENT'
        WHEN lineQualityScore >= 90 AND lineProductionRate >= 100 THEN 'GOOD'
        WHEN lineQualityScore >= 85 AND lineProductionRate >= 80 THEN 'AVERAGE'
        ELSE 'NEEDS_IMPROVEMENT'
    END AS linePerformanceRating
INTO ProductionLineMetricsOutput
FROM ProductionLineMetrics;