# ShopPulse - Base de données e-commerce

ShopPulse est une base PostgreSQL complète conçue pour le projet de Data Engineering décrit dans le guide PDF du dossier `output/pdf`.

Cette première version couvre :

- les clients et leurs adresses ;
- les catégories, produits et stocks ;
- les commandes et leurs lignes ;
- les tentatives de paiement et remboursements ;
- les sessions web et événements comportementaux ;
- les métadonnées des pipelines ;
- les vues analytiques pour les futurs dashboards ;
- un jeu de données fictif, déterministe et sans donnée personnelle réelle ;
- des contrôles automatiques de qualité.

## Architecture actuelle

```text
Données e-commerce -> PostgreSQL -> Kestra -> MinIO
                              |          |
                              v          v
                      dbt / Warehouse   Spark
                              |          |
                              +----> API FastAPI -> Dashboard

Événements temps réel -> Kafka -> MinIO -> Spark -> Parquet
```

Le projet inclut maintenant PostgreSQL, Kestra, MinIO, dbt, Spark et Kafka. BigQuery reste facultatif car le Data Warehouse local utilise PostgreSQL.

Le guide complet, les tests, la sécurité, les captures et le scénario de démonstration sont disponibles dans [`docs/GUIDE_FINAL.md`](docs/GUIDE_FINAL.md).

## Streaming Kafka et traitement Spark

La chaîne temps réel fonctionne ainsi :

```text
Générateur ShopPulse
        |
        v
Kafka : shoppulse.events
        |
        v
Consommateur kafka-to-minio
        |
        v
MinIO : raw/streaming/events/date=.../hour=.../*.jsonl
        |
        v
Spark Batch
        |
        v
MinIO : analytics/streaming_event_summary/date=.../run=.../*.parquet
```

Démarrer Kafka et l'archivage automatique vers MinIO :

```powershell
.\scripts\streaming.ps1 start
```

Simuler 100 événements (le deuxième paramètre permet de changer le nombre) :

```powershell
.\scripts\streaming.ps1 produce 100
```

Contrôler les services et les archives :

```powershell
.\scripts\streaming.ps1 status
.\scripts\streaming.ps1 logs
```

Exécuter l'agrégation batch Spark :

```powershell
.\scripts\spark.ps1 run
```

Les événements simulés couvrent `page_view`, `add_to_cart`, `order_created` et `payment_succeeded`. Spark calcule le nombre d'événements, les clients uniques et le montant total par date, type, canal et appareil.

## Prérequis

1. Installer Docker Desktop.
2. Démarrer Docker Desktop.
3. Ouvrir PowerShell dans ce dossier.

Docker n'était pas disponible sur la machine au moment de la création des fichiers. Les scripts sont donc prêts à être exécutés dès son installation.

## Démarrage rapide

Créer le fichier local de configuration :

```powershell
Copy-Item .env.example .env
```

Modifier ensuite les mots de passe dans `.env`, puis démarrer PostgreSQL :

```powershell
.\scripts\db.ps1 start
```

Lors du premier démarrage, PostgreSQL exécute automatiquement les scripts de `database/init` dans cet ordre :

1. extensions et schémas ;
2. tables, contraintes et index ;
3. fonctions et triggers ;
4. données fictives ;
5. vues analytiques.

Vérifier l'état du service :

```powershell
.\scripts\db.ps1 status
```

Exécuter tous les tests de données :

```powershell
.\scripts\db.ps1 test
```

Ouvrir une console PostgreSQL :

```powershell
.\scripts\db.ps1 shell
```

## Connexion PostgreSQL

Avec les valeurs par défaut de `.env.example` :

| Paramètre | Valeur |
|---|---|
| Hôte | `localhost` |
| Port | `5432` |
| Base | `shoppulse` |
| Utilisateur | `shoppulse` |
| Mot de passe | valeur de `POSTGRES_PASSWORD` dans `.env` |

Chaîne de connexion :

```text
postgresql://shoppulse:VOTRE_MOT_DE_PASSE@localhost:5432/shoppulse
```

## Interface pgAdmin facultative

Démarrer PostgreSQL et pgAdmin :

```powershell
.\scripts\db.ps1 start-tools
```

Puis ouvrir `http://localhost:5050`. Les identifiants de pgAdmin proviennent du fichier `.env`.

## Contenu de démonstration

La base est initialisée avec au minimum :

| Donnée | Volume |
|---|---:|
| Clients | 100 |
| Produits | 30 |
| Commandes | 500 |
| Sessions web | 800 |
| Événements | plus de 2 800 |

Les données utilisent des identifiants et des dates stables afin de rendre les démonstrations reproductibles.

## Schémas PostgreSQL

### `shop`

Contient les données opérationnelles :

- `customers`
- `customer_addresses`
- `categories`
- `products`
- `inventory`
- `orders`
- `order_items`
- `payments`
- `refunds`
- `web_sessions`
- `events`
- `order_status_history`

### `analytics`

Contient les vues prêtes pour l'analyse :

- `v_daily_sales`
- `v_product_performance`
- `v_customer_summary`
- `v_payment_health`
- `v_conversion_funnel`
- `v_order_reconciliation`
- `v_inventory_health`
- `v_data_freshness`

### `meta`

Prépare l'arrivée de Kestra et des pipelines :

- `pipeline_runs`
- `ingestion_watermarks`

## Règles automatiques importantes

- Les totaux de commande sont recalculés après chaque modification de ligne.
- La taxe de démonstration est fixée à 7,5 % du montant taxable.
- Tous les changements de statut d'une commande sont historisés.
- Un paiement ne peut pas dépasser le total de sa commande.
- Un remboursement ne peut pas dépasser le paiement réussi correspondant.
- Les valeurs de statut, devise, canal, appareil et type d'événement sont contrôlées.
- Les clés étrangères empêchent les événements, paiements ou lignes de devenir orphelins.
- Les index couvrent les filtres analytiques et opérationnels principaux.

## Requêtes métier

Le fichier `database/queries/business_questions.sql` contient dix analyses prêtes à utiliser :

- chiffre d'affaires quotidien ;
- produits les plus rentables ;
- produits consultés mais peu achetés ;
- funnel de conversion ;
- conversion par canal ;
- santé des paiements ;
- meilleurs clients ;
- besoins de réapprovisionnement ;
- réconciliation financière ;
- fraîcheur des données.

Depuis la console PostgreSQL :

```sql
\i /workspace-queries/business_questions.sql
```

## Réinitialisation

Les scripts d'initialisation ne s'exécutent que lors de la création initiale du volume PostgreSQL.

Pour supprimer les données locales et recréer la base entièrement :

```powershell
.\scripts\db.ps1 reset
```

Le script demande de taper `RESET` avant de supprimer le volume local.

## Organisation du projet

```text
project1/
|-- .env.example
|-- docker-compose.yml
|-- README.md
|-- database/
|   |-- init/
|   |-- pgadmin/
|   |-- queries/
|   `-- tests/
|-- docs/
|-- output/pdf/
`-- scripts/
```

## Prochaine phase

Après validation de cette base, la prochaine étape est d'ajouter une extraction incrémentale Kestra utilisant `updated_at` et les watermarks du schéma `meta`.
