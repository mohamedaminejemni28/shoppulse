# dbt ShopPulse

Ce projet transforme les tables opérationnelles du schéma `shop` en modèles analytiques dans PostgreSQL.

## Couches

- `staging` : vues de nettoyage et de normalisation.
- `marts` : tables métier `sales`, `customers`, `products` et `events`.

## Exécution

Depuis la racine du projet :

```powershell
docker compose --profile analytics run --rm dbt debug
docker compose --profile analytics run --rm dbt build
```

Ou avec le script PowerShell :

```powershell
.\scripts\dbt.ps1 debug
.\scripts\dbt.ps1 build
.\scripts\dbt.ps1 test
.\scripts\dbt.ps1 docs
```

Les modèles finaux sont créés dans le schéma PostgreSQL `analytics_dbt_analytics`. Les vues de staging sont créées dans `analytics_dbt_staging`.
