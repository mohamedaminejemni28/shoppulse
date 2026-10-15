-- Demande à psql d'arrêter immédiatement le script si une erreur apparaît
\set ON_ERROR_STOP on


-- ============================================================
-- DÉBUT DE LA TRANSACTION
-- ============================================================

-- Toutes les opérations suivantes font partie d'une même transaction
BEGIN;



-- ============================================================
-- 1. FONCTION : mise à jour automatique de updated_at
-- ============================================================

-- Crée la fonction set_updated_at dans le schéma shop
-- OR REPLACE = remplace la fonction si elle existe déjà
CREATE OR REPLACE FUNCTION shop.set_updated_at()

-- Cette fonction sera utilisée par un trigger
RETURNS trigger

-- La fonction est écrite en PL/pgSQL
LANGUAGE plpgsql

-- Début du corps de la fonction
AS $$
BEGIN

    -- NEW représente la nouvelle version de la ligne
    -- On remplace automatiquement updated_at par la date/heure actuelle
    NEW.updated_at := now();

    -- On retourne la nouvelle ligne modifiée
    RETURN NEW;

END;
$$;










-- ============================================================
-- 2. FONCTION : calcul automatique du total d'une commande
-- ============================================================

-- Crée une fonction qui calcule la taxe et le total d'une commande
CREATE OR REPLACE FUNCTION shop.calculate_order_totals()

-- Fonction appelée par un trigger
RETURNS trigger

-- Langage PostgreSQL procédural
LANGUAGE plpgsql

AS $$
BEGIN

    -- Calcul de la taxe :
    -- base taxable = subtotal - discount
    -- greatest(..., 0) empêche une valeur négative
    -- 0.075 = taxe de 7,5 %
    -- round(..., 2) garde 2 chiffres après la virgule
    NEW.tax_amount :=
        round(
            greatest(
                NEW.subtotal_amount - NEW.discount_amount,
                0
            ) * 0.075,
            2
        );

    -- Calcul du montant total :
    -- sous-total
    -- - réduction
    -- + livraison
    -- + taxe
    NEW.total_amount := round(

        NEW.subtotal_amount
        - NEW.discount_amount
        + NEW.shipping_amount
        + NEW.tax_amount,

        2
    );

    -- Retourne la commande avec les nouvelles valeurs calculées
    RETURN NEW;

END;
$$;














-- ============================================================
-- 3. FONCTION : recalculer le sous-total d'une commande
-- ============================================================

-- Cette fonction reçoit l'identifiant d'une commande
CREATE OR REPLACE FUNCTION shop.refresh_one_order_total(
    target_order_id bigint
)

-- La fonction ne retourne aucune valeur
RETURNS void

-- Fonction écrite en PL/pgSQL
LANGUAGE plpgsql

AS $$

-- Déclaration des variables locales
DECLARE

    -- Variable qui va contenir le nouveau sous-total
    new_subtotal numeric(12, 2);

BEGIN

    -- Additionne tous les line_total des produits de la commande
    SELECT coalesce(sum(line_total), 0)

    -- Stocke le résultat dans la variable new_subtotal
    INTO new_subtotal

    -- Table contenant les produits des commandes
    FROM shop.order_items

    -- On prend uniquement les produits de cette commande
    WHERE order_id = target_order_id;


    -- Met à jour la commande correspondante
    UPDATE shop.orders

    -- Remplace son subtotal_amount par le nouveau calcul
    SET subtotal_amount = new_subtotal

    -- Pour la commande concernée uniquement
    WHERE order_id = target_order_id;

END;
$$;



-- ============================================================
-- 4. FONCTION : recalcul après modification de order_items
-- ============================================================

-- Cette fonction sera exécutée lorsqu'un produit est
-- ajouté, modifié ou supprimé dans une commande
CREATE OR REPLACE FUNCTION shop.refresh_order_totals_from_items()

-- Fonction destinée à un trigger
RETURNS trigger

LANGUAGE plpgsql

