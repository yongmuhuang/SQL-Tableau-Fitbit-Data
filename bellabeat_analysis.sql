/* 
===========================================================
Bellabeat Case Study - Fitbit Data Analysis (SQL Script)
Author: [Your Name]
Purpose: Analyze smart device usage patterns from Fitbit dataset 
         and generate insights to inform Bellabeat marketing strategies.
===========================================================
*/

/* --------------------------------------------------------
1. DATA PREPARATION
-------------------------------------------------------- */

/* 
NOTE: CSV files were uploaded into Google BigQuery.
Date/time columns were reformatted for upload compatibility.
Example: converting '4/3/2016 4:01:10 PM' to string before import.
*/

/* --------------------------------------------------------
2. DUPLICATE CHECKS & REMOVAL
-------------------------------------------------------- */

/* Check for duplicates by unique identifiers (Id + ActivityDate) */
SELECT 
    Id, 
    ActivityDate, 
    COUNT(*) AS occurrences
FROM project.dataset.DailyActivity_MarchApril
GROUP BY Id, ActivityDate
HAVING occurrences > 1;

/* Example: Check duplicates in MinuteSleep data */
SELECT 
    Id, 
    Date, 
    COUNT(*) AS occurrences
FROM project.dataset.MinuteSleep_MarchApril
GROUP BY Id, Date, Value, LogId
HAVING occurrences > 1;

/* Remove duplicates using DISTINCT */
CREATE OR REPLACE TABLE project.dataset.MinuteSleep_MarchApril_Deduped AS
SELECT DISTINCT *
FROM project.dataset.MinuteSleep_MarchApril;

/* Repeat deduplication for other affected datasets:
   - MinuteSleep_AprilMay
   - SleepDay
*/

/* Convert SleepDay string column to DATE format */
CREATE OR REPLACE TABLE project.dataset.SleepDay_AprilMay_Deduped AS
SELECT
    *,
    DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', SleepDay)) AS Date
FROM project.dataset.SleepDay_AprilMay_Deduped_Raw;

/* --------------------------------------------------------
3. MERGE TIME PERIODS
-------------------------------------------------------- */

-- Combine March–April and April–May DailyActivity data
CREATE OR REPLACE TABLE project.dataset.DailyActivity_Complete AS
SELECT * FROM project.dataset.DailyActivity_MarchApril
UNION ALL
SELECT * FROM project.dataset.DailyActivity_AprilMay;

-- Combine HR data from both periods
CREATE OR REPLACE TABLE project.dataset.HRSeconds_Complete AS
SELECT * FROM project.dataset.HRSeconds_MarchApril
UNION ALL
SELECT * FROM project.dataset.HRSeconds_AprilMay;

-- Checked the number of participants in each time period
SELECT ActivityDate,
  COUNT (DISTINCT Id) AS num_users
FROM project.dataset.DailyActivity_MarchApril 
GROUP BY ActivityDate
ORDER BY ActivityDate;

/* --------------------------------------------------------
4. DESCRIPTIVE STATISTICS
-------------------------------------------------------- */

-- Average steps per user (filter out 0 steps)
SELECT 
    Id, 
    ROUND(AVG(TotalSteps), 2) AS avg_steps
FROM project.dataset.DailyActivity_Complete
WHERE TotalSteps != 0
GROUP BY Id
ORDER BY avg_steps DESC;

-- Similar queries can be used for calories, minutes asleep, and heart rate

/* --------------------------------------------------------
5. ACTIVITY LEVEL SEGMENTATION
-------------------------------------------------------- */

WITH user_steps AS (
    SELECT 
        Id,
        AVG(TotalSteps) AS avg_steps
    FROM project.dataset.DailyActivity_Complete
    GROUP BY Id
)
SELECT
    CASE
        WHEN avg_steps < 5000 THEN 'Sedentary'
        WHEN avg_steps < 7000 THEN 'Low Active'
        WHEN avg_steps < 10000 THEN 'Healthy Active'
        WHEN avg_steps < 12500 THEN 'High Active'
        ELSE 'Fitness-Focused'
    END AS activity_level,
    COUNT(*) AS user_count
