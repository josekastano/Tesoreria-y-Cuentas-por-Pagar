'use strict';

// ============================================================
// 1. HELPERS GENERALES
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

function formatCurrency(n) { return '$' + Number(n || 0).toLocaleString('es-CO'); }

// Fecha de hoy en 'YYYY-MM-DD' según la hora local (no UTC)
function fechaHoyLocal() {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function formatDate(isoStr) {
    if (!isoStr) return '—';
    const [y, m, d] = isoStr.split('-');
    return `${d}/${m}/${y}`;
}

function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

const ESTADOS_MOVIMIENTO = { 1: 'Pendiente', 2: 'Aprobado', 3: 'Reembolsado' };

// La BD puede devolver el boolean como true/false o 't'/'f'; se aceptan todas las variantes.
function cajaEstaActiva(caja) {
    const v = caja?.ind_estado_caja_m;
    return v === true || v === 't' || v === 'true' || v === 1 || v === '1';
}

// ============================================================
// 2. MODAL: NUEVA CAJA
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    setVal('new-nom-caja', '');
    setVal('new-monto-asignado', '');
    show('modal-new-caja');
}

function closeNewModal() {
    hide('modal-new-caja');
}

// ============================================================
// 3. MODAL: EDITAR NOMBRE DE CAJA
// ============================================================
function openEditModal(caja) {
    clearAllFieldErrors('edit');
    setVal('edit-caja-id', caja.id_caja_menor);
    setVal('edit-nom-caja', caja.nom_caja_menor);
    setVal('edit-monto-display', formatCurrency(caja.monto_asignado));
    show('modal-edit-caja');
}

function closeEditModal() {
    hide('modal-edit-caja');
}

window.openEditModal = openEditModal;

// ============================================================
// 4. MODAL: DETALLE DE CAJA (con movimientos)
// ============================================================
let cajaActualDetalle = null;

function openDetailModal(caja) {
    cajaActualDetalle = caja;
    const activa = cajaEstaActiva(caja);

    setText('detail-title', caja.nom_caja_menor);
    setText('detail-subtitle', `#${caja.id_caja_menor} — ${activa ? 'Activa' : 'Cerrada'}`);
    setVal('mov-id-caja', caja.id_caja_menor);

    const pctDisp = caja.monto_asignado > 0
        ? Math.round((caja.monto_disponible / caja.monto_asignado) * 100)
        : 0;

    const content = document.getElementById('detail-content');
    content.innerHTML = `
        <div class="detail-grid">
            <div class="detail-item"><span class="detail-label">Monto Asignado</span><span class="detail-value">${formatCurrency(caja.monto_asignado)}</span></div>
            <div class="detail-item"><span class="detail-label">Monto Disponible</span><span class="detail-value">${formatCurrency(caja.monto_disponible)} (${pctDisp}%)</span></div>
            <div class="detail-item"><span class="detail-label">Fecha Apertura</span><span class="detail-value">${formatDate(caja.fecha_apertura)}</span></div>
            <div class="detail-item"><span class="detail-label">Fecha Cierre</span><span class="detail-value">${formatDate(caja.fecha_cierre)}</span></div>
        </div>
    `;

    clearAllFieldErrors('mov');
    setVal('mov-concepto', '');
    setVal('mov-valor', '');
    setVal('mov-fecha', fechaHoyLocal());
    document.getElementById('mov-fecha')?.setAttribute('min', fechaHoyLocal());

    // Caja cerrada: se oculta el formulario de nuevo movimiento y se muestra el aviso
    if (activa) {
        show('mov-form-section');
        hide('mov-caja-cerrada-aviso');
    } else {
        hide('mov-form-section');
        show('mov-caja-cerrada-aviso');
    }

    // Botón "Cerrar Caja": solo visible/activo si la caja sigue abierta
    const btnCerrarCaja = document.getElementById('detail-btn-cerrar-caja');
    if (btnCerrarCaja) {
        if (activa) {
            btnCerrarCaja.classList.remove('hidden');
            btnCerrarCaja.onclick = () => cerrarCajaMenor(caja);
        } else {
            btnCerrarCaja.classList.add('hidden');
            btnCerrarCaja.onclick = null;
        }
    }

    show('modal-detail');
    loadMovimientos(caja.id_caja_menor);
}