AS $$
BEGIN

    -- TG_OP contient le type d'opération :
    -- INSERT, UPDATE ou DELETE

    -- Si un produit est supprimé d'une commande
    IF TG_OP = 'DELETE' THEN

        -- Recalcule le total de l'ancienne commande
        -- OLD = ligne avant suppression
        PERFORM shop.refresh_one_order_total(OLD.order_id);

        -- Pour DELETE on retourne OLD
        RETURN OLD;


    -- Si un produit est ajouté
    ELSIF TG_OP = 'INSERT' THEN

        -- Recalcule la commande concernée
        PERFORM shop.refresh_one_order_total(NEW.order_id);

        -- Retourne la nouvelle ligne
        RETURN NEW;


    -- Sinon, il s'agit d'un UPDATE
    ELSE

        -- Recalcule l'ancienne commande
        PERFORM shop.refresh_one_order_total(OLD.order_id);


        -- Vérifie si le produit a été déplacé vers une autre commande
        IF NEW.order_id <> OLD.order_id THEN

            -- Recalcule également la nouvelle commande
            PERFORM shop.refresh_one_order_total(NEW.order_id);

        END IF;

        -- Retourne la ligne modifiée
        RETURN NEW;

    END IF;

END;
$$;



-- ============================================================
-- 5. FONCTION : historique des statuts des commandes
-- ============================================================

-- Cette fonction enregistre chaque changement de statut
CREATE OR REPLACE FUNCTION shop.record_order_status_change()

RETURNS trigger

LANGUAGE plpgsql

AS $$
BEGIN

    -- Si une nouvelle commande vient d'être créée
    IF TG_OP = 'INSERT' THEN

        -- Insère une ligne dans l'historique
        INSERT INTO shop.order_status_history (
            order_id,
            previous_status,
            new_status,
            changed_at,
            change_source
        )

        VALUES (
            NEW.order_id,       -- commande concernée
            NULL,               -- pas de statut précédent
            NEW.order_status,   -- statut initial
            NEW.created_at,     -- date de création
            'order_insert'      -- origine du changement
        );


    -- Si le statut a réellement changé pendant un UPDATE
    ELSIF NEW.order_status IS DISTINCT FROM OLD.order_status THEN

        -- Ajoute le changement dans l'historique
        INSERT INTO shop.order_status_history (
            order_id,
            previous_status,
            new_status,
            changed_at,
            change_source
        )

        VALUES (
            NEW.order_id,       -- commande concernée
            OLD.order_status,   -- ancien statut
            NEW.order_status,   -- nouveau statut
            now(),              -- date du changement
            'order_update'      -- changement venant d'un UPDATE
        );

    END IF;

    -- Retourne la commande
    RETURN NEW;

END;
$$;



-- ============================================================
-- 6. FONCTION : validation et normalisation des paiements
-- ============================================================

CREATE OR REPLACE FUNCTION shop.normalize_payment()

RETURNS trigger

LANGUAGE plpgsql

AS $$

-- Variables utilisées dans la fonction
DECLARE

    -- Devise de la commande
    order_currency char(3);

    -- Montant total de la commande
    order_total numeric(12, 2);

BEGIN

    -- Récupère la devise et le montant de la commande
    SELECT
        currency,
        total_amount

    -- Place les valeurs dans nos variables
    INTO
        order_currency,
        order_total

    FROM shop.orders

    -- Recherche la commande associée au paiement
    WHERE order_id = NEW.order_id;


    -- Si aucune commande n'a été trouvée
    IF order_currency IS NULL THEN

        -- Bloque l'opération avec une erreur
        RAISE EXCEPTION
            'Commande % introuvable pour le paiement',
            NEW.order_id;

    END IF;


    -- Vérifie que la devise du paiement correspond
    -- à la devise de la commande
    IF NEW.currency <> order_currency THEN

        RAISE EXCEPTION
            'La devise du paiement (%) ne correspond pas à la commande (%)',
            NEW.currency,
            order_currency;

    END IF;


    -- Empêche un paiement supérieur au montant de la commande
    IF NEW.amount > order_total THEN

        RAISE EXCEPTION
            'Le paiement (%) dépasse le total de la commande (%)',
            NEW.amount,
            order_total;

    END IF;


    -- Si le paiement a atteint un état final ou traité
    IF NEW.payment_status IN (
        'authorized',
        'succeeded',
        'failed',
        'cancelled',
        'refunded'
    )

    -- Et si processed_at n'a pas encore été renseigné
    AND NEW.processed_at IS NULL THEN

        -- Ajoute automatiquement la date de traitement
        NEW.processed_at := now();

    END IF;


    -- Retourne le paiement validé/modifié
    RETURN NEW;

