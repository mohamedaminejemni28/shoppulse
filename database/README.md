# Base PostgreSQL ShopPulse

## Ordre d'initialisation

| Fichier | Fonction |
|---|---|
| `00_extensions_and_schemas.sql` | extensions et schémas PostgreSQL |
| `01_schema.sql` | tables, contraintes, commentaires et index |
| `02_functions_and_triggers.sql` | calculs automatiques et règles inter-tables |
| `03_seed_data.sql` | données de démonstration déterministes |
| `04_analytics_views.sql` | vues analytiques et contrôles financiers |

## Data Warehouse

Le Data Warehouse se trouve dans le schéma PostgreSQL `warehouse` et suit un modèle en étoile :

| Objet | Grain / rôle |
|---|---|
| `dim_date` | une ligne par date |
| `dim_customer` | une ligne par client |
| `dim_product` | une ligne par produit |
| `fact_sales` | une ligne par article de commande |
| `fact_events` | une ligne par événement utilisateur |
| `etl_runs` | historique des chargements du warehouse |
| `v_sales_dashboard` | ventes agrégées par date, catégorie et canal |

La migration versionnée est `migrations/001_create_warehouse.sql`. Elle crée également la fonction idempotente `warehouse.refresh()`, utilisée par Kestra pour mettre à jour les dimensions et les faits sans dupliquer les lignes.

Le flow `shoppulse.warehouse.refresh_warehouse` démarre tous les jours à 02:30, après l'export du Data Lake planifié à 02:00.

Ces fichiers sont montés dans `/docker-entrypoint-initdb.d` par Docker Compose. PostgreSQL les exécute uniquement lorsque le volume est vide.

## Modifier le schéma plus tard

Ne modifiez pas silencieusement les fichiers d'initialisation après le début du projet. Pour les phases suivantes, créez des migrations versionnées, par exemple :

```text
database/migrations/
  001_add_order_delivery.sql
  002_add_event_partitioning.sql
```

Pendant cette première phase locale, utilisez le script de réinitialisation uniquement lorsque la perte des données de démonstration est acceptable.
