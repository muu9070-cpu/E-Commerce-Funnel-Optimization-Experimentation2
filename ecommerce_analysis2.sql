USE ecommerce_analysis;

WITH event_base AS (
    SELECT
        user_id,
        user_session,
        event_type,
        STR_TO_DATE(
            REPLACE(event_time, ' UTC', ''),
            '%Y-%m-%d %H:%i:%s'
        ) AS event_ts
    FROM ecommerce
    WHERE user_id IS NOT NULL
      AND user_session IS NOT NULL
),

-- Step 1: 每个用户 Session 的首次 View
first_view AS (
    SELECT
        user_id,
        user_session,
        MIN(event_ts) AS first_view_time
    FROM event_base
    WHERE event_type = 'view'
    GROUP BY user_id, user_session
),

-- Step 2: 首次 View 之后的首次 Cart
cart_after_view AS (
    SELECT
        v.user_id,
        v.user_session,
        v.first_view_time,
        MIN(e.event_ts) AS first_cart_time
    FROM first_view v
    LEFT JOIN event_base e
        ON v.user_id = e.user_id
       AND v.user_session = e.user_session
       AND e.event_type = 'cart'
       AND e.event_ts > v.first_view_time
    GROUP BY
        v.user_id,
        v.user_session,
        v.first_view_time
),

-- Step 3: 首次 Cart 之后的首次 Purchase
purchase_after_cart AS (
    SELECT
        c.user_id,
        c.user_session,
        c.first_view_time,
        c.first_cart_time,
        MIN(e.event_ts) AS first_purchase_time
    FROM cart_after_view c
    LEFT JOIN event_base e
        ON c.user_id = e.user_id
       AND c.user_session = e.user_session
       AND e.event_type = 'purchase'
       AND c.first_cart_time IS NOT NULL
       AND e.event_ts > c.first_cart_time
    GROUP BY
        c.user_id,
        c.user_session,
        c.first_view_time,
        c.first_cart_time
),

funnel_summary AS (
    SELECT
        COUNT(*) AS view_sessions,

        SUM(
            CASE WHEN first_cart_time IS NOT NULL
            THEN 1 ELSE 0 END
        ) AS cart_sessions,

        SUM(
            CASE WHEN first_purchase_time IS NOT NULL
            THEN 1 ELSE 0 END
        ) AS purchase_sessions

    FROM purchase_after_cart
)

SELECT
    view_sessions,
    cart_sessions,
    purchase_sessions,

    ROUND(
        cart_sessions * 100.0 / NULLIF(view_sessions, 0),
        2
    ) AS view_to_cart_pct,

    ROUND(
        purchase_sessions * 100.0 / NULLIF(cart_sessions, 0),
        2
    ) AS cart_to_purchase_pct,

    ROUND(
        purchase_sessions * 100.0 / NULLIF(view_sessions, 0),
        2
    ) AS view_to_purchase_pct

FROM funnel_summary;



SELECT COUNT(*) AS total_records
FROM ecommerce;


SHOW INDEX FROM ecommerce;


SELECT
    event_time,
    event_type,
    user_id,
    user_session
FROM ecommerce
LIMIT 10;


SELECT VERSION() AS mysql_version;


SELECT
    COUNT(*) AS total_records,
    SUM(user_id IS NULL) AS null_user_id,
    SUM(user_session IS NULL) AS null_session,
    COUNT(DISTINCT user_session) AS unique_sessions
FROM ecommerce;


SELECT COUNT(*) AS current_records
FROM ecommerce_funnel_events;

INSERT INTO ecommerce_funnel_events (
    user_id,
    user_session,
    event_type,
    event_ts
)
SELECT
    user_id,
    user_session,
    event_type,
    STR_TO_DATE(
        event_time,
        '%Y-%m-%d %H:%i:%s UTC'
    )
FROM ecommerce
WHERE event_type IN (
    'view',
    'cart',
    'purchase'
);


CREATE INDEX idx_funnel_session_event
ON ecommerce_funnel_events (
    user_id,
    user_session,
    event_type,
    event_ts
);

SHOW INDEX FROM ecommerce_funnel_events;


USE ecommerce_analysis;

CREATE TEMPORARY TABLE tmp_first_view
ENGINE = InnoDB
AS
SELECT
    user_id,
    user_session,
    MIN(event_ts) AS first_view_time
