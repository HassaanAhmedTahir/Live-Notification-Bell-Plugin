--------------------------------------------------------------------------------
-- S&H Software Solutions
-- Live Notification Bell - Oracle APEX Region Plugin
-- -----------------------------------------------------------------------------
-- Component : PL/SQL Code (render + AJAX callbacks)
-- Version   : 1.0.0
-- Date      : 2026-10-22
-- Author    : S&H Software Solutions
-- License   : MIT License. This code is free and open to use, modify,
--             and redistribute, with or without attribution, for
--             personal or commercial projects.
-- -----------------------------------------------------------------------------
-- Built for Oracle APEX 23.2 with Oracle Database 19.
-- Render callback : render_notification
-- AJAX callback   : ajax_notification
-- Requires        : MG_NOTIFICATIONS table, MGOR_NOTIFICATIONS_PKG package
--
-- The bell + panel HTML is built by one procedure (print_content), used on
-- page render and by the AJAX action "REFRESH", so a live refresh always
-- returns exactly the same markup as the first page load.
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- CONFIG RECORD
--------------------------------------------------------------------------------
TYPE t_config IS RECORD (
      max_notifications     NUMBER
    , title                 VARCHAR2(4000)
    , icon_class            VARCHAR2(4000)
    , show_badge_yn         VARCHAR2(1)
    , show_header_count_yn  VARCHAR2(1)
    , empty_message         VARCHAR2(4000)
    , show_datetime_yn      VARCHAR2(1)
    , polling_yn            VARCHAR2(1)
    , poll_interval         NUMBER
    , show_mark_all_yn      VARCHAR2(1)
    , mark_read_click_yn    VARCHAR2(1)
);


--------------------------------------------------------------------------------
-- GET CURRENT USER COMPANY
--------------------------------------------------------------------------------
FUNCTION get_current_company_id
RETURN NUMBER
IS
    l_comp_id USERS.USER_COMP_FK%TYPE;
BEGIN

    SELECT USER_COMP_FK
      INTO l_comp_id
      FROM USERS
     WHERE LOWER(USER_EMAIL) = LOWER(V('APP_USER'))
       AND ROWNUM = 1;

    RETURN l_comp_id;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN -1;

END get_current_company_id;


--------------------------------------------------------------------------------
-- READ PLUGIN ATTRIBUTES
--
-- 01 = Maximum Notifications
-- 02 = Notification Title
-- 03 = Bell Icon
-- 04 = Show Unread Badge
-- 05 = Show Header Count
-- 06 = Empty Message
-- 07 = Show Date & Time
-- 08 = Enable Live Polling
-- 09 = Polling Interval (Seconds)
-- 10 = Show Mark All as Read
-- 11 = Mark Read on Click
--------------------------------------------------------------------------------
FUNCTION get_config (
    p_region IN apex_plugin.t_region
)
RETURN t_config
IS
    l_cfg   t_config;
    l_icon  VARCHAR2(4000);
BEGIN

    l_cfg.max_notifications :=
        NVL(
            TO_NUMBER(p_region.attribute_01 DEFAULT NULL ON CONVERSION ERROR),
            10
        );

    l_cfg.max_notifications :=
        LEAST(GREATEST(l_cfg.max_notifications, 1), 100);

    l_cfg.title                := NVL(p_region.attribute_02, 'Notifications');
    l_icon                     := NVL(p_region.attribute_03, 'fa-bell');
    l_cfg.show_badge_yn        := NVL(p_region.attribute_04, 'Y');
    l_cfg.show_header_count_yn := NVL(p_region.attribute_05, 'Y');
    l_cfg.empty_message        := NVL(p_region.attribute_06, 'You''re all caught up!');
    l_cfg.show_datetime_yn     := NVL(p_region.attribute_07, 'Y');
    l_cfg.polling_yn           := NVL(p_region.attribute_08, 'Y');
    l_cfg.show_mark_all_yn     := NVL(p_region.attribute_10, 'Y');
    l_cfg.mark_read_click_yn   := NVL(p_region.attribute_11, 'Y');

    l_cfg.poll_interval :=
        GREATEST(
            NVL(
                TO_NUMBER(p_region.attribute_09 DEFAULT NULL ON CONVERSION ERROR),
                10
            ),
            5
        );

    IF INSTR(LOWER(l_icon), 'fa ') = 1 THEN
        l_cfg.icon_class := l_icon;
    ELSE
        l_cfg.icon_class := 'fa ' || l_icon;
    END IF;

    RETURN l_cfg;

END get_config;