END;
$$;



-- ============================================================
-- 7. FONCTION : appliquer un paiement réussi à une commande
-- ============================================================

CREATE OR REPLACE FUNCTION shop.apply_successful_payment()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

    -- Indique si le paiement vient de devenir réussi
    became_successful boolean := false;

BEGIN

    -- Si on insère un nouveau paiement
    IF TG_OP = 'INSERT' THEN

        -- true uniquement si son statut est succeeded
        became_successful :=
            NEW.payment_status = 'succeeded';


    -- Si on modifie un paiement existant
    ELSIF TG_OP = 'UPDATE' THEN

        -- true si le nouveau statut est succeeded
        -- ET que l'ancien statut était différent
        became_successful :=
            NEW.payment_status = 'succeeded'
            AND OLD.payment_status IS DISTINCT FROM NEW.payment_status;

    END IF;


    -- Si le paiement vient de devenir réussi
    IF became_successful THEN

        -- Met à jour la commande associée
        UPDATE shop.orders

        SET

            -- Enregistre la date de paiement
            -- coalesce prend la première valeur non NULL
            paid_at = coalesce(
                paid_at,
                NEW.processed_at,
                now()
            ),


            -- Modifie le statut de la commande
            order_status = CASE

                -- Si la commande attend encore le paiement
                WHEN order_status IN (
                    'created',
                    'pending_payment'
                )

                -- Elle devient payée
                THEN 'paid'

                -- Sinon on garde son statut actuel
                ELSE order_status

            END

        -- Commande correspondant au paiement
        WHERE order_id = NEW.order_id;

    END IF;


    RETURN NEW;

END;
$$;



-- ============================================================
-- 8. FONCTION : vérifier un remboursement
-- ============================================================

CREATE OR REPLACE FUNCTION shop.validate_refund()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

    -- Montant du paiement original
    payment_amount numeric(12, 2);

    -- Statut du paiement original
    payment_status text;

    -- Montant déjà remboursé
    already_refunded numeric(12, 2);

BEGIN

    -- Récupère les informations du paiement
    SELECT
        p.amount,
        p.payment_status

    INTO
        payment_amount,
        payment_status

    FROM shop.payments AS p

    WHERE p.payment_id = NEW.payment_id;


    -- Autorise le remboursement uniquement
    -- si le paiement a réussi ou a déjà été partiellement remboursé
    IF payment_status NOT IN (
        'succeeded',
        'refunded'
    ) THEN

        RAISE EXCEPTION
            'Seul un paiement réussi peut être remboursé';

    END IF;


    -- Calcule le montant déjà remboursé
    SELECT coalesce(sum(amount), 0)

    INTO already_refunded

    FROM shop.refunds

    WHERE payment_id = NEW.payment_id

      -- On compte seulement les remboursements
      -- en attente ou réussis
      AND refund_status IN (
          'pending',
          'succeeded'
      )

      -- Évite de compter le remboursement actuel deux fois
      AND refund_id <> coalesce(
          NEW.refund_id,
          -1
      );


    -- Vérifie que le remboursement total
    -- ne dépasse pas le paiement original
    IF already_refunded + NEW.amount > payment_amount THEN

        RAISE EXCEPTION
            'Le remboursement total dépasse le paiement : % + % > %',
            already_refunded,
            NEW.amount,
            payment_amount;

    END IF;


    -- Si le remboursement a atteint un état final
    IF NEW.refund_status IN (
        'succeeded',
        'failed',
        'cancelled'
    )

    -- Et qu'aucune date de traitement n'existe
    AND NEW.processed_at IS NULL THEN

        -- Ajoute automatiquement la date
        NEW.processed_at := now();

    END IF;


    RETURN NEW;