FROM ecommerce_funnel_events
WHERE event_type = 'view'
GROUP BY
    user_id,
    user_session;
    
    SELECT
    COUNT(*) AS view_sessions,
    COUNT(DISTINCT user_id) AS view_users
FROM tmp_first_view;



CREATE TEMPORARY TABLE tmp_cart_after_view
ENGINE = InnoDB
AS
SELECT
    v.user_id,
    v.user_session,
    v.first_view_time,
    MIN(e.event_ts) AS first_cart_time

FROM tmp_first_view v

LEFT JOIN ecommerce_funnel_events e
    ON v.user_id = e.user_id
   AND v.user_session = e.user_session
   AND e.event_type = 'cart'
   AND e.event_ts > v.first_view_time

GROUP BY
    v.user_id,
    v.user_session,
    v.first_view_time;
    
SELECT
    COUNT(*) AS view_sessions,

    COUNT(first_cart_time) AS cart_sessions,

    ROUND(
        COUNT(first_cart_time) * 100.0
        / COUNT(*),
        2
    ) AS view_to_cart_pct

FROM tmp_cart_after_view;



CREATE TEMPORARY TABLE tmp_purchase_after_cart
ENGINE = InnoDB
AS
SELECT
    c.user_id,
    c.user_session,
    c.first_view_time,
    c.first_cart_time,

    MIN(e.event_ts) AS first_purchase_time

FROM tmp_cart_after_view c

LEFT JOIN ecommerce_funnel_events e
    ON c.user_id = e.user_id
   AND c.user_session = e.user_session
   AND e.event_type = 'purchase'
   AND e.event_ts > c.first_cart_time

WHERE c.first_cart_time IS NOT NULL

GROUP BY
    c.user_id,
    c.user_session,
    c.first_view_time,
    c.first_cart_time;
    
SELECT
    COUNT(*) AS cart_sessions,

    COUNT(first_purchase_time) AS purchase_sessions,

    ROUND(
        COUNT(first_purchase_time) * 100.0
        / COUNT(*),
        2
    ) AS cart_to_purchase_pct

FROM tmp_purchase_after_cart;


SELECT
    COUNT(*) AS view_sessions,

    SUM(first_cart_time IS NOT NULL)
        AS cart_sessions,

    SUM(first_purchase_time IS NOT NULL)
        AS purchase_sessions,

    ROUND(
        SUM(first_cart_time IS NOT NULL) * 100.0
        / COUNT(*), 2
    ) AS view_to_cart_pct,

    ROUND(
        SUM(first_purchase_time IS NOT NULL) * 100.0
        / NULLIF(SUM(first_cart_time IS NOT NULL), 0),
        2
    ) AS cart_to_purchase_pct,

    ROUND(
        SUM(first_purchase_time IS NOT NULL) * 100.0
        / COUNT(*), 2
    ) AS view_to_purchase_pct

FROM tmp_purchase_after_cart;



SELECT
    COUNT(*) AS view_sessions,

    SUM(c.first_cart_time IS NOT NULL)
        AS cart_sessions,

    SUM(p.first_purchase_time IS NOT NULL)
        AS purchase_sessions,

    ROUND(
        SUM(c.first_cart_time IS NOT NULL) * 100.0
        / COUNT(*), 2
    ) AS view_to_cart_pct,

    ROUND(
        SUM(p.first_purchase_time IS NOT NULL) * 100.0
        / NULLIF(SUM(c.first_cart_time IS NOT NULL), 0),
        2
    ) AS cart_to_purchase_pct,

    ROUND(
        SUM(p.first_purchase_time IS NOT NULL) * 100.0
        / COUNT(*), 2
    ) AS view_to_purchase_pct

FROM tmp_cart_after_view c

LEFT JOIN tmp_purchase_after_cart p
    ON c.user_id = p.user_id
   AND c.user_session = p.user_session;
   
   SELECT
    COUNT(*) AS view_users
FROM tmp_user_first_view;


SELECT *
FROM tmp_user_first_view
ORDER BY first_view_time
LIMIT 10;



CREATE TEMPORARY TABLE tmp_user_cart_after_view
ENGINE = InnoDB
AS
SELECT
    v.user_id,
    v.first_view_time,
    MIN(e.event_ts) AS first_cart_time

