'use strict';

// ============================================================
// 1. HELPERS GENERALES (mismos que festivos.js)
// ============================================================
function val(id)           { return document.getElementById(id)?.value ?? ''; }
function setVal(id, value) { const el = document.getElementById(id); if (el) el.value = value ?? ''; }
function setText(id, text) { const el = document.getElementById(id); if (el) el.textContent = text ?? ''; }
function show(id)          { document.getElementById(id)?.classList.remove('hidden'); }
function hide(id)          { document.getElementById(id)?.classList.add('hidden'); }

function showFieldError(spanId, mensaje, autoHideMs = 4000) {
    const el = document.getElementById(spanId);
    if (!el) return;
    el.textContent = mensaje;
    el.classList.add('visible');
    clearTimeout(el._hideTimer);
    el._hideTimer = setTimeout(() => {
        el.classList.remove('visible');
        setTimeout(() => { el.textContent = ''; }, 300);
    }, autoHideMs);
}

function clearAllFieldErrors(prefix) {
    document.querySelectorAll(`[id^="err-${prefix}-"]`).forEach(el => {
        clearTimeout(el._hideTimer);
        el.classList.remove('visible');
        el.textContent = '';
    });
}

function showToast(message, type = 'success') {
    const toast = document.getElementById('toast');
    const span  = document.getElementById('toast-message');
    if (!toast || !span) return;
    const text = message && message.trim() ? message : (type === 'success' ? 'Operación exitosa' : 'Ocurrió un error');
    span.textContent = text;
    toast.style.background = type === 'error' ? '#ef4444' : '#0f172a';
    toast.classList.remove('hidden');
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => toast.classList.add('hidden'), 3500);
}

// Envía un FormData al mismo PHP y maneja la respuesta JSON.
// Los errores por campo se pintan en sus <span class="field-error">.
async function enviarFormulario(formData, mensajeError, onSuccess) {
    try {
        const response = await fetch(window.location.href, { method: 'POST', body: formData });
        const text = await response.text();
        let result;
        try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }

        if (result.success) {
            showToast(result.message, 'success');
            if (typeof onSuccess === 'function') onSuccess();
            location.reload();
        } else if (result.errors && Object.keys(result.errors).length > 0) {
            Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
        } else {
            showToast(result.message || mensajeError, 'error');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    }
}

// ============================================================
// 1.1 CAMPO DE NOMBRE: MAYÚSCULAS + CONTADOR (máx. 15)
// ============================================================
function actualizarContador(input) {
    const id = input.dataset.contador;
    if (id) setText(id, `${input.value.length} / ${input.maxLength}`);
}

function initCamposNombre() {
    document.querySelectorAll('.input-mayus').forEach(input => {
        input.addEventListener('input', () => {
            const pos = input.selectionStart;
            input.value = input.value.toUpperCase();
            input.setSelectionRange(pos, pos);
            actualizarContador(input);
        });
    });
}

// Datos de una fila de la tabla (se leen de sus data-*)
function datosFila(fila) {
    return {
        id:     fila.dataset.id,
        nombre: fila.dataset.nombre,
        estado: fila.dataset.estado,
    };
}

// ============================================================
// 2. MODAL: NUEVO TIPO DE PAGO
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    const sel = document.getElementById('new-tipo-pago-id');
    if (sel && sel.options.length) sel.selectedIndex = 0;
    setVal('new-tipo-pago-nombre', '');
    actualizarContador(document.getElementById('new-tipo-pago-nombre'));
    show('modal-new-tipo-pago');
    setTimeout(() => document.getElementById('new-tipo-pago-nombre')?.focus(), 50);
}

function closeNewModal() { hide('modal-new-tipo-pago'); }

// ============================================================
// 3. MODAL: EDITAR TIPO DE PAGO
// ============================================================
function openEditModal(tipo) {
    clearAllFieldErrors('edit');
    setVal('edit-tipo-pago-id', tipo.id);
    setVal('edit-tipo-pago-id-ver', `#${tipo.id}`);
    setVal('edit-tipo-pago-nombre', tipo.nombre);
    actualizarContador(document.getElementById('edit-tipo-pago-nombre'));
    show('modal-edit-tipo-pago');
    setTimeout(() => document.getElementById('edit-tipo-pago-nombre')?.focus(), 50);
}

function closeEditModal() { hide('modal-edit-tipo-pago'); }

// ============================================================
// 4. FILTROS (BÚSQUEDA + ESTADO) + PAGINACIÓN
// ============================================================
let tiposPagoPage     = 1;
let tiposPagoPageSize = 25; // debe coincidir con el <option selected>
let tiposPagoEstado   = 'todos';

