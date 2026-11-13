-- STEP 1: Remove duplicate booking IDs

CREATE OR REFRESH MATERIALIZED VIEW silver_bookings_deduplicated
AS
SELECT *
FROM bronze_hotel_bookings
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY booking_id
    ORDER BY booking_date DESC, loaded_at DESC
) = 1;


-- STEP 2: Store invalid records separately

CREATE OR REFRESH MATERIALIZED VIEW silver_bookings_rejected
AS
SELECT
    *,
    CASE
        WHEN TRY_CAST(check_in_date AS DATE) IS NULL
            THEN 'Missing or Invalid Check-in Date'

        WHEN TRY_CAST(check_out_date AS DATE) IS NULL
            THEN 'Missing or Invalid Check-out Date'

        WHEN TRY_CAST(check_out_date AS DATE)
             <= TRY_CAST(check_in_date AS DATE)
            THEN 'Invalid Stay Dates'

        WHEN TRY_CAST(room_rate AS DECIMAL(10,2)) IS NULL
            THEN 'Missing or Invalid Room Rate'

        WHEN TRY_CAST(room_rate AS DECIMAL(10,2)) < 0
            THEN 'Negative Room Rate'
    END AS reject_reason

FROM silver_bookings_deduplicated
WHERE
    TRY_CAST(check_in_date AS DATE) IS NULL
    OR TRY_CAST(check_out_date AS DATE) IS NULL
    OR TRY_CAST(check_out_date AS DATE)
       <= TRY_CAST(check_in_date AS DATE)
    OR TRY_CAST(room_rate AS DECIMAL(10,2)) IS NULL
    OR TRY_CAST(room_rate AS DECIMAL(10,2)) < 0;


-- STEP 3: Clean valid records

CREATE OR REFRESH MATERIALIZED VIEW silver_bookings_clean
AS
SELECT
    booking_id,
    guest_id,

    TRY_CAST(booking_date AS DATE) AS booking_date,
    TRY_CAST(check_in_date AS DATE) AS check_in_date,
    TRY_CAST(check_out_date AS DATE) AS check_out_date,

    COALESCE(
        TRY_CAST(nights AS INT),
        DATEDIFF(
            TRY_CAST(check_out_date AS DATE),
            TRY_CAST(check_in_date AS DATE)
        )
    ) AS nights,

    INITCAP(TRIM(hotel_name)) AS hotel_name,

    COALESCE(
        INITCAP(NULLIF(TRIM(city), '')),
        'Unknown'
    ) AS city,

    INITCAP(TRIM(region)) AS region,
    INITCAP(TRIM(room_type)) AS room_type,

    COALESCE(
        INITCAP(NULLIF(TRIM(booking_channel), '')),
        'Unknown'
    ) AS booking_channel,

    TRY_CAST(guests AS INT) AS guests,

    TRY_CAST(room_rate AS DECIMAL(10,2)) AS room_rate,

    COALESCE(
        TRY_CAST(total_amount AS DECIMAL(12,2)),
        DATEDIFF(
            TRY_CAST(check_out_date AS DATE),
            TRY_CAST(check_in_date AS DATE)
        ) * TRY_CAST(room_rate AS DECIMAL(10,2))
    ) AS total_amount,

    COALESCE(
        TRY_CAST(discount_amount AS DECIMAL(12,2)),
        0
    ) AS discount_amount,

    INITCAP(TRIM(meal_plan)) AS meal_plan,
    payment_method,
    INITCAP(TRIM(payment_status)) AS payment_status,
    INITCAP(TRIM(booking_status)) AS booking_status,

    TRY_CAST(guest_rating AS DECIMAL(3,2)) AS guest_rating

FROM silver_bookings_deduplicated

WHERE
    TRY_CAST(check_in_date AS DATE) IS NOT NULL
    AND TRY_CAST(check_out_date AS DATE) IS NOT NULL
    AND TRY_CAST(check_out_date AS DATE)
        > TRY_CAST(check_in_date AS DATE)
    AND TRY_CAST(room_rate AS DECIMAL(10,2)) >= 0;