FROM tmp_user_first_view v

LEFT JOIN ecommerce_funnel_events e
    ON v.user_id = e.user_id
   AND e.event_type = 'cart'
   AND e.event_ts > v.first_view_time

GROUP BY
    v.user_id,
    v.first_view_time;
    
    
SELECT
    COUNT(*) AS view_users,

    COUNT(first_cart_time) AS cart_users,

    ROUND(
        COUNT(first_cart_time) * 100.0
        / COUNT(*),
        2
    ) AS view_to_cart_pct

FROM tmp_user_cart_after_view;



CREATE TEMPORARY TABLE tmp_user_purchase_after_cart
ENGINE = InnoDB
AS
SELECT
    c.user_id,
    c.first_view_time,
    c.first_cart_time,

    MIN(e.event_ts) AS first_purchase_time

FROM tmp_user_cart_after_view c

LEFT JOIN ecommerce_funnel_events e
    ON c.user_id = e.user_id
   AND e.event_type = 'purchase'
   AND e.event_ts > c.first_cart_time

WHERE c.first_cart_time IS NOT NULL

GROUP BY
    c.user_id,
    c.first_view_time,
    c.first_cart_time;
    
    
SELECT
    COUNT(*) AS cart_users,

    COUNT(first_purchase_time) AS purchase_users,

    ROUND(
        COUNT(first_purchase_time) * 100.0
        / COUNT(*),
        2
    ) AS cart_to_purchase_pct

FROM tmp_user_purchase_after_cart;



CREATE TEMPORARY TABLE tmp_user_view_cart_sessions
ENGINE = InnoDB
AS

WITH first_view_ranked AS (
    SELECT
        user_id,
        user_session,
        event_ts,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_ts, user_session
        ) AS rn
    FROM ecommerce_funnel_events
    WHERE event_type = 'view'
),

first_view AS (
    SELECT
        user_id,
        user_session AS view_session,
        event_ts AS first_view_time
    FROM first_view_ranked
    WHERE rn = 1
),

cart_ranked AS (
    SELECT
        v.user_id,
        e.user_session,
        e.event_ts,
        ROW_NUMBER() OVER (
            PARTITION BY v.user_id
            ORDER BY e.event_ts, e.user_session
        ) AS rn
    FROM first_view v
    JOIN ecommerce_funnel_events e
        ON v.user_id = e.user_id
       AND e.event_type = 'cart'
       AND e.event_ts > v.first_view_time
)

SELECT
    v.user_id,
    v.view_session,
    v.first_view_time,
    c.user_session AS cart_session,
    c.event_ts AS first_cart_time

FROM first_view v

LEFT JOIN cart_ranked c
    ON v.user_id = c.user_id
   AND c.rn = 1;
   
   
SELECT
    COUNT(*) AS view_users,

    COUNT(cart_session) AS cart_users,

    SUM(
        CASE
            WHEN cart_session IS NOT NULL
             AND view_session = cart_session
            THEN 1 ELSE 0
        END
    ) AS same_session_view_cart,

    SUM(
        CASE
            WHEN cart_session IS NOT NULL
             AND view_session <> cart_session
            THEN 1 ELSE 0
        END
    ) AS cross_session_view_cart,

    ROUND(
        SUM(
            CASE
                WHEN cart_session IS NOT NULL
                 AND view_session = cart_session
                THEN 1 ELSE 0
            END
        ) * 100.0
        / NULLIF(COUNT(cart_session), 0),
        2
    ) AS same_session_pct,

    ROUND(
        SUM(
            CASE
                WHEN cart_session IS NOT NULL
                 AND view_session <> cart_session
                THEN 1 ELSE 0
            END
        ) * 100.0
        / NULLIF(COUNT(cart_session), 0),
        2
    ) AS cross_session_pct

FROM tmp_user_view_cart_sessions;



DROP TEMPORARY TABLE IF EXISTS tmp_user_purchase_candidates;

CREATE TEMPORARY TABLE tmp_user_purchase_candidates
ENGINE = InnoDB
AS
SELECT
    c.user_id,
    e.user_session AS purchase_session,
    e.event_ts AS first_purchase_time,

    ROW_NUMBER() OVER (
        PARTITION BY c.user_id
        ORDER BY e.event_ts, e.user_session
    ) AS rn

