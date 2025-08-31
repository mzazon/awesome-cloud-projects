-- BigQuery view for aggregated content performance metrics by content type
-- This view provides summary statistics to identify high-performing content categories
SELECT 
    content_type,
    COUNT(*) as total_content,
    AVG(page_views) as avg_page_views,
    AVG(engagement_rate) as avg_engagement,
    AVG(conversion_rate) as avg_conversion,
    AVG(content_score) as avg_score,
    SUM(social_shares) as total_shares,
    MIN(publish_date) as earliest_publish_date,
    MAX(publish_date) as latest_publish_date
FROM `${project_id}.${dataset_name}.${table_name}`
GROUP BY content_type
ORDER BY avg_score DESC