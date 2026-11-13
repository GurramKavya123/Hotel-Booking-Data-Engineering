-- TABLE 1: Monthly Booking Summary

CREATE OR REFRESH MATERIALIZED VIEW gold_monthly_bookings
AS
SELECT
    DATE_TRUNC('MONTH', check_in_date) AS stay_month,

    COUNT(*) AS bookings,

    SUM(
        CASE
            WHEN booking_status = 'Cancelled' THEN 1
            ELSE 0
        END
    ) AS cancelled_bookings,

    SUM(
        CASE
            WHEN booking_status = 'Completed' THEN nights
            ELSE 0
        END
    ) AS room_nights,

    SUM(
        CASE
            WHEN booking_status = 'Completed'
            THEN total_amount - discount_amount
            ELSE 0
        END
    ) AS net_revenue

FROM silver_bookings_clean

GROUP BY DATE_TRUNC('MONTH', check_in_date);


-- TABLE 2: Hotel Performance Summary

CREATE OR REFRESH MATERIALIZED VIEW gold_hotel_summary
AS
SELECT
    region,
    city,
    hotel_name,

    COUNT(*) AS bookings,

    SUM(
        CASE
            WHEN booking_status = 'Completed' THEN nights
            ELSE 0
        END
    ) AS room_nights,

    SUM(
        CASE
            WHEN booking_status = 'Completed'
            THEN total_amount - discount_amount
            ELSE 0
        END
    ) AS net_revenue,

    CASE
        WHEN SUM(
            CASE WHEN booking_status = 'Completed' THEN nights ELSE 0 END
        ) = 0 THEN 0

        ELSE
            SUM(
                CASE
                    WHEN booking_status = 'Completed'
                    THEN total_amount - discount_amount
                    ELSE 0
                END
            )
            /
            SUM(
                CASE
                    WHEN booking_status = 'Completed' THEN nights
                    ELSE 0
                END
            )
    END AS avg_daily_rate

FROM silver_bookings_clean

GROUP BY
    region,
    city,
    hotel_name;


-- TABLE 3: Room Type Summary

CREATE OR REFRESH MATERIALIZED VIEW gold_room_type_summary
AS
SELECT
    room_type,

    COUNT(*) AS bookings,

    SUM(
        CASE
            WHEN booking_status = 'Completed' THEN nights
            ELSE 0
        END
    ) AS room_nights,

    SUM(
        CASE
            WHEN booking_status = 'Completed'
            THEN total_amount - discount_amount
            ELSE 0
        END
    ) AS net_revenue,

    AVG(
        CASE
            WHEN booking_status = 'Completed' THEN guest_rating
            ELSE NULL
        END
    ) AS avg_rating

FROM silver_bookings_clean

GROUP BY room_type;


-- TABLE 4: Booking Channel Summary

CREATE OR REFRESH MATERIALIZED VIEW gold_channel_summary
AS
SELECT
    booking_channel,

    COUNT(*) AS bookings,

    SUM(
        CASE
            WHEN booking_status = 'Cancelled' THEN 1
            ELSE 0
        END
    ) AS cancelled_bookings,

    CASE
        WHEN COUNT(*) = 0 THEN 0
        ELSE
            SUM(
                CASE
                    WHEN booking_status = 'Cancelled' THEN 1
                    ELSE 0
                END
            ) * 100.0 / COUNT(*)
    END AS cancellation_rate_pct,

    SUM(
        CASE
            WHEN booking_status = 'Completed'
            THEN total_amount - discount_amount
            ELSE 0
        END
    ) AS net_revenue

FROM silver_bookings_clean

GROUP BY booking_channel;


-- TABLE 5: Data Quality and Reconciliation

CREATE OR REFRESH MATERIALIZED VIEW gold_data_quality
AS

WITH bronze_stats AS (
    SELECT
        COUNT(*) AS bronze_rows,

        SUM(
            CASE
                WHEN check_in_date IS NULL
                     OR TRIM(CAST(check_in_date AS STRING)) = ''
                THEN 1 ELSE 0
            END
        ) AS missing_checkin_rows,

        SUM(
            CASE
                WHEN check_out_date IS NULL
                     OR TRIM(CAST(check_out_date AS STRING)) = ''
                THEN 1 ELSE 0
            END
        ) AS missing_checkout_rows,

        SUM(
            CASE
                WHEN TRY_CAST(check_out_date AS DATE) IS NOT NULL
                 AND TRY_CAST(check_in_date AS DATE) IS NOT NULL
                 AND TRY_CAST(check_out_date AS DATE)
                     <= TRY_CAST(check_in_date AS DATE)
                THEN 1 ELSE 0
            END
        ) AS invalid_date_rows,

        SUM(
            CASE
                WHEN TRY_CAST(room_rate AS DECIMAL(10,2)) < 0
                THEN 1 ELSE 0
            END
        ) AS negative_rate_rows,

        SUM(
            CASE
                WHEN city IS NULL OR TRIM(city) = ''
                THEN 1 ELSE 0
            END
        ) AS missing_city_rows,

        SUM(
            CASE
                WHEN booking_channel IS NULL OR TRIM(booking_channel) = ''
                THEN 1 ELSE 0
            END
        ) AS missing_channel_rows,

        SUM(
            CASE
                WHEN nights IS NULL OR TRIM(CAST(nights AS STRING)) = ''
                THEN 1 ELSE 0
            END
        ) AS missing_nights_rows,

        SUM(
            CASE
                WHEN total_amount IS NULL
                     OR TRIM(CAST(total_amount AS STRING)) = ''
                THEN 1 ELSE 0
            END
        ) AS missing_amount_rows

    FROM bronze_hotel_bookings
),

dedup_stats AS (
    SELECT COUNT(*) AS deduplicated_rows
    FROM silver_bookings_deduplicated
),

clean_stats AS (
    SELECT COUNT(*) AS clean_rows
    FROM silver_bookings_clean
),

rejected_stats AS (
    SELECT COUNT(*) AS rejected_rows
    FROM silver_bookings_rejected
)

SELECT
    b.bronze_rows,

    b.bronze_rows - d.deduplicated_rows AS duplicate_rows,

    c.clean_rows,

    r.rejected_rows,

    b.missing_checkin_rows,
    b.missing_checkout_rows,
    b.invalid_date_rows,
    b.negative_rate_rows,
    b.missing_city_rows,
    b.missing_channel_rows,
    b.missing_nights_rows,
    b.missing_amount_rows,

    CASE
        WHEN b.bronze_rows =
             c.clean_rows + r.rejected_rows
             + (b.bronze_rows - d.deduplicated_rows)
        THEN 'Passed'
        ELSE 'Failed'
    END AS reconciliation_status

FROM bronze_stats b
CROSS JOIN dedup_stats d
CROSS JOIN clean_stats c
CROSS JOIN rejected_stats r;
