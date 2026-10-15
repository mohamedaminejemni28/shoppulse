\set ON_ERROR_STOP on 

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS shop; -- Crée le schéma "shop" pour les données principales de la boutique

CREATE SCHEMA IF NOT EXISTS analytics; -- Crée le schéma "analytics" pour les vues, KPI et données analytiques

CREATE SCHEMA IF NOT EXISTS meta;-- Crée le schéma "meta" pour les informations techniques des pipelines

COMMENT ON SCHEMA shop IS 'Données opérationnelles et comportementales de la boutique ShopPulse.'; -- Ajoute une description au schéma "shop"
COMMENT ON SCHEMA analytics IS 'Vues analytiques prêtes pour les dashboards et les contrôles.';-- Ajoute une description au schéma "analytics"
COMMENT ON SCHEMA meta IS 'Métadonnées d''exécution et watermarks des pipelines.';-- Ajoute une description au schéma "meta"
-- d''exécution utilise deux apostrophes pour représenter une apostrophe dans une chaîne SQL

COMMIT;

