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
    toast.classList.toggle('toast-error', type === 'error');
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
            btnCerrarCaja.onclick = () => cerrarCajaMenor(caja);   // propiedad, no atributo onclick en el HTML
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
                            <select class="form-input mov-estado-select" data-id-caja="${m.id_caja_menor}" data-id-mov="${m.id_movimiento}" ${bloqueado ? 'disabled' : ''}>
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
                movList.innerHTML = '<p class="tcx-lista-msg">No hay movimientos registrados en esta caja.</p>';
            }
        })
        .catch(() => {
            if (movList) movList.innerHTML = '<p class="tcx-lista-msg error">Error al cargar los movimientos.</p>';
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


// ============================================================
// 5. LISTA: INDICADORES, FILTROS, ORDEN Y PAGINADOR
// La tabla la pinta este archivo desde cajasData (PHP). Paginador y
// orden: componentes compartidos del ERP (erp_ui.js) — GUIA_PANTALLAS_ERP §4-§5.
// Sin botón de "ver": clic (o Enter/espacio) en la fila abre el detalle.
// ============================================================
let pag = null, orden = null;
const norm = t => (window.erpNormalizar ? erpNormalizar(t) : String(t ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim());
const datos = () => (typeof cajasData !== 'undefined' && Array.isArray(cajasData) ? cajasData : []);
const pctDisponible = c => (Number(c.monto_asignado) > 0 ? Math.round((Number(c.monto_disponible) / Number(c.monto_asignado)) * 100) : 0);

function updateStats() {
    const data = datos();
    const activas = data.filter(cajaEstaActiva);
    const suma = (arr, k) => arr.reduce((t, c) => t + (Number(c[k]) || 0), 0);
    setText('stat-total', data.length);
    setText('stat-activas', activas.length);
    setText('stat-disponible', formatCurrency(suma(activas, 'monto_disponible')));
    setText('stat-asignado', formatCurrency(suma(activas, 'monto_asignado')));
    const asig = suma(activas, 'monto_asignado');
    setText('stat-disponible-hint', asig > 0 ? `${Math.round(suma(activas, 'monto_disponible') / asig * 100)}% de lo asignado` : 'De las cajas activas');
    setText('caja-cnt-all', data.length);
    setText('caja-cnt-activa', activas.length);
    setText('caja-cnt-cerrada', data.length - activas.length);
}

function prepararLista() {
    if (!pag && window.ErpPaginador) {
        pag = ErpPaginador.crear({ lista: document.getElementById('cajas-tbody'), onCambio: renderCajas, tam: 25 });
    }
    if (!orden && window.ErpOrden) {
        orden = ErpOrden.crear({
            tabla: document.getElementById('cajas-table'),
            columnas: {
                'Caja':       { valor: c => c.nom_caja_menor },
                'Apertura':   { valor: c => String(c.fecha_apertura || '').slice(0, 10), tipo: 'fecha' },
                'Asignado':   { valor: c => Number(c.monto_asignado) || 0, tipo: 'numero' },
                'Disponible': { valor: c => Number(c.monto_disponible) || 0, tipo: 'numero' },
                'Estado':     { valor: c => (cajaEstaActiva(c) ? 1 : 0), tipo: 'numero' },
            },
            onCambio: () => { if (pag) pag.inicio(); renderCajas(); },
        });
    }
}

function hayFiltros() {
    return val('caja-search').trim() !== '' || (val('caja-filtro-estado') || 'all') !== 'all';
}

function getFilteredCajas() {
    const q = norm(val('caja-search'));
    const estado = val('caja-filtro-estado') || 'all';
    return datos().filter(c => {
        const activa = cajaEstaActiva(c);
        if (estado === 'activa' && !activa) return false;
        if (estado === 'cerrada' && activa) return false;
        if (q && !norm(`${c.id_caja_menor} ${c.nom_caja_menor}`).includes(q)) return false;
        return true;
    });
}

function applyFilters() {
    if (pag) pag.inicio();
    renderCajas();
}

function clearFilters() {
    setVal('caja-search', '');
    setVal('caja-filtro-estado', 'all');
    if (window.ErpFiltros) ErpFiltros.sincronizar();
    applyFilters();
}

// Lista: filtrar → contar → ordenar → paginar → pintar
function renderCajas() {
    prepararLista();
    let filas = getFilteredCajas();
    setText('cajas-count', `${filas.length} resultado${filas.length !== 1 ? 's' : ''}`);
    const btnClear = document.getElementById('btn-clear-filters');
    if (btnClear) btnClear.hidden = !hayFiltros();

    const tbody = document.getElementById('cajas-tbody');
    if (!tbody) return;
    if (filas.length === 0) {
        const hayDatos = datos().length > 0;
        tbody.innerHTML = `<tr><td colspan="6"><div class="empty-state">
            <i class="fas ${hayDatos ? 'fa-search' : 'fa-cash-register'}"></i>
            <p>${hayDatos ? 'Ninguna caja coincide con los filtros' : 'No hay cajas menores para mostrar'}</p>
            <span>${hayDatos ? 'Cambie la búsqueda o use «Limpiar»' : 'Use «Nueva caja» para registrar la primera'}</span>
        </div></td></tr>`;
        if (pag) pag.paginar([]);
        return;
    }
    if (orden) filas = orden.ordenar(filas);
    const pagina = pag ? pag.paginar(filas) : filas;
    tbody.innerHTML = pagina.map(c => {
        const id = escapeHtml(c.id_caja_menor);
        const nombre = escapeHtml(c.nom_caja_menor);
        const activa = cajaEstaActiva(c);
        return `<tr data-fila-abre data-id="${id}" tabindex="0" aria-label="Ver los movimientos de ${nombre}">
            <td><span class="tcx-fuerte">${nombre}</span><span class="tcx-sub">#${id} · ${pctDisponible(c)}% disponible</span></td>
            <td class="tcx-num">${escapeHtml(formatDate(String(c.fecha_apertura || '').slice(0, 10)))}</td>
            <td class="text-right tcx-num">${formatCurrency(c.monto_asignado)}</td>
            <td class="text-right tcx-num">${formatCurrency(c.monto_disponible)}</td>
            <td><span class="badge ${activa ? 'ok' : 'mute'}">${activa ? 'Activa' : 'Cerrada'}</span></td>
            <td class="col-acciones">
                <div class="actions-cell">
                    <button type="button" class="btn-icon-sm edit" data-caja-accion="editar" title="Editar nombre" aria-label="Editar el nombre de ${nombre}"><i class="fas fa-pen"></i></button>
                    ${activa ? `<button type="button" class="btn-icon-sm reject" data-caja-accion="cerrar" title="Cerrar caja" aria-label="Cerrar ${nombre}"><i class="fas fa-lock"></i></button>` : ''}
                </div>
            </td>
        </tr>`;
    }).join('');
}

// ============================================================
// 6. INICIALIZACIÓN GENERAL
// ============================================================
document.addEventListener('DOMContentLoaded', function() {
    initCajaModule();
});

function initCajaModule() {
    // Los modales los mueve a <body> el componente "modales" (erp_ui.js); el aviso se mueve aquí
    const toastEl = document.getElementById('toast');
    if (toastEl && toastEl.parentElement !== document.body) document.body.appendChild(toastEl);

    document.getElementById('btn-add-caja')?.addEventListener('click', openNewModal);

    document.getElementById('caja-search')?.addEventListener('input', applyFilters);
    document.getElementById('caja-filtro-estado')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // Clic (o Enter/espacio) en la fila abre el detalle; los botones hacen lo suyo
    const tbody = document.getElementById('cajas-tbody');
    const cajaDe = tr => datos().find(x => String(x.id_caja_menor) === tr.dataset.id);
    tbody?.addEventListener('click', e => {
        const tr = e.target.closest('tr[data-fila-abre]');
        if (!tr) return;
        const caja = cajaDe(tr);
        if (!caja) return;
        const b = e.target.closest('[data-caja-accion]');
        if (b) {
            if (b.dataset.cajaAccion === 'editar') openEditModal(caja);
            if (b.dataset.cajaAccion === 'cerrar') cerrarCajaMenor(caja);
            return;
        }
        if (e.target.closest('button, a, input, select, textarea')) return;
        openDetailModal(caja);
    });
    tbody?.addEventListener('keydown', e => {
        if (e.key !== 'Enter' && e.key !== ' ') return;
        const tr = e.target.closest('tr[data-fila-abre]');
        if (!tr || e.target !== tr) return;
        e.preventDefault();
        const caja = cajaDe(tr);
        if (caja) openDetailModal(caja);
    });

    // ---------- LISTA ----------
    updateStats();
    renderCajas();
    if (window.ErpListaFija) ErpListaFija.ajustar();
    const mod = document.getElementById('mod-caja-menor');
    requestAnimationFrame(() => requestAnimationFrame(() => mod?.classList.add('is-listo')));

    // La confirmación es de solo lectura: Esc la cierra (como "Cancelar").
    // El detalle tiene el formulario de movimiento: se cierra solo con la X o "Cerrar".
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        const m = document.getElementById('modal-confirm-accion');
        if (m && !m.classList.contains('hidden')) _resolverConfirmAccion(false);
    });

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