function filasTabla() {
    return Array.from(document.querySelectorAll('#tipos-pago-tbody tr:not(.empty-row)'));
}

function getFilteredRows() {
    const query = val('tipo-pago-search').toLowerCase().trim();
    return filasTabla().filter(fila => {
        const { id, nombre, estado } = datosFila(fila);
        const coincideTexto  = !query || nombre.toLowerCase().includes(query) || id === query.replace('#', '');
        const coincideEstado = tiposPagoEstado === 'todos' || estado === tiposPagoEstado;
        return coincideTexto && coincideEstado;
    });
}

function applyFilters() {
    tiposPagoPage = 1;
    renderPage();

    const hayFiltro = val('tipo-pago-search').trim() !== '' || tiposPagoEstado !== 'todos';
    const clearBtn  = document.getElementById('btn-clear-filters');
    if (clearBtn) clearBtn.style.display = hayFiltro ? 'flex' : 'none';
}

function setEstadoFiltro(estado) {
    tiposPagoEstado = estado;
    document.querySelectorAll('#tipo-pago-estado-filtro .filter-toggle').forEach(b => {
        b.classList.toggle('active', b.dataset.estado === estado);
    });
    applyFilters();
}

function clearFilters() {
    setVal('tipo-pago-search', '');
    setEstadoFiltro('todos');
}