--------------------------------------------------------------------------------
-- PRINT BELL + PANEL
--
-- Used by the render function AND by the AJAX "REFRESH" action, so the
-- markup after a live refresh is exactly the same as on page load.
--------------------------------------------------------------------------------
PROCEDURE print_content (
      p_cfg      IN t_config
    , p_comp_id  IN NUMBER
)
IS
    l_unread_count  NUMBER := 0;
    l_total_count   NUMBER := 0;
    l_latest_id     NUMBER := 0;
BEGIN

    l_unread_count :=
        NVL(
            MGOR_NOTIFICATIONS_PKG.get_unread_count(
                pi_comp_id => p_comp_id
            ),
            0
        );

    SELECT COUNT(*)
         , NVL(MAX(NOTI_ID), 0)
      INTO l_total_count
         , l_latest_id
      FROM MG_NOTIFICATIONS
     WHERE NOTI_COMP_FK = p_comp_id;


    --------------------------------------------------------------------------
    -- INNER WRAPPER (carries the polling baseline)
    --------------------------------------------------------------------------
    htp.p(
        '<div class="mg-noti-inner" ' ||
        'data-unread-count="' || TO_CHAR(l_unread_count) || '" ' ||
        'data-latest-id="'    || TO_CHAR(l_latest_id)    || '">'
    );


    --------------------------------------------------------------------------
    -- BELL BUTTON
    --------------------------------------------------------------------------
    htp.p(
        '<button type="button" class="mg-noti-bell" ' ||
        'aria-label="' || apex_escape.html_attribute(p_cfg.title) || '" ' ||
        'aria-expanded="false">'
    );

    htp.p(
        '<span class="' || apex_escape.html_attribute(p_cfg.icon_class) ||
        ' mg-noti-bell-icon" aria-hidden="true"></span>'
    );

    IF p_cfg.show_badge_yn = 'Y'
       AND l_unread_count > 0
    THEN
        htp.p(
            '<span class="mg-noti-badge">' ||
            CASE
                WHEN l_unread_count > 99 THEN '99+'
                ELSE TO_CHAR(l_unread_count)
            END ||
            '</span>'
        );
    END IF;

    htp.p('</button>');


    --------------------------------------------------------------------------
    -- PANEL
    --------------------------------------------------------------------------
    htp.p(
        '<section class="mg-noti-panel" role="dialog" ' ||
        'aria-label="' || apex_escape.html_attribute(p_cfg.title) || '" ' ||
        'style="display:none;">'
    );


    --------------------------------------------------------------------------
    -- HEADER
    --------------------------------------------------------------------------
    htp.p('<div class="mg-noti-header">');
    htp.p('<div class="mg-noti-header-main">');

    htp.p(
        '<div class="mg-noti-header-icon">' ||
            '<span class="' || apex_escape.html_attribute(p_cfg.icon_class) || '"></span>' ||
        '</div>'
    );

    htp.p(
        '<div class="mg-noti-header-text">' ||
            '<div class="mg-noti-title">' || apex_escape.html(p_cfg.title) || '</div>' ||
            '<div class="mg-noti-subtitle">Your latest activity</div>' ||
        '</div>'
    );

    htp.p('</div>');

    IF p_cfg.show_header_count_yn = 'Y' THEN
        htp.p(
            '<span class="mg-noti-header-count">' ||
            TO_CHAR(l_unread_count) || ' unread' ||
            '</span>'
        );
    END IF;

    htp.p('</div>');


    --------------------------------------------------------------------------
    -- LIST
    --------------------------------------------------------------------------
    htp.p('<div class="mg-noti-list">');

    IF l_unread_count = 0 THEN

        htp.p(
            '<div class="mg-noti-empty">' ||
                '<div class="mg-noti-empty-icon"><span class="fa fa-check"></span></div>' ||
                '<div class="mg-noti-empty-title">' || apex_escape.html(p_cfg.empty_message) || '</div>' ||
                '<div class="mg-noti-empty-text">You have no unread notifications.</div>' ||
            '</div>'
        );

    ELSE

        FOR r IN (
            SELECT *
              FROM (
                    SELECT NOTI_ID
                         , NOTI_TITLE
                         , NOTI_MESSAGE
                         , NOTI_READ_YN
                         , TO_CHAR(NOTI_CREATED, 'DD Mon YYYY HH24:MI') AS NOTI_TIME
                      FROM MG_NOTIFICATIONS
                     WHERE NOTI_COMP_FK = p_comp_id
                     ORDER BY NOTI_ID DESC
                   )
             WHERE ROWNUM <= p_cfg.max_notifications
        )
        LOOP

            htp.p(
                '<article class="mg-noti-item ' ||
                CASE WHEN r.NOTI_READ_YN = 'NO' THEN 'is-unread' ELSE 'is-read' END ||
                '" data-noti-id="' || TO_CHAR(r.NOTI_ID) || '" tabindex="0">'
            );

            htp.p(
                '<div class="mg-noti-item-icon">' ||
                    '<span class="fa fa-shopping-cart"></span>' ||
                '</div>'
            );

            htp.p('<div class="mg-noti-content">');

            htp.p(
                '<div class="mg-noti-item-title">' ||
                    apex_escape.html(NVL(r.NOTI_TITLE, 'Notification')) ||
                '</div>'
            );

            htp.p(
                '<div class="mg-noti-message">' ||
                    apex_escape.html(DBMS_LOB.SUBSTR(r.NOTI_MESSAGE, 4000, 1)) ||
                '</div>'
            );

            IF p_cfg.show_datetime_yn = 'Y' THEN
                htp.p(
                    '<div class="mg-noti-time">' ||
                        '<span class="fa fa-clock-o"></span>' ||
                        '<span>' || apex_escape.html(r.NOTI_TIME) || '</span>' ||
                    '</div>'
                );
            END IF;

            htp.p('</div>');

            IF r.NOTI_READ_YN = 'NO' THEN
                htp.p('<span class="mg-noti-unread-dot" aria-label="Unread"></span>');
            END IF;

            htp.p('</article>');

        END LOOP;

    END IF;

    htp.p('</div>');


    --------------------------------------------------------------------------
    -- FOOTER
    --------------------------------------------------------------------------
    IF p_cfg.show_mark_all_yn = 'Y'
       AND l_unread_count > 0
    THEN
        htp.p(
            '<div class="mg-noti-footer">' ||
                '<button type="button" class="mg-noti-mark-all">' ||
                    '<span class="fa fa-check-circle-o"></span>' ||
                    '<span>Mark all as read</span>' ||
                '</button>' ||
            '</div>'
        );
    END IF;

    htp.p('</section>');
    htp.p('</div>');   -- .mg-noti-inner

