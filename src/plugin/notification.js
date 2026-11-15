/* ======================================================================
   S&H Software Solutions
   Live Notification Bell - Oracle APEX Region Plugin
   ----------------------------------------------------------------------
   Component : JavaScript
   Version   : 1.0.0
   Date      : 2026-10-22
   Author    : S&H Software Solutions
   License   : MIT License. This code is free and open to use, modify,
               and redistribute, with or without attribution, for
               personal or commercial projects.
   ----------------------------------------------------------------------
   How live updates work:
   1. Every <poll interval> seconds -> CHECK_NEW (tiny JSON).
   2. If latestId or unreadCount differs from what the page shows
      -> REFRESH returns fresh bell + panel HTML from the server.
   3. Only the inner block is swapped; the root element, its events
      and the open/closed state of the panel stay intact.
   4. A new notification rings the bell and slides the panel open
      for 5 seconds (hover keeps it open).
   ====================================================================== */
(function ($) {

    "use strict";

    const instances = {};


    /* ============================================================
       HELPERS
       ============================================================ */
    function isYes(value) {
        return ["Y", "YES", "TRUE", "1"].includes(
            String(value || "").toUpperCase()
        );
    }

    function toNum(value, fallback) {
        const n = Number(value);
        return isFinite(n) ? n : fallback;
    }


    /* ============================================================
       CACHE ELEMENTS + BASELINE (after load and after every refresh)
       ============================================================ */
    function cacheElements(state) {

        state.inner = state.root.querySelector(".mg-noti-inner");
        state.bell  = state.root.querySelector(".mg-noti-bell");
        state.panel = state.root.querySelector(".mg-noti-panel");

        state.unreadCount = toNum(state.inner && state.inner.dataset.unreadCount, 0);
        state.latestId    = toNum(state.inner && state.inner.dataset.latestId, 0);
    }


    /* ============================================================
       PANEL POSITION / OPEN / CLOSE
       ============================================================ */
    function positionPanel(state) {

        if (!state.bell || !state.panel) {
            return;
        }

        const rect        = state.bell.getBoundingClientRect();
        const panelWidth  = state.panel.offsetWidth || 410;
        const panelHeight = state.panel.offsetHeight || 500;

        let top  = rect.bottom + 10;
        let left = rect.right - panelWidth;

        if (left < 12) {
            left = 12;
        }

        if (left + panelWidth > window.innerWidth - 12) {
            left = window.innerWidth - panelWidth - 12;
        }

        if (top + panelHeight > window.innerHeight - 12) {
            const above = rect.top - panelHeight - 10;
            if (above >= 12) {
                top = above;
            }
        }

        state.panel.style.top  = top + "px";
        state.panel.style.left = left + "px";
    }

    function openPanel(state, animate) {

        if (!state.panel) {
            return;
        }

        /* Cancel a close animation that is still running */
        window.clearTimeout(state.closeTimer);
        state.panel.classList.remove("is-closing");

        state.panel.classList.toggle("no-anim", animate === false);
        state.panel.style.display = "block";
        state.root.classList.add("is-open");
        state.bell.setAttribute("aria-expanded", "true");
        state.isOpen = true;

        positionPanel(state);
    }

    function closePanel(state) {

        if (!state.panel || !state.isOpen) {
            return;
        }

        const panel = state.panel;

        cancelAutoClose(state);

        state.root.classList.remove("is-open");
        state.bell.setAttribute("aria-expanded", "false");
        state.isOpen = false;

        /*
         * Play the CSS close animation first, hide afterwards.
         * The wait time is read from the CSS (.mg-noti-panel.is-closing),
         * so changing the duration in the CSS needs no JS change.
         */
        panel.classList.remove("no-anim");
        panel.classList.add("is-closing");

        const ms = (parseFloat(window.getComputedStyle(panel).animationDuration) || 0) * 1000;

        window.clearTimeout(state.closeTimer);

        state.closeTimer = window.setTimeout(function () {
            panel.classList.remove("is-closing");
            panel.style.display = "none";
        }, ms);
    }

    function togglePanel(state) {
        cancelAutoClose(state);

        if (state.isOpen) {
            closePanel(state);
        } else {
            openPanel(state, true);
        }
    }

    /* ---- Auto open when a new notification arrives ---- */
    function cancelAutoClose(state) {
        window.clearTimeout(state.autoCloseTimer);
        state.autoCloseTimer = null;
    }

    function startAutoClose(state) {
        cancelAutoClose(state);

        state.autoCloseTimer = window.setTimeout(function () {
            state.autoCloseTimer = null;
            state.autoOpened = false;
            closePanel(state);
        }, state.autoCloseMs);
    }


    /* ============================================================
       TIMER
       ============================================================ */
    function clearTimer(state) {
        if (state.timer) {
            window.clearTimeout(state.timer);
            state.timer = null;
        }
    }

    function schedulePoll(state, delay) {

        clearTimer(state);

        if (!state.pollingEnabled || document.hidden || state.busy) {
            return;
        }

        state.timer = window.setTimeout(
            function () {
                checkNew(state);
            },
            typeof delay === "number" ? delay : state.pollInterval
        );
    }

    function destroy(state) {
        clearTimer(state);
        delete instances[state.key];
    }


    /* ============================================================
       POLL: CHECK_NEW
       ============================================================ */
    function checkNew(state) {

        state.timer = null;

        if (!state.pollingEnabled || document.hidden || state.busy) {
            return;
        }

        /* Region removed from the page (e.g. dialog closed) */
        if (!document.body.contains(state.root)) {
            destroy(state);
            return;
        }

        state.busy = true;

        apex.server.plugin(
            state.ajaxId,
            {
                x01: "CHECK_NEW",
                x02: String(state.latestId)
            },
            {
                dataType: "json"
            }
        ).done(function (data) {

            state.busy = false;

            if (!data || data.success !== true) {
                schedulePoll(state);
                return;
            }

            const serverLatest = toNum(data.latestId, 0);
            const serverUnread = toNum(data.unreadCount, 0);

            /*
             * Anything different from what the page shows
             * (new order, deleted row, read in another tab)
             * -> reload the content from the server.
             */
            if (
                serverLatest !== state.latestId ||
                serverUnread !== state.unreadCount
            ) {
                reloadContent(state, serverLatest > state.latestId);
                return;
            }

            schedulePoll(state);

        }).fail(function (jqXHR, textStatus, errorThrown) {

            state.busy = false;

            console.error("Notification polling error:", textStatus, errorThrown);

            schedulePoll(state);
        });
    }


    /* ============================================================
       REFRESH: fetch new HTML and swap the inner block
       ============================================================ */
    function reloadContent(state, isNew) {

        clearTimer(state);

        if (state.busy) {
            return;
        }

        state.busy = true;

        apex.server.plugin(
            state.ajaxId,
            {
                x01: "REFRESH"
            },
            {
                dataType: "text"
            }
        ).done(function (html) {

            state.busy = false;

            applyContent(state, html, isNew);

            schedulePoll(state);

        }).fail(function (jqXHR, textStatus, errorThrown) {

            state.busy = false;

            console.error("Notification refresh error:", textStatus, errorThrown);

            schedulePoll(state);
        });
    }

    function applyContent(state, html, isNew) {

        const temp = document.createElement("div");
        temp.innerHTML = html;

        const newInner = temp.querySelector(".mg-noti-inner");

        if (!newInner) {
            console.error("Notification refresh returned unexpected content.");
            return;
        }

        const wasOpen   = state.isOpen;
        const oldList   = state.root.querySelector(".mg-noti-list");
        const scrollTop = oldList ? oldList.scrollTop : 0;

        if (state.inner) {
            state.inner.replaceWith(newInner);
        } else {
            state.root.appendChild(newInner);
        }

        cacheElements(state);

        state.isOpen = false;

        /* Keep the dropdown open (without re-playing the animation) */
        if (wasOpen) {

            openPanel(state, false);

            const newList = state.root.querySelector(".mg-noti-list");

            if (newList) {
                newList.scrollTop = scrollTop;
            }
        }

        /*
         * New notification:
         *  - panel closed  -> slide it open by itself, close after N seconds
         *  - opened by the system earlier -> restart the N seconds
         *  - opened by the user -> leave it open (no auto close)
         */
        if (isNew && state.autoOpenOnNew && state.panel) {

            if (!wasOpen) {
                state.autoOpened = true;
                openPanel(state, true);
                startAutoClose(state);
            } else if (state.autoOpened) {
                startAutoClose(state);
            }
        }

        /* Small "ring" animation when a new notification arrived */
        if (isNew && state.bell) {
            state.bell.classList.remove("mg-noti-ring");
            void state.bell.offsetWidth; // restart animation
            state.bell.classList.add("mg-noti-ring");
        }

        /* Hook for Dynamic Actions: Custom Event "mgnotificationsupdate" */
        $(state.root).trigger("mgnotificationsupdate", [{
            unreadCount: state.unreadCount,
            latestId: state.latestId,
            isNew: isNew === true
        }]);
    }


    /* ============================================================
       UPDATE COUNTS LOCALLY (after mark read)
       ============================================================ */
    function updateUnreadUI(state) {

        const count = toNum(state.unreadCount, 0);

        const badge = state.root.querySelector(".mg-noti-badge");

        if (badge) {
            if (count > 0) {
                badge.textContent = count > 99 ? "99+" : String(count);
            } else {
                badge.remove();
            }
        }

        const headerCount = state.root.querySelector(".mg-noti-header-count");

        if (headerCount) {
            headerCount.textContent = count + " unread";
        }

        if (count === 0) {
            const footer = state.root.querySelector(".mg-noti-footer");
            if (footer) {
                footer.remove();
            }
        }

        /* Keep the baseline in sync so the next poll doesn't reload */
        if (state.inner) {
            state.inner.dataset.unreadCount = String(count);
        }
    }

    function setItemRead(item) {

        item.classList.remove("is-unread");
        item.classList.add("is-read");

        const dot = item.querySelector(".mg-noti-unread-dot");

        if (dot) {
            dot.remove();
        }
    }


    /* Instantly replace the list with the "all caught up" message */
    function showEmptyState(state) {

        const list = state.root.querySelector(".mg-noti-list");

        if (!list) { return; }

        list.innerHTML = "";

        const box   = document.createElement("div");
        const icon  = document.createElement("div");
        const title = document.createElement("div");
        const text  = document.createElement("div");

        box.className   = "mg-noti-empty";
        icon.className  = "mg-noti-empty-icon";
        icon.innerHTML  = '<span class="fa fa-check"></span>';
        title.className = "mg-noti-empty-title";
        title.textContent = state.emptyMessage;
        text.className  = "mg-noti-empty-text";
        text.textContent = "You have no unread notifications.";

        box.appendChild(icon);
        box.appendChild(title);
        box.appendChild(text);
        list.appendChild(box);
        list.scrollTop = 0;
    }


    /* ============================================================
       MARK ONE READ
       ============================================================ */
    function markRead(state, item) {

        if (
            !state.markReadOnClick ||
            !item ||
            !item.classList.contains("is-unread") ||
            item.dataset.processing === "Y"
        ) {
            return;
        }

        item.dataset.processing = "Y";

        /* Last unread one: update the screen NOW, tell the server in background */
        const wasLast = state.unreadCount <= 1;

        if (wasLast) {
            setItemRead(item);
            state.unreadCount = 0;
            updateUnreadUI(state);
            showEmptyState(state);
        }

        apex.server.plugin(
            state.ajaxId,
            {
                x01: "MARK_READ",
                x02: item.dataset.notiId
            },
            {
                dataType: "json"
            }
        ).done(function (data) {

            item.dataset.processing = "N";

            if (!data || data.success !== true) {
                if (wasLast) { reloadContent(state, state.isOpen); }
                return;
            }

            const serverCount = toNum(data.unreadCount, 0);

            if (wasLast) {
                /* a new notification arrived meanwhile -> resync */
                if (serverCount > 0) {
                    state.unreadCount = serverCount;
                    reloadContent(state, true);
                }
                return;
            }

            setItemRead(item);
            state.unreadCount = serverCount;
            updateUnreadUI(state);

        }).fail(function () {

            item.dataset.processing = "N";

            if (wasLast) { reloadContent(state, state.isOpen); }
        });
    }


    /* ============================================================
       MARK ALL READ
       ============================================================ */
    function markAllRead(state) {

        apex.server.plugin(
            state.ajaxId,
            {
                x01: "MARK_ALL_READ"
            },
            {
                dataType: "json"
            }
        ).done(function (data) {

            if (!data || data.success !== true) {
                return;
            }

            state.root
                .querySelectorAll(".mg-noti-item.is-unread")
                .forEach(setItemRead);

            state.unreadCount = toNum(data.unreadCount, 0);

            updateUnreadUI(state);

            /*
             * Reload the panel from the server:
             *  - unread = 0 -> shows the "Empty Message" (all caught up)
             *  - unread > 0 -> something new arrived at the same moment
             */
            reloadContent(state, state.unreadCount > 0);

        }).fail(function (jqXHR, textStatus, errorThrown) {

            console.error("Mark all read error:", textStatus, errorThrown);
        });
    }


    /* ============================================================
       EVENTS (delegated on the root -> survive content swaps)
       ============================================================ */
    function bindEvents(state) {

        /* Mouse over the auto-opened panel: keep it open; leave: count 5s again */
        state.root.addEventListener("mouseenter", function () {
            if (state.autoOpened) {
                cancelAutoClose(state);
            }
        });

        state.root.addEventListener("mouseleave", function () {
            if (state.autoOpened && state.isOpen) {
                startAutoClose(state);
            }
        });

        state.root.addEventListener("click", function (event) {

            /* user is interacting -> no more auto close */
            state.autoOpened = false;
            cancelAutoClose(state);

            const bell = event.target.closest(".mg-noti-bell");

            if (bell) {
                event.preventDefault();
                togglePanel(state);
                return;
            }

            const markAll = event.target.closest(".mg-noti-mark-all");

            if (markAll) {
                event.preventDefault();
                markAllRead(state);
                return;
            }

            const item = event.target.closest(".mg-noti-item");

            if (item) {
                markRead(state, item);
            }
        });

        state.root.addEventListener("keydown", function (event) {

            if (event.key === "Escape" && state.isOpen) {
                closePanel(state);
                if (state.bell) {
                    state.bell.focus();
                }
                return;
            }

            const item = event.target.closest(".mg-noti-item");

            if (item && (event.key === "Enter" || event.key === " ")) {
                event.preventDefault();
                markRead(state, item);
            }
        });
    }


    /* ============================================================
       OPTIONAL: make "Refresh" Dynamic Action work on this region
       ============================================================ */
    function registerRegion(state) {

        const id  = state.regionId;
        const key = state.key;
        const el  = id ? document.getElementById(id) : null;

        if (!el) {
            return;
        }

        function doRefresh() {
            const s = instances[key];
            if (s) {
                reloadContent(s, false);
            }
        }

        try {
            if (
                apex.region &&
                typeof apex.region.create === "function" &&
                !(typeof apex.region.isRegion === "function" && apex.region.isRegion(id))
            ) {
                apex.region.create(id, {
                    type: "mgNotificationBell",
                    refresh: doRefresh
                });
            }
        } catch (e) {
            /* ignore - fallback below */
        }

        /* Fallback if APEX already created a default region interface */
        $(el).off("apexrefresh.mgNoti").on("apexrefresh.mgNoti", doRefresh);
    }


    /* ============================================================
       INITIALISE ONE INSTANCE
       ============================================================ */
    function initialise(root) {

        if (!root || root.dataset.mgInit === "Y") {
            return;
        }

        const key = root.dataset.instanceId;

        if (instances[key]) {
            destroy(instances[key]);
        }

        const state = {
            key: key,
            root: root,
            ajaxId: root.dataset.ajaxId,
            regionId: root.dataset.regionId,

            /* Attribute 8 */
            pollingEnabled: isYes(root.dataset.polling),

            /* Attribute 9 (seconds -> ms, min 5s) */
            pollInterval: Math.max(toNum(root.dataset.pollInterval, 10), 5) * 1000,

            /* Attribute 11 */
            markReadOnClick: isYes(root.dataset.markReadClick),

            /* Attribute 6 (Empty Message) */
            emptyMessage: root.dataset.emptyMessage || "You're all caught up!",

            /* Auto open the panel when a new notification arrives */
            autoOpenOnNew: true,
            autoCloseMs: 5000,
            autoOpened: false,
            autoCloseTimer: null,

            isOpen: false,
            timer: null,
            busy: false
        };

        cacheElements(state);

        if (!state.bell || !state.panel) {
            return;
        }

        root.dataset.mgInit = "Y";

        instances[key] = state;

        bindEvents(state);
        registerRegion(state);

        /* First check shortly after page load */
        schedulePoll(state, 2000);
    }

    function initialiseAll(container) {

        const scope = container || document;

        if (scope.classList && scope.classList.contains("mg-noti-plugin")) {
            initialise(scope);
        }

        if (typeof scope.querySelectorAll === "function") {
            scope.querySelectorAll(".mg-noti-plugin").forEach(initialise);
        }
    }


    /* ============================================================
       GLOBAL LISTENERS
       ============================================================ */
    $(function () {
        initialiseAll(document);
    });

    $(document).on("apexafterrefresh.mgNotifications", function (event) {
        initialiseAll(event.target);
    });

    /* Click outside closes the panel */
    document.addEventListener("click", function (event) {
        Object.values(instances).forEach(function (state) {
            const path = event.composedPath ? event.composedPath() : [];
            const inside = path.indexOf(state.root) !== -1 || state.root.contains(event.target);

            if (state && state.isOpen && !inside) {
                closePanel(state);
            }
        });
    });

    window.addEventListener("resize", function () {
        Object.values(instances).forEach(function (state) {
            if (state && state.isOpen) {
                positionPanel(state);
            }
        });
    });

    window.addEventListener("scroll", function () {
        Object.values(instances).forEach(function (state) {
            if (state && state.isOpen) {
                positionPanel(state);
            }
        });
    }, true);

    /* Pause while tab hidden, check quickly when user comes back */
    document.addEventListener("visibilitychange", function () {
        Object.values(instances).forEach(function (state) {

            if (!state) {
                return;
            }

            if (document.hidden) {
                clearTimer(state);
                return;
            }

            schedulePoll(state, 1000);
        });
    });

})(apex.jQuery);
