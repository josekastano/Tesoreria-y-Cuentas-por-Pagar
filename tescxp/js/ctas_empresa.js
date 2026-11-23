'use strict';

// ============================================================
// 1. HELPERS GENERALES (mismos que tescxp.js)
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

// ============================================================
// 2. MODAL: NUEVA CUENTA
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    setVal('new-id-banco', '');
    setVal('new-cta-empresa', '');
    setVal('new-tipocuenta', 'false');
    actualizarEstadoBancos();
    show('modal-new-cuenta');
}

function closeNewModal() {
    closeBancoRapidoModal();
    hide('modal-new-cuenta');
}

// ============================================================
// 2.1 MODAL ANIDADO: CREAR BANCO DESDE "NUEVA CUENTA"
// ============================================================

// ¿El select de la nueva cuenta tiene al menos un banco para escoger?
function hayBancos() {
    const sel = document.getElementById('new-id-banco');
    if (!sel) return false;
    return Array.from(sel.options).some(opt => opt.value !== '');
}

// Muestra/oculta el aviso "no hay bancos" y ajusta el texto del placeholder
function actualizarEstadoBancos() {
    const hay = hayBancos();
    document.getElementById('new-banco-empty')?.classList.toggle('hidden', hay);
    const placeholder = document.querySelector('#new-id-banco option[value=""]');
    if (placeholder) placeholder.textContent = hay ? 'Seleccione...' : 'No hay bancos registrados';
}

function openBancoRapidoModal() {
    clearAllFieldErrors('banco');
    setVal('banco-rapido-id', '');
    setVal('banco-rapido-nombre', '');
    show('modal-banco-rapido');
    setTimeout(() => document.getElementById('banco-rapido-id')?.focus(), 50);
}

function closeBancoRapidoModal() {
    hide('modal-banco-rapido');
}

// Agrega el banco nuevo a los selects (nueva y editar) en orden alfabético
function agregarBancoASelects(banco) {
    ['new-id-banco', 'edit-id-banco'].forEach(selId => {
        const sel = document.getElementById(selId);
        if (!sel) return;
        if (Array.from(sel.options).some(o => o.value === banco.id_banco)) return;

        const opt = document.createElement('option');
        opt.value = banco.id_banco;
        opt.textContent = banco.nom_banco;

        const siguiente = Array.from(sel.options).find(o =>
            o.value !== '' && o.textContent.localeCompare(banco.nom_banco, 'es', { sensitivity: 'base' }) > 0
        );
        sel.insertBefore(opt, siguiente || null);
    });
}

async function guardarBancoRapido() {
    const btn = document.getElementById('banco-rapido-save');
    if (btn?.disabled) return;
    clearAllFieldErrors('banco');

    const formData = new FormData(document.getElementById('banco-rapido-form'));
    if (btn) btn.disabled = true;

    try {
        const response = await fetch(window.location.href, { method: 'POST', body: formData });
        const text = await response.text();
        let result;
        try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }

        if (result.success && result.banco) {
            agregarBancoASelects(result.banco);
            setVal('new-id-banco', result.banco.id_banco);   // queda seleccionado
            clearAllFieldErrors('new-banco');
            const errBanco = document.getElementById('err-new-banco');
            if (errBanco) { errBanco.classList.remove('visible'); errBanco.textContent = ''; }
            actualizarEstadoBancos();
            closeBancoRapidoModal();
            showToast(result.message, 'success');
            document.getElementById('new-cta-empresa')?.focus();
        } else if (result.errors && Object.keys(result.errors).length > 0) {
            Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
        } else {
            showToast(result.message || 'Error al guardar el banco', 'error');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    } finally {
        if (btn) btn.disabled = false;
    }
}

function initBancoRapido() {
    const sel = document.getElementById('new-id-banco');

    // Si no hay bancos, al intentar abrir el select se abre el modal de crear banco
    sel?.addEventListener('mousedown', e => {
        if (!hayBancos()) { e.preventDefault(); openBancoRapidoModal(); }
    });
    sel?.addEventListener('keydown', e => {
        if (!hayBancos() && ['Enter', ' ', 'ArrowDown', 'ArrowUp'].includes(e.key)) {
            e.preventDefault();
            openBancoRapidoModal();
        }
    });

    document.getElementById('btn-open-banco-rapido')?.addEventListener('click', openBancoRapidoModal);
    document.getElementById('btn-empty-crear-banco')?.addEventListener('click', openBancoRapidoModal);

    document.querySelectorAll('.btn-close-banco-modal, .btn-cancel-banco-modal')
        .forEach(btn => btn.addEventListener('click', closeBancoRapidoModal));

    document.getElementById('banco-rapido-save')?.addEventListener('click', guardarBancoRapido);

    // Enter dentro del formulario = guardar (sin enviar la página)
    document.getElementById('banco-rapido-form')?.addEventListener('submit', e => {
        e.preventDefault();
        guardarBancoRapido();
    });

    actualizarEstadoBancos();
}

