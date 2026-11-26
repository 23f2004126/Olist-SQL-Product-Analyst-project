-- =============================================================================
-- 00_schema.sql: Olist tables, one per CSV
--
-- Run:  psql -d olist -f sql/00_schema.sql
--
-- Choices that apply to every table:
--   * Column names match the CSV headers exactly, including Olist's own
--     spelling "lenght" in products, so each column traces back to the source file.
--   * IDs are 32-character hex strings, stored as varchar(32).
--   * Zip code prefixes are stored as char(5), not integer. As text, the
--     leading zeros are kept ("01037" would otherwise become 1037).
--   * Date/time columns use timestamp (without time zone). The source has
--     no time zone information.
--   * Money columns use numeric(10,2). numeric is exact, while float can add
--     rounding errors when summing currency. Every source value has 2 decimals.
--   * Primary keys are declared only where profiling showed the column(s) are
--     unique. Foreign keys are declared only where every child value exists
--     in the parent.
-- =============================================================================

-- Rebuilding the schema starts clean. Drop children before parents so
-- foreign keys don't block the drop.
DROP TABLE IF EXISTS order_reviews;
DROP TABLE IF EXISTS order_payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS product_category_name_translation;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS geolocation;


-- -----------------------------------------------------------------------------
-- customers  (olist_customers_dataset.csv)
-- One row per customer_id. Olist creates a new customer_id for every order,
-- so the same person can appear under several customer_ids.
-- customer_unique_id identifies the person.
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id               varchar(32) PRIMARY KEY,  -- unique: 99,441 rows, 99,441 distinct
    customer_unique_id        varchar(32) NOT NULL,     -- NOT unique (96,096 distinct). One person can have many customer_ids
    customer_zip_code_prefix  char(5),
    customer_city             text,
    customer_state            char(2)
);
-- No FK from customer_zip_code_prefix to geolocation:
--   (1) geolocation has many rows per zip prefix, so the prefix isn't a key there.
--   (2) 157 customer zip prefixes (278 customers) don't appear in geolocation at all.


-- -----------------------------------------------------------------------------
-- geolocation  (olist_geolocation_dataset.csv)
-- Several lat/lng points per zip prefix.
-- -----------------------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_zip_code_prefix  char(5),
    geolocation_lat              double precision,  -- coordinates, not money, so float is fine
    geolocation_lng              double precision,
    geolocation_city             text,
    geolocation_state            char(2)
);
-- No PRIMARY KEY: 1,000,163 rows but only 19,015 distinct zip prefixes
-- (17,972 prefixes repeat). No column or small column set identifies a row;
-- 261,831 rows are exact copies of an earlier row. To join on location later,
-- first build one row per prefix (e.g. average lat/lng).


-- -----------------------------------------------------------------------------
-- sellers  (olist_sellers_dataset.csv)
-- -----------------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id               varchar(32) PRIMARY KEY,  -- unique: 3,095 rows, 3,095 distinct
    seller_zip_code_prefix  char(5),
    seller_city             text,
    seller_state            char(2)
);
-- No FK to geolocation, for the same reasons as customers
-- (7 seller zip prefixes are missing from geolocation).


-- -----------------------------------------------------------------------------
-- product_category_name_translation  (product_category_name_translation.csv)
-- Portuguese category name -> English. The CSV starts with a UTF-8 BOM.
-- HEADER skips that line, so the BOM doesn't affect the load.
-- -----------------------------------------------------------------------------
CREATE TABLE product_category_name_translation (
    product_category_name          text PRIMARY KEY,  -- unique: 71 rows, 71 distinct
    product_category_name_english  text
);