FROM tmp_user_view_cart_sessions c

JOIN ecommerce_funnel_events e
    ON c.user_id = e.user_id
   AND e.event_type = 'purchase'
   AND e.event_ts > c.first_cart_time

WHERE c.first_cart_time IS NOT NULL;


DROP TEMPORARY TABLE IF EXISTS tmp_user_purchase_sessions;

CREATE TEMPORARY TABLE tmp_user_purchase_sessions
ENGINE = InnoDB
AS
SELECT
    c.user_id,
    c.view_session,
    c.cart_session,
    c.first_view_time,
    c.first_cart_time,

    p.purchase_session,
    p.first_purchase_time

FROM tmp_user_view_cart_sessions c

LEFT JOIN (
    SELECT
        user_id,
        purchase_session,
        first_purchase_time
    FROM tmp_user_purchase_candidates
    WHERE rn = 1
) p
    ON c.user_id = p.user_id;
    
    
SELECT
    COUNT(*) AS cart_users,

    COUNT(purchase_session) AS purchase_users,

    SUM(
        CASE
            WHEN cart_session = purchase_session
            THEN 1 ELSE 0
        END
    ) AS same_session_cart_purchase,

    SUM(
        CASE
            WHEN cart_session <> purchase_session
            THEN 1 ELSE 0
        END
    ) AS cross_session_cart_purchase,

    ROUND(
        SUM(
            CASE
                WHEN cart_session = purchase_session
                THEN 1 ELSE 0
            END
        ) * 100.0
        / NULLIF(COUNT(purchase_session), 0),
        2
    ) AS same_session_pct,

    ROUND(
        SUM(
            CASE
                WHEN cart_session <> purchase_session
                THEN 1 ELSE 0
            END
        ) * 100.0
        / NULLIF(COUNT(purchase_session), 0),
        2
    ) AS cross_session_pct

FROM tmp_user_purchase_sessions

WHERE cart_session IS NOT NULL;



SELECT
    COUNT(*) AS purchase_users,

    SUM(
        CASE
            WHEN view_session = cart_session
             AND cart_session = purchase_session
            THEN 1 ELSE 0
        END
    ) AS all_same_session,

    SUM(
        CASE
            WHEN view_session <> cart_session
             AND cart_session = purchase_session
            THEN 1 ELSE 0
        END
    ) AS cross_view_cart_only,

    SUM(
        CASE
            WHEN view_session = cart_session
             AND cart_session <> purchase_session
            THEN 1 ELSE 0
        END
    ) AS cross_cart_purchase_only,

    SUM(
        CASE
            WHEN view_session <> cart_session
             AND cart_session <> purchase_session
            THEN 1 ELSE 0
        END
    ) AS cross_both_stages

FROM tmp_user_purchase_sessions

WHERE purchase_session IS NOT NULL;



SELECT
    COUNT(*) AS purchase_events,
    ROUND(SUM(price), 2) AS purchase_revenue,
    ROUND(AVG(price), 4) AS avg_purchase_event_value,
    COUNT(DISTINCT user_id) AS purchase_users,
    COUNT(DISTINCT user_session) AS purchase_sessions
FROM ecommerce
WHERE event_type = 'purchase';


USE ecommerce_analysis;

DESCRIBE ecommerce;



USE ecommerce_analysis;

-- 1. 检查原始数据
SELECT COUNT(*) AS total_records
FROM ecommerce;

-- 2. 检查用户和 Session
SELECT
    COUNT(*) AS total_records,
    SUM(user_id IS NULL) AS null_user_id,
    SUM(user_session IS NULL) AS null_session,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(DISTINCT user_session) AS unique_sessions
FROM ecommerce;

-- 3. 检查 Funnel 临时数据表是否存在
SHOW TABLES LIKE 'ecommerce_funnel_events';

-- 4. 检查事件类型
SELECT
    event_type,
    COUNT(*) AS event_count
FROM ecommerce
GROUP BY event_type
ORDER BY event_count DESC;




USE ecommerce_analysis;

-- 1. 检查目标表总记录数
SELECT
    COUNT(*) AS total_records
FROM ecommerce_funnel_events;

-- 2. 检查事件分布
SELECT
    event_type,
    COUNT(*) AS event_count
