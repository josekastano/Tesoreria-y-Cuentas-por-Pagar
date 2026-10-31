'use strict';

// ============================================================
// 1. HELPERS GENERALES (mismos que bancos.js)
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

// Si el servidor no devuelve JSON (p. ej. un error fatal de PHP), muestra el
// comienzo de lo que llegó, sin etiquetas HTML, para saber qué pasó.
function resumenRespuesta(text) {
    const div = document.createElement('div');
    div.innerHTML = text || '';
    const plano = (div.textContent || '').replace(/\s+/g, ' ').trim();
    if (!plano) return '(respuesta vacía; revise el log de errores de PHP)';
    const i = plano.search(/(fatal|error|warning|notice|uncaught)/i);
    return (i >= 0 ? plano.slice(i) : plano).slice(0, 220);
}

// Envía un FormData al mismo PHP y devuelve el JSON (o un error genérico)
async function enviarPost(formData) {
    const response = await fetch(window.location.href, { method: 'POST', body: formData });
    const text = await response.text();
    let result;
    try { result = JSON.parse(text); }
    catch (e) {
        console.error('Respuesta del servidor que no es JSON:', text);
        return { success: false, message: 'Respuesta inválida del servidor: ' + resumenRespuesta(text) };
    }
    if (result.debug_salida_previa) console.warn('Salida de PHP antes del JSON:', result.debug_salida_previa);
    return result;
}

// ============================================================
// 2. MODAL: NUEVO CÓDIGO
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    setVal('new-id-banco', '');
    setVal('new-id-codigo', '');
    setVal('new-des-motivo', '');
    show('modal-new-codigo');
}

function closeNewModal() {
    hide('modal-new-codigo');
}

// ============================================================
// 3. MODAL: EDITAR CÓDIGO
// ============================================================
// Solo se edita la descripción. Se conserva ind_borrado para que editar un
// código dado de baja no lo reactive (para eso está el botón Reactivar).
function openEditModal(codigo) {
    clearAllFieldErrors('edit');
    setVal('edit-id-codigo-hid',   codigo.id_codigo);
    setVal('edit-id-banco-hid',    codigo.id_banco);
    setVal('edit-ind-borrado-hid', codigo.ind_borrado ? 'true' : 'false');
    setVal('edit-codigo-display',  codigo.id_codigo);
    setVal('edit-banco-display',   codigo.nom_banco);
    setVal('edit-des-motivo',      codigo.des_motivo);
    show('modal-edit-codigo');
}

function closeEditModal() {
    hide('modal-edit-codigo');
}

// ============================================================
// 4. FILTROS + PAGINACIÓN + ORDENAMIENTO (mismo sistema que Proveedores)
// ============================================================

// ---- ESTADO DE PAGINACIÓN ----
let codigosPage     = 1;
let codigosPageSize = 25; // debe coincidir con el <option selected> de #codigos-page-size

function getEstadoActivo() {
    return document.querySelector('#mod-codigos .filter-toggle.active')?.dataset.filter ?? 'all';
}

// Filas que pasan la búsqueda, el banco y el estado (sin tener en cuenta la página)
function getFilteredCodigoRows() {
    const query  = val('codigo-search').toLowerCase().trim();
    const banco  = val('codigo-banco-filter');
    const estado = getEstadoActivo();
    const filas  = Array.from(document.querySelectorAll('#codigos-tbody tr:not(.empty-row)'));
    return filas.filter(fila => {
        const texto = [0, 1, 2].map(i => (fila.children[i]?.textContent ?? '').toLowerCase()).join(' ');
        const pasaTexto  = !query || texto.includes(query);
        const pasaBanco  = !banco || fila.dataset.banco === banco;
        const pasaEstado = estado === 'all' || fila.dataset.estado === estado;
        return pasaTexto && pasaBanco && pasaEstado;
    });
}

// Aplica los filtros y vuelve a la primera página.
// "Limpiar" aparece cuando algo difiere de la vista por defecto (Activos, todos los bancos).
function applyFilters() {
    codigosPage = 1;
    renderCodigosPage();

    const hayFiltro = val('codigo-search').trim() || val('codigo-banco-filter') || getEstadoActivo() !== 'activo';
    const clearBtn  = document.getElementById('btn-clear-filters');
    if (clearBtn) clearBtn.style.display = hayFiltro ? 'flex' : 'none';
}