FROM user_steps
GROUP BY activity_level
ORDER BY user_count DESC;

/* --------------------------------------------------------
6. WEEKDAY VS. WEEKEND MOVERS
-------------------------------------------------------- */

WITH with_day_of_week AS (
    SELECT
        Id,
        ActivityDate,
        EXTRACT(DAYOFWEEK FROM ActivityDate) AS day_of_week,
        TotalSteps
    FROM project.dataset.DailyActivity_Complete
),
steps_summary AS (
    SELECT
        Id,
        SUM(CASE WHEN day_of_week BETWEEN 2 AND 6 THEN TotalSteps ELSE 0 END) AS weekday_steps,
        SUM(TotalSteps) AS total_steps
    FROM with_day_of_week
    GROUP BY Id
),
categorized_users AS (
    SELECT 
        Id,
        weekday_steps, 
        total_steps, 
        SAFE_DIVIDE(weekday_steps, total_steps) AS weekday_ratio,
        CASE 
            WHEN SAFE_DIVIDE(weekday_steps, total_steps) < 0.69 THEN 'Weekend Mover'  -- <69% steps on weekdays
            WHEN SAFE_DIVIDE(weekday_steps, total_steps) > 0.73 THEN 'Weekday Mover'  -- >73% steps on weekdays
            ELSE 'Balanced Mover'  -- 69–73% range
        END AS exercise_pattern
    FROM steps_summary
)
SELECT exercise_pattern, COUNT(*) AS user_count
FROM categorized_users
GROUP BY exercise_pattern;

/* --------------------------------------------------------
7. DAY-OF-WEEK TRENDS
-------------------------------------------------------- */

-- Average steps by day of week
SELECT 
    FORMAT_DATE('%A', ActivityDate) AS day_of_week,
    ROUND(AVG(TotalSteps)) AS avg_steps
FROM project.dataset.DailyActivity_Complete
WHERE TotalSteps != 0
GROUP BY day_of_week
ORDER BY avg_steps DESC;

-- Average sleep by day of week
SELECT 
    FORMAT_DATE('%A', Date) AS day_of_week,
    ROUND(AVG(TotalMinutesAsleep)) AS avg_asleep,
    ROUND(AVG(TotalTimeInBed)) AS avg_in_bed
FROM project.dataset.SleepDay_AprilMay_Deduped
GROUP BY day_of_week;

/* --------------------------------------------------------
8. SLEEP VS. STEPS CORRELATION
-------------------------------------------------------- */

WITH merged_step_sleep AS (
    SELECT
        s.Id,
        s.Date,
        d.TotalSteps,
        s.TotalMinutesAsleep,
        s.TotalTimeInBed
    FROM project.dataset.SleepDay_AprilMay_Deduped s    -- MarchApril has no corresponding dataset
    INNER JOIN project.dataset.DailyActivity_AprilMay d 
        ON s.Id = d.Id AND s.Date = d.ActivityDate
)
SELECT
    ROUND(CORR(TotalSteps, TotalMinutesAsleep), 2) AS corr_step_asleep,
    ROUND(CORR(TotalSteps, TotalTimeInBed), 2) AS corr_step_bed
FROM merged_step_sleep;

/* --------------------------------------------------------
9. WEEKLY TRENDS
-------------------------------------------------------- */

SELECT   
    EXTRACT(WEEK FROM ActivityDate) AS week_num,
    ROUND(AVG(TotalSteps)) AS avg_steps,
    COUNT(DISTINCT ActivityDate) AS num_of_days
FROM project.dataset.DailyActivity_Complete
GROUP BY week_num
ORDER BY week_num;