END;
$$;



-- ============================================================
-- 9. FONCTION : appliquer un remboursement réussi
-- ============================================================

CREATE OR REPLACE FUNCTION shop.apply_successful_refund()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

    -- Identifiant de la commande concernée
    target_order_id bigint;

    -- Montant initial du paiement
    payment_amount numeric(12, 2);

    -- Montant total déjà remboursé
    refunded_amount numeric(12, 2);

    -- Indique si ce remboursement vient de réussir
    became_successful boolean := false;

BEGIN

    -- Lors d'un INSERT
    IF TG_OP = 'INSERT' THEN

        became_successful :=
            NEW.refund_status = 'succeeded';


    -- Lors d'un UPDATE
    ELSIF TG_OP = 'UPDATE' THEN

        became_successful :=
            NEW.refund_status = 'succeeded'

            -- Vérifie que le statut vient réellement de changer
            AND OLD.refund_status
                IS DISTINCT FROM NEW.refund_status;

    END IF;


    -- Si le remboursement vient de réussir
    IF became_successful THEN

        -- Récupère la commande et le montant du paiement
        SELECT
            p.order_id,
            p.amount

        INTO
            target_order_id,
            payment_amount

        FROM shop.payments AS p

        WHERE p.payment_id = NEW.payment_id;


        -- Additionne tous les remboursements réussis
        SELECT coalesce(sum(r.amount), 0)

        INTO refunded_amount

        FROM shop.refunds AS r

        WHERE r.payment_id = NEW.payment_id

          AND r.refund_status = 'succeeded';


        -- Si tout le paiement a été remboursé
        IF refunded_amount >= payment_amount THEN


            -- Change le statut du paiement
            UPDATE shop.payments

            SET payment_status = 'refunded'

            WHERE payment_id = NEW.payment_id;


            -- Change également le statut de la commande
            UPDATE shop.orders

            SET order_status = 'refunded'

            WHERE order_id = target_order_id

              -- Ne modifie pas une commande déjà annulée
              AND order_status <> 'cancelled';

        END IF;

    END IF;


    RETURN NEW;

END;
$$;



-- ============================================================
--                  CRÉATION DES TRIGGERS
-- ============================================================



-- ============================================================
-- TRIGGER 1 : customers.updated_at
-- ============================================================

-- Crée un trigger sur customers
CREATE TRIGGER trg_customers_updated_at

-- Il s'exécute AVANT chaque UPDATE
BEFORE UPDATE ON shop.customers

-- Pour chaque ligne modifiée
FOR EACH ROW

-- Appelle la fonction set_updated_at
EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- TRIGGER 2 : customer_addresses.updated_at
-- ============================================================

CREATE TRIGGER trg_addresses_updated_at

-- Avant une modification d'adresse
BEFORE UPDATE ON shop.customer_addresses

-- Pour chaque adresse modifiée
FOR EACH ROW

-- Met automatiquement updated_at à maintenant
EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- TRIGGER 3 : categories.updated_at
-- ============================================================

CREATE TRIGGER trg_categories_updated_at

BEFORE UPDATE ON shop.categories

FOR EACH ROW

EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- TRIGGER 4 : products.updated_at
-- ============================================================

CREATE TRIGGER trg_products_updated_at

BEFORE UPDATE ON shop.products

FOR EACH ROW

EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- TRIGGER 5 : inventory.updated_at
-- ============================================================

CREATE TRIGGER trg_inventory_updated_at

BEFORE UPDATE ON shop.inventory

FOR EACH ROW

EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- TRIGGER 6 : calcul automatique du total des commandes
-- ============================================================

CREATE TRIGGER trg_orders_calculate_totals