// ============================================================
// 3. MODAL: EDITAR CUENTA
// ============================================================
function openEditModal(cuenta) {
    clearAllFieldErrors('edit');
    setVal('edit-id-empresa-hid', cuenta.id_empresa);
    setVal('edit-cta-empresa-hid', cuenta.cta_empresa);
    setVal('edit-id-empresa-display', cuenta.id_empresa);
    setVal('edit-cta-empresa-display', cuenta.cta_empresa);
    setVal('edit-id-banco', cuenta.id_banco);
    const esCorriente = cuenta.ind_tipocuenta === 't' || cuenta.ind_tipocuenta === true;
    setVal('edit-tipocuenta', esCorriente ? 'true' : 'false');
    show('modal-edit-cuenta');
}

function closeEditModal() {
    hide('modal-edit-cuenta');
}


// ============================================================
// 4. LISTA: INDICADORES, FILTROS, ORDEN Y PAGINADOR
// La tabla la pinta este archivo desde ctasData (PHP). Paginador y
// orden: componentes compartidos del ERP (erp_ui.js) — GUIA_PANTALLAS_ERP §4-§5.
// ============================================================
let pag = null, orden = null;
const norm = t => (window.erpNormalizar ? erpNormalizar(t) : String(t ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim());
const datos = () => (typeof ctasData !== 'undefined' && Array.isArray(ctasData) ? ctasData : []);
const esCorriente = c => c.ind_tipocuenta === 't' || c.ind_tipocuenta === true;
const claveCta = c => `${c.id_empresa}|${c.cta_empresa}`;
function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

function updateStats() {
    const data = datos();
    const corr = data.filter(esCorriente).length;
    setText('stat-total', data.length);
    setText('stat-corrientes', corr);
    setText('stat-ahorros', data.length - corr);
    setText('stat-bancos', new Set(data.map(c => String(c.id_banco))).size);
    setText('cta-cnt-all', data.length);
    setText('cta-cnt-corriente', corr);
    setText('cta-cnt-ahorros', data.length - corr);
}

// Lista de bancos del filtro: los que aparecen en las cuentas
function llenarFiltroBancos() {
    const sel = document.getElementById('cuenta-banco-filter');
    if (!sel) return;
    const bancos = new Map();
    datos().forEach(c => bancos.set(String(c.id_banco), c.nom_banco));
    [...bancos.entries()].sort((x, y) => String(x[1]).localeCompare(String(y[1]), 'es')).forEach(([id, nom]) => {
        const o = document.createElement('option');
        o.value = id; o.textContent = nom;
        sel.appendChild(o);
    });
}

function prepararLista() {
    if (!pag && window.ErpPaginador) {
        pag = ErpPaginador.crear({ lista: document.getElementById('cuentas-tbody'), onCambio: renderCuentas, tam: 25 });
    }
    if (!orden && window.ErpOrden) {
        orden = ErpOrden.crear({
            tabla: document.getElementById('cuentas-table'),
            columnas: {
                'NIT empresa':      { valor: c => c.id_empresa },
                'Banco':            { valor: c => c.nom_banco },
                'Número de cuenta': { valor: c => c.cta_empresa },
                'Tipo':             { valor: c => (esCorriente(c) ? 'Corriente' : 'Ahorros') },
            },
            onCambio: () => { if (pag) pag.inicio(); renderCuentas(); },
        });
    }
}

function hayFiltros() {
    return val('cuenta-search').trim() !== '' || val('cuenta-banco-filter') !== '' || (val('cuenta-filtro-tipo') || 'all') !== 'all';
}

function getFilteredCuentas() {
    const q = norm(val('cuenta-search'));
    const banco = val('cuenta-banco-filter');
    const tipo = val('cuenta-filtro-tipo') || 'all';
    return datos().filter(c => {
        if (tipo === 'corriente' && !esCorriente(c)) return false;
        if (tipo === 'ahorros' && esCorriente(c)) return false;
        if (banco && String(c.id_banco) !== banco) return false;
        if (q && !norm(`${c.id_empresa} ${c.nom_empresa || ''} ${c.nom_banco} ${c.cta_empresa}`).includes(q)) return false;
        return true;
    });
}

function applyFilters() {
    if (pag) pag.inicio();
    renderCuentas();
}

function clearFilters() {
    setVal('cuenta-search', '');
    setVal('cuenta-banco-filter', '');
    setVal('cuenta-filtro-tipo', 'all');
    if (window.ErpFiltros) ErpFiltros.sincronizar();
    applyFilters();
}

// Lista: filtrar → contar → ordenar → paginar → pintar
function renderCuentas() {
    prepararLista();
    let filas = getFilteredCuentas();
    setText('cuentas-count', `${filas.length} resultado${filas.length !== 1 ? 's' : ''}`);
    const btnClear = document.getElementById('btn-clear-filters');
    if (btnClear) btnClear.hidden = !hayFiltros();

    const tbody = document.getElementById('cuentas-tbody');
    if (!tbody) return;
    if (filas.length === 0) {
        const hayDatos = datos().length > 0;
        tbody.innerHTML = `<tr><td colspan="5"><div class="empty-state">
            <i class="fas ${hayDatos ? 'fa-search' : 'fa-university'}"></i>
            <p>${hayDatos ? 'Ninguna cuenta coincide con los filtros' : 'No hay cuentas bancarias para mostrar'}</p>
            <span>${hayDatos ? 'Cambie la búsqueda o use «Limpiar»' : 'Use «Nueva cuenta» para registrar la primera'}</span>
        </div></td></tr>`;
        if (pag) pag.paginar([]);
        return;
    }
    if (orden) filas = orden.ordenar(filas);
    const pagina = pag ? pag.paginar(filas) : filas;
    tbody.innerHTML = pagina.map(c => {
        const cta = escapeHtml(c.cta_empresa);
        return `<tr data-clave="${escapeHtml(claveCta(c))}">
            <td class="tcx-num"><span class="tcx-fuerte">${escapeHtml(c.id_empresa)}</span>${c.nom_empresa ? `<span class="tcx-sub">${escapeHtml(c.nom_empresa)}</span>` : ''}</td>
            <td>${escapeHtml(c.nom_banco)}</td>
            <td class="tcx-num">${cta}</td>
            <td><span class="badge ${esCorriente(c) ? 'info' : 'warn'}">${esCorriente(c) ? 'Corriente' : 'Ahorros'}</span></td>
            <td class="col-acciones">
                <div class="actions-cell">
                    <button type="button" class="btn-icon-sm edit" data-cta-accion="editar" title="Editar" aria-label="Editar la cuenta ${cta}"><i class="fas fa-pen"></i></button>
                    <button type="button" class="btn-icon-sm reject" data-cta-accion="eliminar" title="Eliminar" aria-label="Eliminar la cuenta ${cta}"><i class="fas fa-trash"></i></button>
                </div>
            </td>
        </tr>`;
    }).join('');
}

// ============================================================
// 5. MODAL DE CONFIRMACIÓN DE ELIMINACIÓN (estilo módulo Compras)
// ============================================================
let _confirmDeleteAction = null;

function abrirConfirmEliminar(titulo, mensaje, accion) {
    setText('confirm-eliminar-title', titulo);
    setText('confirm-eliminar-body', mensaje);
    _confirmDeleteAction = accion;
    show('modal-confirm-eliminar');
}

function cerrarConfirmEliminar() {
    hide('modal-confirm-eliminar');
    _confirmDeleteAction = null;
}

// ============================================================
// 5.1 ELIMINAR CUENTA (función global)
// ============================================================
window.eliminarCuenta = function(idEmpresa, ctaEmpresa, nombreBanco) {
    abrirConfirmEliminar(
        `Eliminar cuenta ${ctaEmpresa}`,
        `¿Desea eliminar la cuenta ${ctaEmpresa} (${nombreBanco})? Esta acción es reversible desde la base de datos.`,
        () => ejecutarEliminarCuenta(idEmpresa, ctaEmpresa)
    );
};

function ejecutarEliminarCuenta(idEmpresa, ctaEmpresa) {
    const formData = new FormData();
    formData.append('btn_eliminar', '1');
    formData.append('hid_del_id_empresa', idEmpresa);
    formData.append('hid_del_cta_empresa', ctaEmpresa);
    fetch(window.location.href, {
        method: 'POST',
        body: formData
    })
    .then(res => res.text())
    .then(text => {
        let result;
        try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida' }; }
        if (result.success) {
            showToast(result.message, 'success');
            location.reload();
        } else {
            showToast(result.message || 'Error al eliminar', 'error');
        }
    })
    .catch(() => showToast('Error de conexión', 'error'));
}

// ============================================================
// 6. INICIALIZACIÓN GENERAL
// ============================================================
document.addEventListener('DOMContentLoaded', function() {
    initCuentaModule();
});

function initCuentaModule() {
    // Los modales los mueve a <body> el componente "modales" (erp_ui.js); el aviso se mueve aquí
    const toastEl = document.getElementById('toast');
    if (toastEl && toastEl.parentElement !== document.body) document.body.appendChild(toastEl);

    document.getElementById('btn-add-cuenta')?.addEventListener('click', openNewModal);

    document.getElementById('cuenta-search')?.addEventListener('input', applyFilters);
    document.getElementById('cuenta-banco-filter')?.addEventListener('change', applyFilters);
    document.getElementById('cuenta-filtro-tipo')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // Acciones de cada fila (sin onclick en línea)
    document.getElementById('cuentas-tbody')?.addEventListener('click', e => {
        const btn = e.target.closest('[data-cta-accion]');
        const tr = e.target.closest('tr[data-clave]');
        if (!btn || !tr) return;
        const c = datos().find(x => claveCta(x) === tr.dataset.clave);
        if (!c) return;
        if (btn.dataset.ctaAccion === 'editar') openEditModal(c);
        if (btn.dataset.ctaAccion === 'eliminar') window.eliminarCuenta(c.id_empresa, c.cta_empresa, c.nom_banco);
    });

    // ---------- LISTA ----------
    updateStats();
    llenarFiltroBancos();
    renderCuentas();
    if (window.ErpListaFija) ErpListaFija.ajustar();
    const mod = document.getElementById('mod-ctas-empresa');
    requestAnimationFrame(() => requestAnimationFrame(() => mod?.classList.add('is-listo')));

    // La confirmación es de solo lectura: Esc la cierra (los formularios, solo X o Cancelar)
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        const m = document.getElementById('modal-confirm-eliminar');
        if (m && !m.classList.contains('hidden')) cerrarConfirmEliminar();
    });

    // ---------- MODAL ANIDADO: CREAR BANCO ----------
    initBancoRapido();

    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));
    document.querySelectorAll('.btn-close-edit-modal, .btn-cancel-edit-modal')
        .forEach(btn => btn.addEventListener('click', closeEditModal));

    // Los modales NO se cierran al hacer clic por fuera (en el fondo oscuro):
    // así no se pierde lo que se lleva escrito en un formulario por un clic
    // accidental. Se cierran solo con la X, "Cancelar" o "Cerrar".

    // ---------- MODAL: CONFIRMAR ELIMINACIÓN ----------
    document.getElementById('confirm-eliminar-cancel-btn')?.addEventListener('click', cerrarConfirmEliminar);
    document.getElementById('confirm-eliminar-ok-btn')?.addEventListener('click', () => {
        const accion = _confirmDeleteAction;
        cerrarConfirmEliminar();
        if (typeof accion === 'function') accion();
    });

    // ---------- SUBMIT: NUEVA CUENTA ----------
    document.getElementById('new-btn-save')?.addEventListener('click', async function() {
        const form = document.getElementById('new-cuenta-form');
        clearAllFieldErrors('new');
        const formData = new FormData(form);

        try {
            const response = await fetch(window.location.href, {
                method: 'POST',
                body: formData
            });
            const text = await response.text();
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }

            if (result.success) {
                showToast(result.message, 'success');
                closeNewModal();
                location.reload();
            } else if (result.errors && Object.keys(result.errors).length > 0) {
                Object.entries(result.errors).forEach(([spanId, mensaje]) => {
                    showFieldError(spanId, mensaje);
                });
            } else {
                showToast(result.message || 'Error al guardar', 'error');
            }
        } catch (err) {
            showToast('Error de conexión', 'error');
        }
    });

    // ---------- SUBMIT: EDITAR CUENTA ----------
    document.getElementById('edit-btn-save')?.addEventListener('click', async function() {
        const form = document.getElementById('edit-cuenta-form');
        clearAllFieldErrors('edit');
        const formData = new FormData(form);

        try {
            const response = await fetch(window.location.href, {
                method: 'POST',
                body: formData
            });
            const text = await response.text();
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }

            if (result.success) {
                showToast(result.message, 'success');
                closeEditModal();
                location.reload();
            } else if (result.errors && Object.keys(result.errors).length > 0) {
                Object.entries(result.errors).forEach(([spanId, mensaje]) => {
                    showFieldError(spanId, mensaje);
                });
            } else {
                showToast(result.message || 'Error al actualizar', 'error');
            }
        } catch (err) {
            showToast('Error de conexión', 'error');
        }
    });
}
