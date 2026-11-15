create or replace TRIGGER TRG_ORDER_NOTIFICATION
AFTER INSERT ON ORDERS
FOR EACH ROW
DECLARE
    v_cust_name  VARCHAR2(4000) := 'Unknown Customer';
    v_comp_id    NUMBER;
    v_postcode   VARCHAR2(4000);
    v_message    VARCHAR2(4000);
BEGIN
    -- Step 1: Get customer name and postcode
    BEGIN
        SELECT
            c.CUST_NAME || ' ' || c.CUST_SURNAME,
            c.CUST_POSTCODE
        INTO v_cust_name, v_postcode
        FROM CUSTOMER c
        WHERE c.CUST_ID = :NEW.ORDR_CUST_FK;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        v_cust_name := 'Unknown Customer';
        v_postcode  := NULL;
    END;

    -- Step 2: Get correct company from LOCATION via postcode
    BEGIN
        SELECT l.LOCA_COMP_FK
        INTO v_comp_id
        FROM LOCATION_POSTCODE lp
        JOIN LOCATION l ON l.LOCA_ID = lp.LOPO_LOCA_FK
        WHERE lp.LOPO_NAME   = v_postcode
          AND lp.LOPO_ACTIVE_YN  = 'YES'
          AND lp.LOPO_DELETED_YN = 'NO'
          AND l.LOCA_ACTIVE_YN   = 'YES'
          AND l.LOCA_DELETED_YN  = 'NO'
        FETCH FIRST 1 ROWS ONLY;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        v_comp_id := NULL;
    END;

    -- Step 3: Fallback - get first active company
    IF v_comp_id IS NULL THEN
        BEGIN
            SELECT LOCA_COMP_FK
            INTO v_comp_id
            FROM LOCATION
            WHERE LOCA_ACTIVE_YN  = 'YES'
              AND LOCA_DELETED_YN = 'NO'
            FETCH FIRST 1 ROWS ONLY;
        EXCEPTION WHEN OTHERS THEN
            v_comp_id := NULL;
        END;
    END IF;

    -- Step 4: Build message
    v_message := 'New order from ' || v_cust_name ||
                 ' | ' || TO_CHAR(:NEW.ORDR_START_DATE, 'DD.MM.YYYY') ||
                 ' to '   || TO_CHAR(:NEW.ORDR_END_DATE, 'DD.MM.YYYY');

    -- Step 5: Insert notification
    INSERT INTO MG_NOTIFICATIONS (
        NOTI_ID,
        NOTI_TYPE,
        NOTI_TITLE,
        NOTI_MESSAGE,
        NOTI_ORDR_FK,
        NOTI_CUST_FK,
        NOTI_COMP_FK,
        NOTI_CREATED_BY
    ) VALUES (
        MG_NOTI_SEQ.NEXTVAL,
        'NEW_ORDER',
        'New Order Received',
        v_message,
        :NEW.ORDR_ID,
        :NEW.ORDR_CUST_FK,
        v_comp_id,
        'SYSTEM'
    );

EXCEPTION WHEN OTHERS THEN NULL;
END;
/