-- Avant :
-- 1. l'insertion d'une commande
-- OU
-- 2. une modification de subtotal, discount ou shipping
BEFORE INSERT
OR UPDATE OF
    subtotal_amount,
    discount_amount,
    shipping_amount

-- Sur la table orders
ON shop.orders

-- Pour chaque commande
FOR EACH ROW

-- Calcule automatiquement taxe et total
EXECUTE FUNCTION shop.calculate_order_totals();



-- ============================================================
-- TRIGGER 7 : orders.updated_at
-- ============================================================

CREATE TRIGGER trg_orders_updated_at

BEFORE UPDATE ON shop.orders

FOR EACH ROW

EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- TRIGGER 8 : historique du statut des commandes
-- ============================================================

CREATE TRIGGER trg_orders_status_history

-- Après création d'une commande
-- OU modification de order_status
AFTER INSERT
OR UPDATE OF order_status

ON shop.orders

FOR EACH ROW

-- Enregistre le changement dans order_status_history
EXECUTE FUNCTION shop.record_order_status_change();



-- ============================================================
-- TRIGGER 9 : recalcul après modification des produits
-- ============================================================

CREATE TRIGGER trg_order_items_refresh_totals

-- Après ajout, modification ou suppression d'un produit
AFTER INSERT
OR UPDATE
OR DELETE

ON shop.order_items

FOR EACH ROW

-- Recalcule le subtotal de la commande
EXECUTE FUNCTION shop.refresh_order_totals_from_items();



-- ============================================================
-- TRIGGER 10 : validation des paiements
-- ============================================================

CREATE TRIGGER trg_payments_normalize

-- Avant création ou modification du paiement
BEFORE INSERT OR UPDATE

ON shop.payments

FOR EACH ROW

-- Vérifie :
-- commande existante
-- devise
-- montant
-- processed_at
EXECUTE FUNCTION shop.normalize_payment();



-- ============================================================
-- TRIGGER 11 : payments.updated_at
-- ============================================================

CREATE TRIGGER trg_payments_updated_at

BEFORE UPDATE ON shop.payments

FOR EACH ROW

EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- TRIGGER 12 : paiement réussi
-- ============================================================

CREATE TRIGGER trg_payments_apply_success

-- Après insertion d'un paiement
-- OU changement du payment_status
AFTER INSERT
OR UPDATE OF payment_status

ON shop.payments

FOR EACH ROW

-- Met automatiquement la commande à "paid"
-- lorsqu'un paiement réussit
EXECUTE FUNCTION shop.apply_successful_payment();



-- ============================================================
-- TRIGGER 13 : validation des remboursements
-- ============================================================

CREATE TRIGGER trg_refunds_validate

-- Avant ajout ou modification d'un remboursement
BEFORE INSERT OR UPDATE

ON shop.refunds

FOR EACH ROW

-- Vérifie si le remboursement est autorisé
EXECUTE FUNCTION shop.validate_refund();



-- ============================================================
-- TRIGGER 14 : refunds.updated_at
-- ============================================================

CREATE TRIGGER trg_refunds_updated_at

BEFORE UPDATE ON shop.refunds

FOR EACH ROW

EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- TRIGGER 15 : remboursement réussi
-- ============================================================

CREATE TRIGGER trg_refunds_apply_success

-- Après insertion
-- OU changement du statut du remboursement
AFTER INSERT
OR UPDATE OF refund_status

ON shop.refunds

FOR EACH ROW

-- Vérifie si le paiement est maintenant
-- complètement remboursé
EXECUTE FUNCTION shop.apply_successful_refund();



-- ============================================================
-- TRIGGER 16 : ingestion_watermarks.updated_at
-- ============================================================

CREATE TRIGGER trg_watermarks_updated_at

-- Avant modification d'un watermark
BEFORE UPDATE ON meta.ingestion_watermarks

FOR EACH ROW

-- Actualise automatiquement updated_at
EXECUTE FUNCTION shop.set_updated_at();



-- ============================================================
-- FIN DE LA TRANSACTION
-- ============================================================

-- Valide définitivement toutes les fonctions
-- et tous les triggers créés ci-dessus
COMMIT;