-- =============================================================================
-- 01_load.sql: load the 9 Olist CSVs into the tables from 00_schema.sql
--
-- Run FROM THE REPO ROOT (the \copy paths are relative to where psql is started):
--     psql -d olist -f sql/01_load.sql
--
-- Re-runnable: everything is truncated before loading, so a second run gives
-- the same result instead of doubling the rows.
--
-- Why \copy and not COPY:
--   COPY reads files on the database server. \copy is a psql command that
--   reads the file on the client (this machine) and streams it to the
--   server, so it needs no server file permissions.
--
-- CSV options used:
--   FORMAT csv  handles quoted fields, including review comments that
--               contain commas and line breaks.
--   HEADER      skips the first line (column names).
--   In CSV format an empty unquoted field loads as NULL. That is how the
--   blanks in the source become NULLs.
-- =============================================================================

-- Stop at the first error instead of carrying on with half-loaded data.
\set ON_ERROR_STOP on

-- One transaction: either every table loads, or nothing changes.
BEGIN;

-- Empty all tables in one statement. Listing them together lets Postgres
-- truncate tables that have foreign keys between them.
TRUNCATE TABLE
    order_reviews,
    order_payments,
    order_items,
    orders,
    products,
    product_category_name_translation,
    sellers,
    customers,
    geolocation;

-- Load parents before children so every foreign key finds its parent row.

\copy customers                         FROM 'data/olist_customers_dataset.csv'            WITH (FORMAT csv, HEADER true)
\copy geolocation                       FROM 'data/olist_geolocation_dataset.csv'          WITH (FORMAT csv, HEADER true)
\copy sellers                           FROM 'data/olist_sellers_dataset.csv'              WITH (FORMAT csv, HEADER true)
\copy product_category_name_translation FROM 'data/product_category_name_translation.csv'  WITH (FORMAT csv, HEADER true)
\copy products                          FROM 'data/olist_products_dataset.csv'             WITH (FORMAT csv, HEADER true)
\copy orders                            FROM 'data/olist_orders_dataset.csv'               WITH (FORMAT csv, HEADER true)
\copy order_items                       FROM 'data/olist_order_items_dataset.csv'          WITH (FORMAT csv, HEADER true)
\copy order_payments                    FROM 'data/olist_order_payments_dataset.csv'       WITH (FORMAT csv, HEADER true)
\copy order_reviews                     FROM 'data/olist_order_reviews_dataset.csv'        WITH (FORMAT csv, HEADER true)

COMMIT;

-- Refresh planner statistics after a bulk load.
ANALYZE;