-- -----------------------------------------------------------------------------
-- products  (olist_products_dataset.csv)
-- Dimensions are whole numbers in the source, so they use integer.
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    product_id                  varchar(32) PRIMARY KEY,  -- unique: 32,951 rows, 32,951 distinct
    product_category_name       text,     -- 610 blanks -> NULL
    product_name_lenght         integer,  -- sic: source spelling kept
    product_description_lenght  integer,  -- sic
    product_photos_qty          integer,
    product_weight_g            integer,
    product_length_cm           integer,
    product_height_cm           integer,
    product_width_cm            integer
);
-- No FK from product_category_name to the translation table: 2 categories
-- ('pc_gamer', 'portateis_cozinha_e_preparadores_de_alimentos', 13 products)
-- have no translation row. An FK would reject them. Use a LEFT JOIN when
-- translating instead.


-- -----------------------------------------------------------------------------
-- orders  (olist_orders_dataset.csv)
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id                       varchar(32) PRIMARY KEY,  -- unique: 99,441 rows, 99,441 distinct
    customer_id                    varchar(32) NOT NULL REFERENCES customers (customer_id),  -- all customer_ids exist in customers (0 orphans)
    order_status                   text NOT NULL,   -- delivered, shipped, canceled, ...
    order_purchase_timestamp       timestamp NOT NULL,
    order_approved_at              timestamp,       -- NULL when not (yet) approved
    order_delivered_carrier_date   timestamp,       -- NULL when not handed to carrier
    order_delivered_customer_date  timestamp,       -- NULL when not delivered
    order_estimated_delivery_date  timestamp        -- source always has 00:00:00 time
);


-- -----------------------------------------------------------------------------
-- order_items  (olist_order_items_dataset.csv)
-- One row per item in an order. order_item_id counts items within an order
-- (1, 2, 3, ...), so it's only unique together with order_id.
-- -----------------------------------------------------------------------------
CREATE TABLE order_items (
    order_id             varchar(32) NOT NULL REFERENCES orders (order_id),     -- 0 orphans
    order_item_id        integer     NOT NULL,
    product_id           varchar(32) NOT NULL REFERENCES products (product_id), -- 0 orphans
    seller_id            varchar(32) NOT NULL REFERENCES sellers (seller_id),   -- 0 orphans
    shipping_limit_date  timestamp,
    price                numeric(10,2),
    freight_value        numeric(10,2),
    PRIMARY KEY (order_id, order_item_id)  -- pair unique: 112,650 rows, 112,650 distinct pairs
);


-- -----------------------------------------------------------------------------
-- order_payments  (olist_order_payments_dataset.csv)
-- An order can be paid in several parts (e.g. card + voucher).
-- payment_sequential numbers those parts within an order.
-- -----------------------------------------------------------------------------
CREATE TABLE order_payments (
    order_id              varchar(32) NOT NULL REFERENCES orders (order_id),  -- 0 orphans
    payment_sequential    integer     NOT NULL,
    payment_type          text,           -- credit_card, boleto, voucher, debit_card, not_defined
    payment_installments  integer,
    payment_value         numeric(10,2),
    PRIMARY KEY (order_id, payment_sequential)  -- pair unique: 103,886 rows, 103,886 distinct pairs
);


-- -----------------------------------------------------------------------------
-- order_reviews  (olist_order_reviews_dataset.csv)
-- -----------------------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id                varchar(32) NOT NULL,
    order_id                 varchar(32) NOT NULL REFERENCES orders (order_id),  -- 0 orphans
    review_score             smallint,      -- 1–5
    review_comment_title     text,          -- mostly blank -> NULL
    review_comment_message   text,          -- may contain line breaks
    review_creation_date     timestamp,     -- almost always 00:00:00 (85 rows have a time)
    review_answer_timestamp  timestamp,
    PRIMARY KEY (review_id, order_id)
);
-- review_id on its own is NOT unique: 99,224 rows but 98,410 distinct review_ids
-- (789 review_ids appear more than once, attached to different orders).
-- order_id on its own is NOT unique either: 547 orders have more than one review.
-- The pair (review_id, order_id) is unique (99,224 distinct pairs), so it is
-- the primary key. Analysis has to choose which review counts per order
-- (see docs/data_quality_notes.md).
