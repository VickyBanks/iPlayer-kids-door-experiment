/*
Work to analyse kids door experiment ticket DATAFORCE-562
1. Find the users/visits in the experiment and label them as control or variant
2. Find only their first visit. For variant this is when they saw the door, for control this is the first time they had the exp id.
3. For variant group
    a. How many saw the door
    b. How many clicked adult, kids or left.
4. Link the first visits to the journey start/watched table
    a. Categorise their viewing as kids/adult
    b. Count number of starts and watched that were adult content and that were kids content
5. Analysis across variants
    a. visit_id, control or variant, number of STARTS to KIDS content - per browser statistical significance and uplift
    b. visit_id, control or variant, number of COMPLETES to KIDS content - per browser statistical significance and uplift
6. Analysis within variant
    a. visit_id, kids or adult door, number of STARTS to KIDS content - per browser statistical significance and uplift
a. visit_id, kids or adult door, number of completes to KIDS content - per browser statistical significance and uplift
*/

-- Create temp tables
CREATE TEMP TABLE vb_door_exp_group AS
with
    -- set dt so it doesn't need repeating
    door_exp_dt AS (
        SELECT 20200702 as dt
    )
SELECT DISTINCT dt,
                visit_id,
                CASE
                    WHEN user_experience ILIKE '%control%' THEN 'control'
                    WHEN user_experience ILIKE '%front-door%' THEN 'front-door'
                    ELSE 'unknown' END AS exp_group,
                dt || visit_id         as dist_visit_id
FROM s3_audience.publisher
WHERE dt > (SELECT dt FROM door_exp_dt)
  AND user_experience ILIKE '%iplwb_cb16%'
  AND destination = 'PS_IPLAYER';

SELECT exp_group, count(DISTINCT dt||visit_id) as num_visits FROM vb_door_exp_group GROUP BY 1;
------
CREATE TEMP TABLE vb_exp_door_seen AS
with
    -- set dt so it doesn't need repeating
    door_exp_dt AS (
        SELECT 20200702 as dt
    ),
    -- Get all the impressions on each door
    door_impr AS (
        SELECT DISTINCT dt, visit_id, container, attribute, publisher_impressions
                            FROM s3_audience.publisher
                            WHERE dt > (SELECT dt FROM door_exp_dt)
                              AND container = 'kids-experiment-door'
                              AND destination = 'PS_IPLAYER'
                              AND publisher_impressions = 1
        ),
     -- Get each visit in the exp (control and variant) and their impression on the door or not.
     door_impr_all_visits AS (
        SELECT DISTINCT a.dist_visit_id,
                        a.exp_group,
                        b.container,
                        ISNULL(b.attribute, 'no-door') as door_seen,
                        b.publisher_impressions
        FROM vb_door_exp_group a
                 LEFT JOIN door_impr b
                           ON a.dist_visit_id = b.dt || b.visit_id
    )
    -- Summarise the number of visits who saw each door
SELECT exp_group,
       door_seen,
       count(dist_visit_id) as num_visits_saw_door
FROM door_impr_all_visits
GROUP BY 1, 2
ORDER BY 1, 2;


SELECT *
FROM vb_exp_door_seen;

DROP TABLE vb_exp_door_clicked;
CREATE TEMP TABLE vb_exp_door_clicked AS
with door_exp_dt AS (
    SELECT 20200702 as dt
),
     -- Find the number of clicks to each door for the experimental group, or no door for control
     door_clicks AS (
         SELECT DISTINCT a.dist_visit_id,
                         a.exp_group,
                         b.container,
                         ISNULL(b.attribute, 'no-door') as door_clicked,
                         b.publisher_impressions
         FROM vb_door_exp_group a
                  LEFT JOIN (SELECT DISTINCT dt, visit_id, container, attribute, publisher_impressions
                             FROM s3_audience.publisher
                             WHERE dt > (SELECT dt FROM door_exp_dt)
                               AND container = 'kids-experiment-door'
                               AND destination = 'PS_IPLAYER'
                               AND publisher_clicks = 1) b
                            ON a.dist_visit_id = b.dt || b.visit_id
     )
     -- Summarise the number of visits who clicked each door
SELECT exp_group,
       door_clicked,
       count(dist_visit_id) as num_visits_clicked_door
FROM door_clicks
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT *
FROM vb_exp_door_clicked;

with door_exp_dt AS (
    SELECT 20200702 as dt
),
     -- Get vmb info
     vmb AS (
         SELECT DISTINCT master_brand_name, brand_title, series_title, episode_title, episode_id
         FROM prez.scv_vmb
     ),
     door_clicks AS (
         SELECT DISTINCT a.dist_visit_id,
                         a.exp_group,
                         b.container,
                         ISNULL(b.attribute, 'no-door') as door_clicked,
                         b.publisher_impressions
         FROM vb_door_exp_group a
                  LEFT JOIN (SELECT DISTINCT dt, visit_id, container, attribute, publisher_impressions
                             FROM s3_audience.publisher
                             WHERE dt > (SELECT dt FROM door_exp_dt)
                               AND container = 'kids-experiment-door'
                               AND destination = 'PS_IPLAYER'
                               AND publisher_clicks = 1) b
                            ON a.dist_visit_id = b.dt || b.visit_id
     ),
     -- Get the episodes they viewed, label as kids or adult masterbrand, and the start/complete flags
     eps_viewed AS (
         SELECT a.dt,
                a.dt || a.visit_id                                              AS dist_visit_id,
                b.exp_group,
                CASE
                    WHEN c.master_brand_name in ('CBBC', 'CBeebies') THEN 'kids_content'
                    ELSE 'adult_content' END                                    as master_brand_name,
                ISNULL(d.door_clicked, 'no_click')                              AS door_clicked,
                a.content_id,
                CASE WHEN a.start_flag = 'iplxp-ep-started' THEN 1 ELSE 0 END   AS start_flag,
                CASE WHEN a.watched_flag = 'iplxp-ep-watched' THEN 1 ELSE 0 END AS watched_flag
         FROM vb_door_exp_group b
                  LEFT JOIN central_insights_sandbox.dataforce_journey_start_watch_complete a
                            on a.dt || a.visit_id = b.dist_visit_id
                  JOIN vmb c on a.content_id = c.episode_id
                  LEFT JOIN door_clicks d ON a.dt || a.visit_id = d.dist_visit_id
         WHERE a.dt > (SELECT dt FROM door_exp_dt)
     )
SELECT exp_group,
       door_clicked,
       master_brand_name,
       count(dist_visit_id)         AS num_visits_clicked,
       ISNULL(sum(start_flag), 0)   as num_starts,
       ISNULL(sum(watched_flag), 0) as num_completes
FROM eps_viewed
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
;
