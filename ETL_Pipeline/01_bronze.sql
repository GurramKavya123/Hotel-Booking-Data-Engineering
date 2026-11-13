CREATE OR REFRESH STREAMING TABLE bronze_hotel_bookings
AS
SELECT
    *,
    _metadata.file_name AS source_file,
    current_timestamp() AS loaded_at
FROM STREAM read_files(
    '/Volumes/hospitality_catalog/bookings/raw_files/',
    format => 'csv',
    header => true,
    inferColumnTypes => true
);