FROM ecommerce_funnel_events
GROUP BY event_type
ORDER BY event_count DESC;

-- 3. 检查时间字段是否存在 NULL
SELECT
    COUNT(*) AS total_records,
    SUM(event_ts IS NULL) AS null_event_ts,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(DISTINCT user_session) AS unique_sessions
FROM ecommerce_funnel_events;

-- 4. 检查表结构
DESCRIBE ecommerce_funnel_events;





USE ecommerce_analysis;

WITH first_view AS (
    SELECT
        user_id,
        user_session,
        MIN(event_ts) AS first_view_time
    FROM ecommerce_funnel_events
    WHERE event_type = 'view'
    GROUP BY user_id, user_session
),

cart_after_view AS (
    SELECT
        v.user_id,
        v.user_session,
        v.first_view_time,
        MIN(e.event_ts) AS first_cart_time
    FROM first_view v
    LEFT JOIN ecommerce_funnel_events e
        ON v.user_id = e.user_id
       AND v.user_session = e.user_session
       AND e.event_type = 'cart'
       AND e.event_ts > v.first_view_time
    GROUP BY
        v.user_id,
        v.user_session,
        v.first_view_time
),

purchase_after_cart AS (
    SELECT
        c.user_id,
        c.user_session,
        c.first_view_time,
        c.first_cart_time,
        MIN(e.event_ts) AS first_purchase_time
    FROM cart_after_view c
    LEFT JOIN ecommerce_funnel_events e
        ON c.user_id = e.user_id
       AND c.user_session = e.user_session
       AND e.event_type = 'purchase'
       AND c.first_cart_time IS NOT NULL
       AND e.event_ts > c.first_cart_time
    GROUP BY
        c.user_id,
        c.user_session,
        c.first_view_time,
        c.first_cart_time
)