function clearFilters() {
    setVal('codigo-search', '');
    setVal('codigo-banco-filter', '');
    document.querySelectorAll('#mod-codigos .filter-toggle').forEach(btn => btn.classList.remove('active'));
    document.querySelector('#mod-codigos .filter-toggle[data-filter="activo"]')?.classList.add('active');
    applyFilters();
}

// Muestra solo las filas que pasan el filtro Y caen en la página actual
function renderCodigosPage() {
    const todas     = Array.from(document.querySelectorAll('#codigos-tbody tr:not(.empty-row)'));
    const coinciden = getFilteredCodigoRows();
    todas.forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = codigosPageSize === 'all';
    const size         = esTodos ? total : codigosPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    if (codigosPage > totalPaginas) codigosPage = totalPaginas;
    if (codigosPage < 1) codigosPage = 1;

    const start = esTodos ? 0 : (codigosPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    setText('codigos-count', `${total} resultado${total !== 1 ? 's' : ''}`);

    const rangeEl = document.getElementById('codigos-range');
    if (rangeEl) {
        rangeEl.textContent = total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`;
    }

    const btnPrev = document.getElementById('codigos-prev');
    const btnNext = document.getElementById('codigos-next');
    if (btnPrev) btnPrev.disabled = codigosPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || codigosPage >= totalPaginas;
}

function initCodigosPagination() {
    document.getElementById('codigos-page-size')?.addEventListener('change', function() {
        codigosPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        codigosPage = 1;
        renderCodigosPage();
    });
    document.getElementById('codigos-prev')?.addEventListener('click', () => {
        codigosPage--;
        renderCodigosPage();
    });
    document.getElementById('codigos-next')?.addEventListener('click', () => {
        codigosPage++;
        renderCodigosPage();
    });
}

// ---- ORDENAMIENTO ASC / DESC ----
// El código se compara con "numeric" (R2 < R10).
let codigosSortKey = null; // índice de columna, coincide con data-sort-key del <th>
let codigosSortDir = 'asc';

function sortCodigoRows(key, type) {
    const tbody = document.getElementById('codigos-tbody');
    if (!tbody) return;
    const filas = Array.from(tbody.querySelectorAll('tr:not(.empty-row)'));
    if (filas.length === 0) return;

    codigosSortDir = (codigosSortKey === key && codigosSortDir === 'asc') ? 'desc' : 'asc';
    codigosSortKey = key;

    const getValor = fila => {
        const celda = fila.cells[Number(key)];
        const crudo = celda?.dataset.sort;
        const base  = crudo !== undefined ? crudo : (celda?.textContent.trim() ?? '');
        return type === 'number' ? (parseFloat(base) || 0) : base.toLowerCase();
    };

    filas.sort((a, b) => {
        const va  = getValor(a);
        const vb  = getValor(b);
        const cmp = type === 'number' ? (va - vb) : va.localeCompare(vb, 'es', { numeric: true });
        return codigosSortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-codigos .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${codigosSortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    codigosPage = 1;
    renderCodigosPage();
}

function initCodigosSorting() {
    document.querySelectorAll('#mod-codigos .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortCodigoRows(th.dataset.sortKey, th.dataset.sortType));
    });
}

// ---- ALTO DINÁMICO DE LA TABLA (evita el doble scroll) ----
function ajustarAlturaTablaCodigos() {
    const scrollBox = document.getElementById('codigos-table-scroll');
    if (!scrollBox) return;
    const footer = document.querySelector('#mod-codigos .table-footer');
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
// 5. DAR DE BAJA / REACTIVAR (borrado lógico)
// ============================================================
// Dar de baja: el código deja de ofrecerse al registrar la respuesta del
// banco, pero los pagos que ya lo usan lo conservan.
async function enviarAccionCodigo(accion, codigo, mensajeError) {
    const formData = new FormData();
    formData.append(accion, '1');
    formData.append('hid_id_codigo',  codigo.id_codigo);
    formData.append('hid_id_banco',   codigo.id_banco);
    formData.append('hid_des_motivo', codigo.des_motivo);

    try {
        const result = await enviarPost(formData);
        if (result.success) {
            showToast(result.message, 'success');
            location.reload();
        } else {
            showToast(result.message || mensajeError, 'error');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    }
}

// ---- MODAL DE CONFIRMACIÓN (estilo módulo Compras) ----
let _confirmAction = null;

function abrirConfirmEliminar(titulo, mensaje, accion) {
    setText('confirm-eliminar-title', titulo);
    setText('confirm-eliminar-body', mensaje);
    _confirmAction = accion;
    show('modal-confirm-eliminar');
}

function cerrarConfirmEliminar() {
    hide('modal-confirm-eliminar');
    _confirmAction = null;
}

function darDeBajaCodigo(codigo) {
    abrirConfirmEliminar(
        `Dar de baja el código "${codigo.id_codigo}"`,
        `¿Desea dar de baja el código "${codigo.id_codigo}" de ${codigo.nom_banco}? Dejará de ofrecerse al registrar la respuesta del banco, pero los pagos que ya lo usan lo conservan.`,
        () => enviarAccionCodigo('btn_eliminar', codigo, 'Error al dar de baja el código')
    );
}

function reactivarCodigo(codigo) {
    enviarAccionCodigo('btn_reactivar', codigo, 'Error al reactivar el código');
}

// ============================================================
// 6. INICIALIZACIÓN GENERAL
// ============================================================
document.addEventListener('DOMContentLoaded', function() {
    initCodigosModule();
});

function initCodigosModule() {
    document.getElementById('btn-add-codigo')?.addEventListener('click', openNewModal);

    document.getElementById('codigo-search')?.addEventListener('input', applyFilters);
    document.getElementById('codigo-banco-filter')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    document.querySelectorAll('#mod-codigos .filter-toggle').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('#mod-codigos .filter-toggle').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            applyFilters();
        });
    });

    // ---------- BOTONES DE CADA FILA (editar / dar de baja / reactivar) ----------
    // Los datos van en data-codigo (JSON), así no hay que escapar comillas en un onclick.
    document.getElementById('codigos-tbody')?.addEventListener('click', function(e) {
        const btn = e.target.closest('button[data-action]');
        if (!btn) return;
        let codigo;
        try { codigo = JSON.parse(btn.dataset.codigo); } catch (err) { return; }
        if (btn.dataset.action === 'editar')    openEditModal(codigo);
        if (btn.dataset.action === 'eliminar')  darDeBajaCodigo(codigo);
        if (btn.dataset.action === 'reactivar') reactivarCodigo(codigo);
    });

    // ---------- PAGINACIÓN Y ORDENAMIENTO ----------
    initCodigosPagination();
    initCodigosSorting();
    renderCodigosPage();
    ajustarAlturaTablaCodigos();
    window.addEventListener('resize', ajustarAlturaTablaCodigos);

    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));
    document.querySelectorAll('.btn-close-edit-modal, .btn-cancel-edit-modal')
        .forEach(btn => btn.addEventListener('click', closeEditModal));

    // ---------- MODAL: CONFIRMAR ----------
    document.getElementById('confirm-eliminar-cancel-btn')?.addEventListener('click', cerrarConfirmEliminar);
    document.getElementById('confirm-eliminar-ok-btn')?.addEventListener('click', () => {
        const accion = _confirmAction;
        cerrarConfirmEliminar();
        if (typeof accion === 'function') accion();
    });

    // Los modales NO se cierran al hacer clic por fuera (en el fondo oscuro):
    // así no se pierde lo que se lleva escrito en un formulario por un clic
    // accidental. Se cierran solo con la X o "Cancelar".

    // ---------- SUBMIT: NUEVO / EDITAR ----------
    const guardar = (formId, prefijo, cerrar, mensajeError) => async function() {
        clearAllFieldErrors(prefijo);
        try {
            const result = await enviarPost(new FormData(document.getElementById(formId)));
            if (result.success) {
                showToast(result.message, 'success');
                cerrar();
                location.reload();
            } else if (result.errors && Object.keys(result.errors).length > 0) {
                Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
            } else {
                showToast(result.message || mensajeError, 'error');
            }
        } catch (err) {
            showToast('Error de conexión', 'error');
        }
    };

    document.getElementById('new-btn-save')?.addEventListener('click',
        guardar('new-codigo-form', 'new', closeNewModal, 'Error al guardar'));
    document.getElementById('edit-btn-save')?.addEventListener('click',
        guardar('edit-codigo-form', 'edit', closeEditModal, 'Error al actualizar'));
}