END print_content;

--------------------------------------------------------------------------------
-- RENDER
--------------------------------------------------------------------------------
FUNCTION render_notification (
      p_region               IN apex_plugin.t_region
    , p_plugin               IN apex_plugin.t_plugin
    , p_is_printer_friendly  IN BOOLEAN
)
RETURN apex_plugin.t_region_render_result
IS
    l_result         apex_plugin.t_region_render_result;
    l_cfg            t_config;
    l_instance_id    VARCHAR2(255);
    l_region_dom_id  VARCHAR2(255);
BEGIN

    l_cfg := get_config(p_region);

    l_instance_id   := 'mgNoti_' || p_region.id;

    -- Real DOM id of the region: Static ID, or APEX default "R<region id>"
    l_region_dom_id := NVL(p_region.static_id, 'R' || p_region.id);


    --------------------------------------------------------------------------
    -- ROOT (stays on the page; only .mg-noti-inner is swapped on refresh)
    --------------------------------------------------------------------------
    htp.p(
        '<div id="'               || apex_escape.html_attribute(l_instance_id) || '" ' ||
        'class="mg-noti-plugin" ' ||
        'data-instance-id="'      || apex_escape.html_attribute(l_instance_id) || '" ' ||
        'data-region-id="'        || apex_escape.html_attribute(l_region_dom_id) || '" ' ||
        'data-ajax-id="'          || apex_escape.html_attribute(apex_plugin.get_ajax_identifier) || '" ' ||
        'data-polling="'          || apex_escape.html_attribute(l_cfg.polling_yn) || '" ' ||
        'data-poll-interval="'    || TO_CHAR(l_cfg.poll_interval) || '" ' ||
        'data-mark-read-click="'  || apex_escape.html_attribute(l_cfg.mark_read_click_yn) || '" ' ||
        'data-empty-message="'    || apex_escape.html_attribute(l_cfg.empty_message) || '">'
    );

    print_content(
          p_cfg     => l_cfg
        , p_comp_id => get_current_company_id
    );

    htp.p('</div>');

    RETURN l_result;

END render_notification;