SELECT
    COUNT(*) AS view_sessions,

    SUM(first_cart_time IS NOT NULL)
        AS cart_sessions,

    SUM(first_purchase_time IS NOT NULL)
        AS purchase_sessions,

    ROUND(
        SUM(first_cart_time IS NOT NULL)
        * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS view_to_cart_pct,

    ROUND(
        SUM(first_purchase_time IS NOT NULL)
        * 100.0
        / NULLIF(SUM(first_cart_time IS NOT NULL), 0),
        2
    ) AS cart_to_purchase_pct,

    ROUND(
        SUM(first_purchase_time IS NOT NULL)
        * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS view_to_purchase_pct

FROM purchase_after_cart;





USE ecommerce_analysis;

WITH first_view AS (
    SELECT
        user_id,
        MIN(event_ts) AS first_view_time
    FROM ecommerce_funnel_events
    WHERE event_type = 'view'
    GROUP BY user_id
),

cart_after_view AS (
    SELECT
        v.user_id,
        v.first_view_time,
        MIN(e.event_ts) AS first_cart_time
    FROM first_view v
    LEFT JOIN ecommerce_funnel_events e
        ON v.user_id = e.user_id
       AND e.event_type = 'cart'
       AND e.event_ts > v.first_view_time
    GROUP BY
        v.user_id,
        v.first_view_time
),

purchase_after_cart AS (
    SELECT
        c.user_id,
        c.first_view_time,
        c.first_cart_time,
        MIN(e.event_ts) AS first_purchase_time
    FROM cart_after_view c
    LEFT JOIN ecommerce_funnel_events e
        ON c.user_id = e.user_id
       AND e.event_type = 'purchase'
       AND c.first_cart_time IS NOT NULL
       AND e.event_ts > c.first_cart_time
    GROUP BY
        c.user_id,
        c.first_view_time,
        c.first_cart_time
)

SELECT
    COUNT(*) AS view_users,

    SUM(first_cart_time IS NOT NULL)
        AS cart_users,

    SUM(first_purchase_time IS NOT NULL)
        AS purchase_users,

    ROUND(
        SUM(first_cart_time IS NOT NULL)
        * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS view_to_cart_pct,

    ROUND(
        SUM(first_purchase_time IS NOT NULL)
        * 100.0
        / NULLIF(SUM(first_cart_time IS NOT NULL), 0),
        2
    ) AS cart_to_purchase_pct,

    ROUND(
        SUM(first_purchase_time IS NOT NULL)
        * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS view_to_purchase_pct

FROM purchase_after_cart;




USE ecommerce_analysis;

WITH first_view_ranked AS (
    SELECT
        user_id,
        user_session,
        event_ts,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_ts, user_session
        ) AS rn
    FROM ecommerce_funnel_events
    WHERE event_type = 'view'
),

first_view AS (
    SELECT
        user_id,
        user_session AS view_session,
        event_ts AS first_view_time
    FROM first_view_ranked
    WHERE rn = 1
),

cart_ranked AS (
    SELECT
        v.user_id,
        e.user_session AS cart_session,
        e.event_ts AS first_cart_time,
        ROW_NUMBER() OVER (
            PARTITION BY v.user_id
            ORDER BY e.event_ts, e.user_session
        ) AS rn
    FROM first_view v
    JOIN ecommerce_funnel_events e
        ON v.user_id = e.user_id
       AND e.event_type = 'cart'
       AND e.event_ts > v.first_view_time
),

first_cart AS (
    SELECT
        user_id,
        cart_session,
        first_cart_time
    FROM cart_ranked
    WHERE rn = 1
),

purchase_ranked AS (
    SELECT
        c.user_id,
        e.user_session AS purchase_session,
        e.event_ts AS first_purchase_time,
        ROW_NUMBER() OVER (
            PARTITION BY c.user_id
            ORDER BY e.event_ts, e.user_session
        ) AS rn
    FROM first_cart c
    JOIN ecommerce_funnel_events e
        ON c.user_id = e.user_id
       AND e.event_type = 'purchase'
       AND e.event_ts > c.first_cart_time
),

first_purchase AS (
    SELECT
        user_id,
        purchase_session,
        first_purchase_time
    FROM purchase_ranked
    WHERE rn = 1
),

user_path AS (
    SELECT
        v.user_id,
        v.view_session,
        c.cart_session,
        p.purchase_session
    FROM first_view v
    LEFT JOIN first_cart c
        ON v.user_id = c.user_id
    LEFT JOIN first_purchase p
        ON v.user_id = p.user_id
)

SELECT
    COUNT(*) AS view_users,

    COUNT(cart_session) AS cart_users,

    COUNT(purchase_session) AS purchase_users,

    SUM(
        CASE WHEN cart_session IS NOT NULL
              AND view_session = cart_session
             THEN 1 ELSE 0 END
    ) AS same_session_view_cart,

    SUM(
        CASE WHEN cart_session IS NOT NULL
              AND view_session <> cart_session
             THEN 1 ELSE 0 END
    ) AS cross_session_view_cart,

    SUM(
        CASE WHEN purchase_session IS NOT NULL
              AND cart_session = purchase_session
             THEN 1 ELSE 0 END
    ) AS same_session_cart_purchase,

    SUM(
        CASE WHEN purchase_session IS NOT NULL
              AND cart_session <> purchase_session
             THEN 1 ELSE 0 END
    ) AS cross_session_cart_purchase,

    SUM(
        CASE WHEN purchase_session IS NOT NULL
              AND view_session = cart_session
              AND cart_session = purchase_session
             THEN 1 ELSE 0 END
    ) AS all_same_session,

    SUM(
        CASE WHEN purchase_session IS NOT NULL
              AND view_session <> cart_session
              AND cart_session = purchase_session
             THEN 1 ELSE 0 END
    ) AS cross_view_cart_only,

    SUM(
        CASE WHEN purchase_session IS NOT NULL
              AND view_session = cart_session
              AND cart_session <> purchase_session
             THEN 1 ELSE 0 END
    ) AS cross_cart_purchase_only,

    SUM(
        CASE WHEN purchase_session IS NOT NULL
              AND view_session <> cart_session
              AND cart_session <> purchase_session
             THEN 1 ELSE 0 END
    ) AS cross_both_stages

FROM user_path;



USE ecommerce_analysis;

SELECT
    COUNT(*) AS purchase_events,

    ROUND(SUM(price), 2) AS purchase_revenue,

    ROUND(AVG(price), 4) AS avg_purchase_event_value,

    COUNT(DISTINCT user_id) AS purchase_users,

    COUNT(DISTINCT user_session) AS purchase_sessions

FROM ecommerce

WHERE event_type = 'purchase';
