/**
 * static/js/components/index.js
 *
 * Barrel: incluir sólo este archivo en base_2daE.html para cargar
 * todos los módulos de componentes.
 *
 * Uso en base_2daE.html (antes de </body>):
 *
 *   <script src="{{ url_for('static', filename='js/components/modals.js') }}"></script>
 *   <script src="{{ url_for('static', filename='js/components/alerts.js') }}"></script>
 *   <script src="{{ url_for('static', filename='js/components/dropdowns.js') }}"></script>
 *   <script src="{{ url_for('static', filename='js/components/loaders.js') }}"></script>
 *   <script src="{{ url_for('static', filename='js/components/tables.js') }}"></script>
 *   <script src="{{ url_for('static', filename='js/components/filters.js') }}"></script>
 *   <script src="{{ url_for('static', filename='js/components/tabs.js') }}"></script>
 *
 * ─────────────────────────────────────────────────────────────────────────
 * CADA MÓDULO es autónomo. Este archivo sólo documenta el orden recomendado
 * y las APIs disponibles. No hace nada por sí mismo.
 *
 * APIs expuestas:
 *
 *  modals.js
 *    openModal(id)
 *    closeModal(id)
 *    showConfirmModal(title, msg, onConfirm)
 *    closeConfirmModal()
 *    executeConfirmAction()
 *
 *  alerts.js
 *    Alert.show(container, message, type, {title, dismissible, autoDismissMs})
 *    Alert.toast(message, type, duration)
 *    Alert.dismiss(el)
 *    window.closeAlert(btn)   ← compat legacy
 *
 *  dropdowns.js
 *    Dropdown.open(el)
 *    Dropdown.close(el)
 *    Dropdown.toggle(el)
 *    Dropdown.init(el)
 *
 *  loaders.js
 *    Loader.show(containerEl, text?)
 *    Loader.hide(containerEl)
 *    Loader.showById(id)
 *    Loader.hideById(id)
 *    Loader.button(btnEl, loading, text?)
 *    Loader.fetchWithLoader(url, opts, containerEl, text?)
 *
 *  tables.js
 *    const ctrl = Tables.init({ tableId, searchId, filterSelectId,
 *                               filterDataKey, sortSelectId, colMap,
 *                               rowSelector, onFilter })
 *    ctrl.applyFilter()
 *    ctrl.applySort()
 *    ctrl.refresh()
 *
 *  filters.js
 *    Filters.init(scopeEl?)
 *    Filters.addPill(container, labelKey, labelValue, key, onRemove?)
 *    Filters.clearAll(pillsContainer)
 *    Filters.syncFromURL(scopeEl?)
 *    Filters.syncToURL(scopeEl?, replace?)
 *
 *  tabs.js
 *    Tabs.init(barEl)
 *    Tabs.activate(tabEl)
 *    Tabs.activateByIndex(barEl, index)
 *    Evento: 'md3:tab:change' → e.detail.{ tab, targetId }
 */
