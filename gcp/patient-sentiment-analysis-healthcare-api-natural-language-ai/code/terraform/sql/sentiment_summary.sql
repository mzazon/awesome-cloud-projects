SELECT 
  overall_sentiment,
  COUNT(*) as total_records,
  ROUND(AVG(sentiment_score), 3) as avg_sentiment_score,
  ROUND(AVG(magnitude), 3) as avg_magnitude,
  MIN(sentiment_score) as min_score,
  MAX(sentiment_score) as max_score,
  COUNT(DISTINCT patient_id) as unique_patients,
  DATE(processing_timestamp) as analysis_date,
  -- Sentiment distribution percentages
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage_of_total
FROM 
  `${project_id}.${dataset_id}.${table_id}`
WHERE 
  processing_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY 
  overall_sentiment, 
  DATE(processing_timestamp)
ORDER BY 
  analysis_date DESC, 
  overall_sentiment