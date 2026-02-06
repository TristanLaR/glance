/**
 * GlanceBridge - Platform abstraction layer for Glance
 *
 * Abstracts Tauri IPC (Linux) vs WKWebView messageHandlers (macOS native)
 * so that index.html works identically on both platforms.
 */
(function () {
    'use strict';

    const PLATFORM_TAURI = 'tauri';
    const PLATFORM_WEBKIT = 'webkit';

    // Detect platform
    function detectPlatform() {
        if (window.__TAURI__) return PLATFORM_TAURI;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.glance) return PLATFORM_WEBKIT;
        // Fallback: check again after a tick (Tauri injects globals asynchronously)
        return null;
    }

    let platform = detectPlatform();

    // Pending promises for WebKit async responses (id -> {resolve, reject})
    const pending = new Map();
    let nextId = 1;

    // Event listeners: event name -> Set of callbacks
    const eventListeners = new Map();

    const GlanceBridge = {
        /**
         * Invoke a backend command.
         * @param {string} command - Command name (e.g. 'get_markdown_content')
         * @param {object} [args] - Command arguments
         * @returns {Promise<any>}
         */
        invoke(command, args) {
            if (!platform) platform = detectPlatform();

            if (platform === PLATFORM_TAURI) {
                return window.__TAURI__.core.invoke(command, args);
            }

            if (platform === PLATFORM_WEBKIT) {
                return new Promise((resolve, reject) => {
                    const id = nextId++;
                    pending.set(id, { resolve, reject });
                    window.webkit.messageHandlers.glance.postMessage({
                        id: id,
                        command: command,
                        args: args || {}
                    });
                });
            }

            return Promise.reject(new Error('GlanceBridge: no platform detected'));
        },

        /**
         * Convert a local file path to a URL the webview can load.
         * @param {string} path - Absolute file path
         * @returns {string} URL
         */
        convertFileSrc(path) {
            if (!platform) platform = detectPlatform();

            if (platform === PLATFORM_TAURI) {
                return window.__TAURI__.core.convertFileSrc(path);
            }

            if (platform === PLATFORM_WEBKIT) {
                // Use custom URL scheme registered in WKWebView
                return 'glance-asset://localhost' + encodeURI(path);
            }

            // Fallback: file:// protocol (may not work in all webviews)
            return 'file://' + path;
        },

        /**
         * Open a native file picker dialog for markdown files.
         * @returns {Promise<string|null>} Selected file path or null
         */
        async openFileDialog() {
            if (!platform) platform = detectPlatform();

            if (platform === PLATFORM_TAURI) {
                const { open } = window.__TAURI__.dialog;
                const selected = await open({
                    filters: [{
                        name: 'Markdown',
                        extensions: ['md', 'markdown']
                    }],
                    multiple: false
                });
                return (selected && typeof selected === 'string') ? selected : null;
            }

            if (platform === PLATFORM_WEBKIT) {
                // Ask Swift to show NSOpenPanel
                return this.invoke('open_file_dialog');
            }

            return null;
        },

        /**
         * Listen for an event from the backend.
         * @param {string} event - Event name (e.g. 'file-changed')
         * @param {function} callback - Callback function
         * @returns {Promise<function>} Unlisten function
         */
        async listen(event, callback) {
            if (!platform) platform = detectPlatform();

            if (platform === PLATFORM_TAURI) {
                return window.__TAURI__.event.listen(event, callback);
            }

            // WebKit: store callback locally, Swift will call _dispatch
            if (!eventListeners.has(event)) {
                eventListeners.set(event, new Set());
            }
            eventListeners.get(event).add(callback);

            // Return unlisten function
            return () => {
                const listeners = eventListeners.get(event);
                if (listeners) listeners.delete(callback);
            };
        },

        // --- Internal methods called by Swift ---

        /**
         * Called by Swift to resolve a pending invoke promise.
         * @param {number} id - Request ID
         * @param {any} data - Response data
         */
        _resolve(id, data) {
            const entry = pending.get(id);
            if (entry) {
                pending.delete(id);
                entry.resolve(data);
            }
        },

        /**
         * Called by Swift to reject a pending invoke promise.
         * @param {number} id - Request ID
         * @param {string} error - Error message
         */
        _reject(id, error) {
            const entry = pending.get(id);
            if (entry) {
                pending.delete(id);
                entry.reject(new Error(error));
            }
        },

        /**
         * Called by Swift to dispatch a backend event.
         * @param {string} event - Event name
         * @param {any} [payload] - Event payload
         */
        _dispatch(event, payload) {
            const listeners = eventListeners.get(event);
            if (listeners) {
                for (const cb of listeners) {
                    try {
                        cb({ event, payload });
                    } catch (e) {
                        console.error('GlanceBridge event listener error:', e);
                    }
                }
            }
        }
    };

    window.GlanceBridge = GlanceBridge;
})();
