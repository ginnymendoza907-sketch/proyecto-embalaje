-- Usuarios y Permisos

CREATE USER app_user WITH PASSWORD 'cambie_app';
CREATE USER elt_user WITH PASSWORD 'cambie_elt';
CREATE USER bi_user WITH PASSWORD 'cambie_bi';

GRANT USAGE ON SCHEMA operacional TO app_user, elt_user;
GRANT USAGE ON SCHEMA analitico TO elt_user, bi_user;

-- app_user: CRUD sobre operacional
GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA operacional TO app_user;

GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA operacional TO app_user;

GRANT EXECUTE
ON ALL FUNCTIONS IN SCHEMA operacional TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA operacional
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA operacional
GRANT USAGE, SELECT ON SEQUENCES TO app_user;

-- elt_user: lee operacional, escribe analitico
GRANT SELECT
ON ALL TABLES IN SCHEMA operacional TO elt_user;

GRANT EXECUTE
ON ALL FUNCTIONS IN SCHEMA operacional TO elt_user;

GRANT ALL
ON ALL TABLES IN SCHEMA analitico TO elt_user;

GRANT ALL
ON ALL SEQUENCES IN SCHEMA analitico TO elt_user;

GRANT EXECUTE
ON ALL ROUTINES IN SCHEMA analitico TO elt_user;

-- bi_user: solo lectura de analitico
GRANT SELECT
ON ALL TABLES IN SCHEMA analitico TO bi_user;