function closeDetailModal() {
    hide('modal-detail');
    cajaActualDetalle = null;
}

window.openDetailModal = openDetailModal;

function loadMovimientos(idCajaMenor) {
    const movList = document.getElementById('movimientos-list');
    if (movList) movList.innerHTML = '<div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>Cargando...</p></div>';

    const formData = new FormData();
    formData.append('btn_ver_movimientos', '1');
    formData.append('hid_id_caja_menor', idCajaMenor);

    fetch(window.location.href, { method: 'POST', body: formData })
        .then(res => res.text())
        .then(text => {
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false }; }
            if (!movList) return;

            if (result.success && result.movimientos && result.movimientos.length > 0) {
                const soloLectura = !cajaEstaActiva(cajaActualDetalle);
                movList.innerHTML = result.movimientos.map(m => {
                    const estado = parseInt(m.ind_estado, 10);
                    // Bloqueado si la caja está cerrada o el movimiento ya fue reembolsado (estado final).
                    // Los estados anteriores al actual se deshabilitan: la BD no permite retroceder.
                    const bloqueado = soloLectura || estado === 3;
                    return `
                        <div class="mov-row">
                            <div class="mov-info">
                                <span class="mov-concepto">${escapeHtml(m.concepto)}</span>
                                <span class="mov-fecha">${formatDate(m.fecha_movimiento)}</span>
                            </div>
                            <span class="mov-valor">${formatCurrency(m.val_movimiento)}</span>
                            <select class="form-select mov-estado-select" data-id-caja="${m.id_caja_menor}" data-id-mov="${m.id_movimiento}" ${bloqueado ? 'disabled' : ''}>
                                <option value="1" ${estado === 1 ? 'selected' : ''} ${estado > 1 ? 'disabled' : ''}>Pendiente</option>
                                <option value="2" ${estado === 2 ? 'selected' : ''} ${estado > 2 ? 'disabled' : ''}>Aprobado</option>
                                <option value="3" ${estado === 3 ? 'selected' : ''}>Reembolsado</option>
                            </select>
                        </div>
                    `;
                }).join('');

                movList.querySelectorAll('.mov-estado-select').forEach(sel => {
                    sel.addEventListener('change', onCambiarEstadoMovimiento);
                });
            } else {
                movList.innerHTML = '<p style="font-size:12px;color:#94a3b8;text-align:center;padding:12px">No hay movimientos registrados en esta caja.</p>';
            }
        })
        .catch(() => {
            if (movList) movList.innerHTML = '<p style="font-size:12px;color:#ef4444;text-align:center;padding:12px">Error al cargar los movimientos.</p>';
        });
}

// ============================================================
// 4a. MODAL DE CONFIRMACIÓN DE ACCIÓN (estilo módulo Compras)
// ============================================================
let _confirmAccionOnAceptar  = null;
let _confirmAccionOnCancelar = null;

function abrirConfirmAccion(titulo, mensaje, opciones = {}) {
    const { textoOk = 'Confirmar', onAceptar = null, onCancelar = null } = opciones;
    setText('confirm-accion-title', titulo);
    setText('confirm-accion-body', mensaje);
    setText('confirm-accion-ok-btn', textoOk);
    _confirmAccionOnAceptar  = onAceptar;
    _confirmAccionOnCancelar = onCancelar;
    show('modal-confirm-accion');
}

function _resolverConfirmAccion(aceptado) {
    const onAceptar  = _confirmAccionOnAceptar;
    const onCancelar = _confirmAccionOnCancelar;
    hide('modal-confirm-accion');
    _confirmAccionOnAceptar  = null;
    _confirmAccionOnCancelar = null;
    if (aceptado && typeof onAceptar === 'function') onAceptar();
    if (!aceptado && typeof onCancelar === 'function') onCancelar();
}