--------------------------------------------------------------------------------
-- AJAX CALLBACK
--
-- x01:
--   CHECK_NEW      -> JSON  { success, hasNew, latestId, unreadCount }
--   REFRESH        -> HTML  (the .mg-noti-inner block)
--   MARK_READ      -> JSON  { success, unreadCount }
--   MARK_ALL_READ  -> JSON  { success, unreadCount }
--
-- x02:
--   CHECK_NEW  = latest NOTI_ID the browser knows
--   MARK_READ  = NOTI_ID to mark
--------------------------------------------------------------------------------
FUNCTION ajax_notification (
      p_region IN apex_plugin.t_region
    , p_plugin IN apex_plugin.t_plugin
)
RETURN apex_plugin.t_region_ajax_result
IS
    l_result          apex_plugin.t_region_ajax_result;

    l_action          VARCHAR2(100) := UPPER(NVL(apex_application.g_x01, 'CHECK_NEW'));
    l_comp_id         NUMBER;

    l_noti_id         NUMBER;
    l_count           NUMBER := 0;
    l_exists          NUMBER := 0;

    l_latest_id       NUMBER := 0;
    l_client_last_id  NUMBER := 0;
BEGIN

    l_comp_id := get_current_company_id;


    --------------------------------------------------------------------------
    -- REFRESH : return fresh bell + panel HTML
    --------------------------------------------------------------------------
    IF l_action = 'REFRESH' THEN

        print_content(
              p_cfg     => get_config(p_region)
            , p_comp_id => l_comp_id
        );

        RETURN l_result;

    END IF;


    --------------------------------------------------------------------------
    -- CHECK NEW
    --------------------------------------------------------------------------
    IF l_action = 'CHECK_NEW' THEN

        l_client_last_id :=
            NVL(
                TO_NUMBER(apex_application.g_x02 DEFAULT 0 ON CONVERSION ERROR),
                0
            );

        SELECT NVL(MAX(NOTI_ID), 0)
          INTO l_latest_id
          FROM MG_NOTIFICATIONS
         WHERE NOTI_COMP_FK = l_comp_id;

        l_count :=
            NVL(MGOR_NOTIFICATIONS_PKG.get_unread_count(pi_comp_id => l_comp_id), 0);

        apex_json.open_object;
        apex_json.write(p_name => 'success',     p_value => TRUE);
        apex_json.write(p_name => 'hasNew',      p_value => l_latest_id > l_client_last_id);
        apex_json.write(p_name => 'latestId',    p_value => l_latest_id);
        apex_json.write(p_name => 'unreadCount', p_value => l_count);
        apex_json.close_object;


    --------------------------------------------------------------------------
    -- MARK ONE READ
    --------------------------------------------------------------------------
    ELSIF l_action = 'MARK_READ' THEN

        l_noti_id :=
            TO_NUMBER(apex_application.g_x02 DEFAULT NULL ON CONVERSION ERROR);

        SELECT COUNT(*)
          INTO l_exists
          FROM MG_NOTIFICATIONS
         WHERE NOTI_ID      = l_noti_id
           AND NOTI_COMP_FK = l_comp_id;

        IF l_exists = 1 THEN
            MGOR_NOTIFICATIONS_PKG.mark_read(pi_noti_id => l_noti_id);
        END IF;

        l_count :=
            NVL(MGOR_NOTIFICATIONS_PKG.get_unread_count(pi_comp_id => l_comp_id), 0);

        apex_json.open_object;
        apex_json.write(p_name => 'success',     p_value => TRUE);
        apex_json.write(p_name => 'unreadCount', p_value => l_count);
        apex_json.close_object;


    --------------------------------------------------------------------------
    -- MARK ALL READ
    --------------------------------------------------------------------------
    ELSIF l_action = 'MARK_ALL_READ' THEN

        UPDATE MG_NOTIFICATIONS
           SET NOTI_READ_YN = 'YES'
         WHERE NOTI_COMP_FK = l_comp_id
           AND NOTI_READ_YN = 'NO';

        -- Re-count: an order may have arrived in the same second
        l_count :=
            NVL(MGOR_NOTIFICATIONS_PKG.get_unread_count(pi_comp_id => l_comp_id), 0);

        apex_json.open_object;
        apex_json.write(p_name => 'success',     p_value => TRUE);
        apex_json.write(p_name => 'unreadCount', p_value => l_count);
        apex_json.close_object;


    --------------------------------------------------------------------------
    -- UNKNOWN
    --------------------------------------------------------------------------
    ELSE

        apex_json.open_object;
        apex_json.write(p_name => 'success', p_value => FALSE);
        apex_json.write(p_name => 'message', p_value => 'Unknown notification action.');
        apex_json.close_object;

    END IF;

    RETURN l_result;

EXCEPTION
    WHEN OTHERS THEN

        apex_debug.error('Live Notification Bell [%s]: %s', l_action, SQLERRM);

        IF l_action = 'REFRESH' THEN
            RAISE;
        END IF;

        apex_json.open_object;
        apex_json.write(p_name => 'success', p_value => FALSE);
        apex_json.write(p_name => 'message', p_value => 'Notification request failed.');
        apex_json.close_object;

        RETURN l_result;

END ajax_notification;