function renderPage() {
    const coinciden = getFilteredRows();
    filasTabla().forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = tiposPagoPageSize === 'all';
    const size         = esTodos ? total : tiposPagoPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    tiposPagoPage = Math.min(Math.max(tiposPagoPage, 1), totalPaginas);

    const start = esTodos ? 0 : (tiposPagoPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    setText('tipos-pago-count', `${total} resultado${total !== 1 ? 's' : ''}`);
    setText('tipos-pago-range', total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`);

    const btnPrev = document.getElementById('tipos-pago-prev');
    const btnNext = document.getElementById('tipos-pago-next');
    if (btnPrev) btnPrev.disabled = tiposPagoPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || tiposPagoPage >= totalPaginas;
}

function initPagination() {
    document.getElementById('tipos-pago-page-size')?.addEventListener('change', function() {
        tiposPagoPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        tiposPagoPage = 1;
        renderPage();
    });
    document.getElementById('tipos-pago-prev')?.addEventListener('click', () => { tiposPagoPage--; renderPage(); });
    document.getElementById('tipos-pago-next')?.addEventListener('click', () => { tiposPagoPage++; renderPage(); });
}

// ---- ORDENAMIENTO ASC / DESC ----
let sortKey = null;
let sortDir = 'asc';

function sortRows(key, type) {
    const tbody = document.getElementById('tipos-pago-tbody');
    const filas = filasTabla();
    if (!tbody || filas.length === 0) return;

    sortDir = (sortKey === key && sortDir === 'asc') ? 'desc' : 'asc';
    sortKey = key;

    const getValor = fila => {
        const celda = fila.cells[Number(key)];
        const crudo = celda?.dataset.sort;
        const base  = crudo !== undefined ? crudo : (celda?.textContent.trim() ?? '');
        return type === 'number' ? (parseFloat(base) || 0) : base.toLowerCase();
    };

    filas.sort((a, b) => {
        const va = getValor(a), vb = getValor(b);
        const cmp = type === 'number' ? (va - vb) : va.localeCompare(vb, 'es');
        return sortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-tipos-pago .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${sortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    tiposPagoPage = 1;
    renderPage();
}

function initSorting() {
    document.querySelectorAll('#mod-tipos-pago .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortRows(th.dataset.sortKey, th.dataset.sortType));
    });
}

// ---- ALTO DINÁMICO DE LA TABLA (evita el doble scroll) ----
function ajustarAlturaTabla() {
    const scrollBox = document.getElementById('tipos-pago-table-scroll');
    if (!scrollBox) return;
    const footer = document.querySelector('#mod-tipos-pago .table-footer');
    const top = scrollBox.getBoundingClientRect().top;
    const alturaFooter = footer ? footer.offsetHeight : 0;

    let margenInferior = 16;
    const contentCard = scrollBox.closest('.content-card') || document.querySelector('.content-card');
    if (contentCard) {
        const cs = getComputedStyle(contentCard);
        margenInferior += (parseFloat(cs.paddingBottom) || 0) + (parseFloat(cs.marginBottom) || 0);
    }

    const disponible = window.innerHeight - top - alturaFooter - margenInferior;
    scrollBox.style.maxHeight = Math.max(220, disponible) + 'px';
}

// ============================================================
// 5. CONFIRMAR ACTIVAR / INACTIVAR (borrado lógico)
// ============================================================
let _confirmEstadoAction = null;

function abrirConfirmEstado(tipo, accion) {
    const inactivar = accion === 'inactivar';
    const icon = document.getElementById('confirm-estado-icon');
    const ok   = document.getElementById('confirm-estado-ok-btn');

    setText('confirm-estado-title', `${inactivar ? 'Inactivar' : 'Activar'} "${tipo.nombre}"`);
    setText('confirm-estado-body', inactivar
        ? `¿Desea inactivar el tipo de pago "${tipo.nombre}"? Dejará de estar disponible, pero se puede volver a activar.`
        : `¿Desea activar de nuevo el tipo de pago "${tipo.nombre}"?`);

    if (icon) {
        icon.classList.toggle('activar', !inactivar);
        icon.innerHTML = inactivar
            ? '<i class="fas fa-exclamation-triangle"></i>'
            : '<i class="fas fa-check-circle"></i>';
    }
    if (ok) {
        ok.textContent = inactivar ? 'Sí, inactivar' : 'Sí, activar';
        ok.classList.toggle('btn-eliminar', inactivar);
        ok.classList.toggle('btn-activar', !inactivar);
    }

    _confirmEstadoAction = () => ejecutarCambioEstado(tipo.id, accion);
    show('modal-confirm-estado');
}

function cerrarConfirmEstado() {
    hide('modal-confirm-estado');
    _confirmEstadoAction = null;
}

function ejecutarCambioEstado(id, accion) {
    const formData = new FormData();
    formData.append('btn_estado', '1');
    formData.append('hid_est_id', id);
    formData.append('hid_est_accion', accion);
    enviarFormulario(formData, 'Error al cambiar el estado');
}

// ============================================================
// 6. INICIALIZACIÓN GENERAL
// ============================================================
document.addEventListener('DOMContentLoaded', initTiposPagoModule);

function initTiposPagoModule() {
    document.getElementById('btn-add-tipo-pago')?.addEventListener('click', openNewModal);

    initCamposNombre();

    // ---------- FILTROS ----------
    document.getElementById('tipo-pago-search')?.addEventListener('input', applyFilters);
    document.querySelectorAll('#tipo-pago-estado-filtro .filter-toggle').forEach(btn => {
        btn.addEventListener('click', () => setEstadoFiltro(btn.dataset.estado));
    });
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // ---------- TABLA ----------
    initPagination();
    initSorting();
    renderPage();
    ajustarAlturaTabla();
    window.addEventListener('resize', ajustarAlturaTabla);

    // Botones de cada fila (delegación: no hay onclick inline)
    document.getElementById('tipos-pago-tbody')?.addEventListener('click', e => {
        const btn  = e.target.closest('button');
        const fila = e.target.closest('tr[data-id]');
        if (!btn || !fila) return;
        const tipo = datosFila(fila);
        if (btn.classList.contains('btn-editar')) openEditModal(tipo);
        if (btn.classList.contains('btn-estado')) abrirConfirmEstado(tipo, btn.dataset.accion);
    });

    // ---------- CERRAR MODALES (solo con X o Cancelar) ----------
    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));
    document.querySelectorAll('.btn-close-edit-modal, .btn-cancel-edit-modal')
        .forEach(btn => btn.addEventListener('click', closeEditModal));

    // ---------- CONFIRMAR ESTADO ----------
    document.getElementById('confirm-estado-cancel-btn')?.addEventListener('click', cerrarConfirmEstado);
    document.getElementById('confirm-estado-ok-btn')?.addEventListener('click', () => {
        const accion = _confirmEstadoAction;
        cerrarConfirmEstado();
        if (typeof accion === 'function') accion();
    });

    // ---------- GUARDAR ----------
    document.getElementById('new-btn-save')?.addEventListener('click', () => {
        clearAllFieldErrors('new');
        const formData = new FormData(document.getElementById('new-tipo-pago-form'));
        enviarFormulario(formData, 'Error al guardar', closeNewModal);
    });

    document.getElementById('edit-btn-save')?.addEventListener('click', () => {
        clearAllFieldErrors('edit');
        const formData = new FormData(document.getElementById('edit-tipo-pago-form'));
        enviarFormulario(formData, 'Error al actualizar', closeEditModal);
    });

    // Enter dentro del nombre = guardar (en vez de recargar la página)
    document.getElementById('new-tipo-pago-form')?.addEventListener('submit', e => {
        e.preventDefault(); document.getElementById('new-btn-save')?.click();
    });
    document.getElementById('edit-tipo-pago-form')?.addEventListener('submit', e => {
        e.preventDefault(); document.getElementById('edit-btn-save')?.click();
    });
}