function onCambiarEstadoMovimiento(e) {
    const sel         = e.target;
    const idCaja      = sel.dataset.idCaja;
    const idMov       = sel.dataset.idMov;
    const nuevoEstado = sel.value;
    const estadoTexto = ESTADOS_MOVIMIENTO[nuevoEstado];

    if (!cajaEstaActiva(cajaActualDetalle)) {
        showToast('La caja está cerrada; sus movimientos no pueden modificarse.', 'error');
        loadMovimientos(idCaja);
        return;
    }

    if (nuevoEstado === '3') {
        abrirConfirmAccion(
            'Confirmar reembolso',
            'Este movimiento se marcará como reembolsado a la caja. El monto disponible se incrementará nuevamente.',
            {
                textoOk: 'Sí, reembolsar',
                onAceptar:  () => ejecutarCambioEstadoMovimiento(idCaja, idMov, nuevoEstado, estadoTexto),
                onCancelar: () => loadMovimientos(idCaja)
            }
        );
        return;
    }

    ejecutarCambioEstadoMovimiento(idCaja, idMov, nuevoEstado, estadoTexto);
}

async function ejecutarCambioEstadoMovimiento(idCaja, idMov, nuevoEstado, estadoTexto) {
    const formData = new FormData();
    formData.append('btn_cambiar_estado', '1');
    formData.append('hid_estado_id_caja', idCaja);
    formData.append('hid_estado_id_mov', idMov);
    formData.append('sel_nuevo_estado', nuevoEstado);

    try {
        const response = await fetch(window.location.href, { method: 'POST', body: formData });
        const text = await response.text();
        let result;
        try { result = JSON.parse(text); } catch (err) { result = { success: false, message: 'Respuesta inválida' }; }

        if (result.success) {
            showToast(`Movimiento marcado como ${estadoTexto}.`, 'success');
            location.reload();
        } else {
            showToast(result.message || 'Error al actualizar el estado', 'error');
            loadMovimientos(idCaja);
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    }
}

// ============================================================
// 4b. CERRAR CAJA MENOR
// ============================================================
function cerrarCajaMenor(caja) {
    abrirConfirmAccion(
        `Cerrar "${caja.nom_caja_menor}"`,
        'La caja pasará a estado Cerrada y esta acción no se puede deshacer desde aquí.',
        {
            textoOk: 'Sí, cerrar caja',
            onAceptar: () => ejecutarCerrarCajaMenor(caja)
        }
    );
}

async function ejecutarCerrarCajaMenor(caja) {
    const formData = new FormData();
    formData.append('btn_cerrar_caja', '1');
    formData.append('hid_id_caja_menor', caja.id_caja_menor);

    try {
        const response = await fetch(window.location.href, { method: 'POST', body: formData });
        const text = await response.text();
        let result;
        try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }

        if (result.success) {
            showToast(result.message, 'success');
            closeDetailModal();
            location.reload();
        } else {
            showToast(result.message || 'Error al cerrar la caja', 'error');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    }
}

window.cerrarCajaMenor = cerrarCajaMenor;

// ============================================================
// 5. FILTROS + PAGINACIÓN + ORDENAMIENTO (mismo sistema que Proveedores)
// ============================================================

// ---- ESTADO DE PAGINACIÓN ----
let cajasPage     = 1;
let cajasPageSize = 25; // debe coincidir con el <option selected> de #cajas-page-size

// Filas que pasan la búsqueda y el filtro Todas/Activas/Cerradas (sin tener en cuenta la página)
function getFilteredCajaRows() {
    const query  = val('caja-search').toLowerCase().trim();
    const active = document.querySelector('#mod-caja-menor .filter-toggle.active')?.dataset.filter ?? 'all';
    const filas  = Array.from(document.querySelectorAll('#cajas-tbody tr:not(.empty-row)'));
    return filas.filter(fila => {
        const nombre = fila.children[0]?.textContent.toLowerCase() ?? '';
        const pasaTexto  = !query || nombre.includes(query);
        const pasaEstado = active === 'all' || fila.dataset.estado === active;
        return pasaTexto && pasaEstado;
    });
}

// Aplica búsqueda/estado y vuelve a la primera página
function applyFilters() {
    cajasPage = 1;
    renderCajasPage();

    const query    = val('caja-search').trim();
    const active   = document.querySelector('#mod-caja-menor .filter-toggle.active')?.dataset.filter ?? 'all';
    const clearBtn = document.getElementById('btn-clear-filters');
    if (clearBtn) clearBtn.style.display = (query || active !== 'all') ? 'flex' : 'none';
}

function clearFilters() {
    setVal('caja-search', '');
    document.querySelectorAll('.filter-toggle').forEach(btn => btn.classList.remove('active'));
    document.querySelector('.filter-toggle[data-filter="all"]')?.classList.add('active');
    applyFilters();
}

// Muestra solo las filas que pasan el filtro Y caen en la página actual
function renderCajasPage() {
    const todas     = Array.from(document.querySelectorAll('#cajas-tbody tr:not(.empty-row)'));
    const coinciden = getFilteredCajaRows();
    todas.forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = cajasPageSize === 'all';
    const size         = esTodos ? total : cajasPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    if (cajasPage > totalPaginas) cajasPage = totalPaginas;
    if (cajasPage < 1) cajasPage = 1;

    const start = esTodos ? 0 : (cajasPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    setText('cajas-count', `${total} resultado${total !== 1 ? 's' : ''}`);

    const rangeEl = document.getElementById('cajas-range');
    if (rangeEl) {
        rangeEl.textContent = total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`;
    }

    const btnPrev = document.getElementById('cajas-prev');
    const btnNext = document.getElementById('cajas-next');
    if (btnPrev) btnPrev.disabled = cajasPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || cajasPage >= totalPaginas;
}

function initCajasPagination() {
    document.getElementById('cajas-page-size')?.addEventListener('change', function() {
        cajasPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        cajasPage = 1;
        renderCajasPage();
    });
    document.getElementById('cajas-prev')?.addEventListener('click', () => {
        cajasPage--;
        renderCajasPage();
    });
    document.getElementById('cajas-next')?.addEventListener('click', () => {
        cajasPage++;
        renderCajasPage();
    });
}

// ---- ORDENAMIENTO ASC / DESC ----
// Cada celda ordenable trae su valor "crudo" en data-sort: el nombre, la
// fecha en 'YYYY-MM-DD' y los montos como número (no el texto "$1.500.000").
let cajasSortKey = null; // índice de columna, coincide con data-sort-key del <th>
let cajasSortDir = 'asc';

function sortCajaRows(key, type) {
    const tbody = document.getElementById('cajas-tbody');
    if (!tbody) return;
    const filas = Array.from(tbody.querySelectorAll('tr:not(.empty-row)'));
    if (filas.length === 0) return;

    cajasSortDir = (cajasSortKey === key && cajasSortDir === 'asc') ? 'desc' : 'asc';
    cajasSortKey = key;

    const getValor = fila => {
        const celda = fila.cells[Number(key)];
        const crudo = celda?.dataset.sort;
        const base  = crudo !== undefined ? crudo : (celda?.textContent.trim() ?? '');
        return type === 'number' ? (parseFloat(base) || 0) : base.toLowerCase();
    };

    filas.sort((a, b) => {
        const va  = getValor(a);
        const vb  = getValor(b);
        const cmp = type === 'number' ? (va - vb) : va.localeCompare(vb, 'es');
        return cajasSortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-caja-menor .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${cajasSortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    cajasPage = 1;
    renderCajasPage();
}

function initCajasSorting() {
    document.querySelectorAll('#mod-caja-menor .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortCajaRows(th.dataset.sortKey, th.dataset.sortType));
    });
}

// ---- ALTO DINÁMICO DE LA TABLA (evita el doble scroll) ----
function ajustarAlturaTablaCajas() {
    const scrollBox = document.getElementById('cajas-table-scroll');
    if (!scrollBox) return;
    const footer = document.querySelector('#mod-caja-menor .table-footer');
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
// 6. INICIALIZACIÓN GENERAL
// ============================================================
document.addEventListener('DOMContentLoaded', function() {
    initCajaModule();
});

function initCajaModule() {
    document.getElementById('btn-add-caja')?.addEventListener('click', openNewModal);

    document.getElementById('caja-search')?.addEventListener('input', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    document.querySelectorAll('.filter-toggle').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('.filter-toggle').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            applyFilters();
        });
    });

    // ---------- PAGINACIÓN Y ORDENAMIENTO ----------
    initCajasPagination();
    initCajasSorting();
    renderCajasPage();
    ajustarAlturaTablaCajas();
    window.addEventListener('resize', ajustarAlturaTablaCajas);

    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));
    document.querySelectorAll('.btn-close-edit-modal, .btn-cancel-edit-modal')
        .forEach(btn => btn.addEventListener('click', closeEditModal));

    document.getElementById('close-detail-modal')?.addEventListener('click', closeDetailModal);
    document.getElementById('close-detail-btn')?.addEventListener('click', closeDetailModal);

    // Los modales NO se cierran al hacer clic por fuera (en el fondo oscuro):
    // así no se pierde lo que se lleva escrito en un formulario por un clic
    // accidental. Se cierran solo con la X, "Cancelar" o "Cerrar".

    // ---------- MODAL: CONFIRMAR ACCIÓN ----------
    document.getElementById('confirm-accion-ok-btn')?.addEventListener('click', () => _resolverConfirmAccion(true));
    document.getElementById('confirm-accion-cancel-btn')?.addEventListener('click', () => _resolverConfirmAccion(false));

    // ---------- SUBMIT: NUEVA CAJA ----------
    document.getElementById('new-btn-save')?.addEventListener('click', async function() {
        const form = document.getElementById('new-caja-form');
        clearAllFieldErrors('new');
        const formData = new FormData(form);

        try {
            const response = await fetch(window.location.href, { method: 'POST', body: formData });
            const text = await response.text();
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }

            if (result.success) {
                showToast(result.message, 'success');
                closeNewModal();
                location.reload();
            } else if (result.errors && Object.keys(result.errors).length > 0) {
                Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
            } else {
                showToast(result.message || 'Error al guardar', 'error');
            }
        } catch (err) {
            showToast('Error de conexión', 'error');
        }
    });

    // ---------- SUBMIT: EDITAR NOMBRE DE CAJA ----------
    document.getElementById('edit-btn-save')?.addEventListener('click', async function() {
        const form = document.getElementById('edit-caja-form');
        clearAllFieldErrors('edit');
        const formData = new FormData(form);

        try {
            const response = await fetch(window.location.href, { method: 'POST', body: formData });
            const text = await response.text();
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }

            if (result.success) {
                showToast(result.message, 'success');
                closeEditModal();
                location.reload();
            } else if (result.errors && Object.keys(result.errors).length > 0) {
                Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
            } else {
                showToast(result.message || 'Error al actualizar', 'error');
            }
        } catch (err) {
            showToast('Error de conexión', 'error');
        }
    });

    // ---------- SUBMIT: NUEVO MOVIMIENTO ----------
    document.getElementById('mov-btn-save')?.addEventListener('click', async function() {
        // Defensa en el cliente: la validación definitiva la hace la BD
        if (!cajaEstaActiva(cajaActualDetalle)) {
            showToast('La caja está cerrada y no admite nuevos movimientos.', 'error');
            return;
        }

        const btn  = this;
        const form = document.getElementById('new-mov-form');
        clearAllFieldErrors('mov');
        const formData = new FormData(form);
        const idCaja = formData.get('hid_mov_id_caja');

        btn.disabled = true; // evita doble registro por doble clic
        try {
            const response = await fetch(window.location.href, { method: 'POST', body: formData });
            const text = await response.text();
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }

            if (result.success) {
                showToast(result.message, 'success');
                // No recargamos toda la página: eso cerraba el modal antes de
                // que se alcanzara a ver la confirmación. En vez de eso,
                // limpiamos el formulario y refrescamos solo la lista de
                // movimientos, dejando el modal abierto.
                setVal('mov-concepto', '');
                setVal('mov-valor', '');
                setVal('mov-fecha', fechaHoyLocal());
                loadMovimientos(idCaja);
            } else if (result.errors && Object.keys(result.errors).length > 0) {
                Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
            } else {
                showToast(result.message || 'Error al registrar el movimiento', 'error');
            }
        } catch (err) {
            showToast('Error de conexión', 'error');
        } finally {
            btn.disabled = false;
        }
    });
}
