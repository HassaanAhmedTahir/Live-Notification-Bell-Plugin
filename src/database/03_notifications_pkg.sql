create or replace PACKAGE MGOR_NOTIFICATIONS_PKG AS

PROCEDURE send_push_notification(
    pi_comp_id  IN NUMBER
  , pi_title    IN VARCHAR2
  , pi_message  IN VARCHAR2
  , pi_ordr_id  IN NUMBER DEFAULT NULL

);

PROCEDURE mark_read(
    pi_noti_id IN NUMBER

);

FUNCTION get_unread_count(
    pi_comp_id IN NUMBER
) RETURN NUMBER;

END MGOR_NOTIFICATIONS_PKG;
/

create or replace PACKAGE BODY MGOR_NOTIFICATIONS_PKG AS

PROCEDURE send_push_notification(
    pi_comp_id  IN NUMBER
  , pi_title    IN VARCHAR2
  , pi_message  IN VARCHAR2
  , pi_ordr_id  IN NUMBER DEFAULT NULL

)
IS
    BEGIN
        FOR r IN (
            SELECT USER_EMAIL
            FROM USERS
            WHERE USER_COMP_FK = pi_comp_id
        ) LOOP
            BEGIN
                APEX_PWA.SEND_PUSH_NOTIFICATION(
                    p_application_id => 148,
                    p_user_name      => r.USER_EMAIL,
                    p_title          => pi_title,
                    p_body           => pi_message
                );
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;
    END send_push_notification;

PROCEDURE mark_read(
    pi_noti_id IN NUMBER
)
IS
    BEGIN
        UPDATE MG_NOTIFICATIONS
        SET    NOTI_READ_YN = 'YES'
        WHERE  NOTI_ID = pi_noti_id;
        COMMIT;
    END mark_read;

FUNCTION get_unread_count(
    pi_comp_id IN NUMBER
) RETURN NUMBER

IS
    v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*)
        INTO   v_count
        FROM   MG_NOTIFICATIONS
        WHERE  NOTI_COMP_FK = pi_comp_id
        AND    NOTI_READ_YN = 'NO';
        RETURN v_count;
    EXCEPTION WHEN OTHERS THEN
        RETURN 0;
    END get_unread_count;

END MGOR_NOTIFICATIONS_PKG;
/
