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
    toast.classList.toggle('toast-error', type === 'error');
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
// 4. LISTA: INDICADORES, FILTROS, ORDEN Y PAGINADOR
// La tabla la pinta este archivo desde codigosData (PHP). Paginador y
// orden: componentes compartidos del ERP (erp_ui.js) — GUIA_PANTALLAS_ERP §4-§5.
// "Todos" no incluye los dados de baja: van aparte, como una papelera.
// ============================================================
let pag = null, orden = null;
const normCod = t => (window.erpNormalizar ? erpNormalizar(t) : String(t ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim());
const datosCod = () => (typeof codigosData !== 'undefined' && Array.isArray(codigosData) ? codigosData : []);
const escCod = v => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');

function updateStats() {
    const data = datosCod();
    const activos = data.filter(c => !c.ind_borrado);
    const bancosCon = new Set(activos.map(c => String(c.id_banco)));
    const bancosAct = (typeof codigosBancosActivos !== 'undefined' ? codigosBancosActivos : []);
    const sin = bancosAct.filter(b => !bancosCon.has(String(b.id_banco)));
    setText('stat-activos', activos.length);
    setText('stat-inactivos', data.length - activos.length);
    setText('stat-bancos', bancosCon.size);
    setText('stat-sin-codigos', sin.length);
    setText('stat-sin-codigos-hint', sin.length ? `Ej.: ${sin[0].nom_banco}` : 'Todos tienen catálogo');
    setText('cod-cnt-all', activos.length);
    setText('cod-cnt-baja', data.length - activos.length);
}

function prepararLista() {
    if (!pag && window.ErpPaginador) {
        pag = ErpPaginador.crear({ lista: document.getElementById('codigos-tbody'), onCambio: renderCodigos, tam: 25 });
    }
    if (!orden && window.ErpOrden) {
        orden = ErpOrden.crear({
            tabla: document.getElementById('codigos-table'),
            columnas: {
                'Código':      { valor: c => c.id_codigo },
                'Banco':       { valor: c => c.nom_banco },
                'Descripción': { valor: c => c.des_motivo },
                'Estado':      { valor: c => (c.ind_borrado ? 0 : 1), tipo: 'numero' },
            },
            onCambio: () => { if (pag) pag.inicio(); renderCodigos(); },
        });
    }
}

function hayFiltros() {
    return val('codigo-search').trim() !== '' || val('codigo-banco-filter') !== '' || (val('codigo-filtro-estado') || 'all') !== 'all';
}

function getFilteredCodigos() {
    const q = normCod(val('codigo-search'));
    const banco = val('codigo-banco-filter');
    const papelera = (val('codigo-filtro-estado') || 'all') === 'baja';
    return datosCod().filter(c => {
        if (!!c.ind_borrado !== papelera) return false;
        if (banco && String(c.id_banco) !== banco) return false;
        if (q && !normCod(`${c.id_codigo} ${c.nom_banco} ${c.des_motivo}`).includes(q)) return false;
        return true;
    });
}

function applyFilters() {
    if (pag) pag.inicio();
    renderCodigos();
}

function clearFilters() {
    setVal('codigo-search', '');
    setVal('codigo-banco-filter', '');
    setVal('codigo-filtro-estado', 'all');
    if (window.ErpFiltros) ErpFiltros.sincronizar();
    applyFilters();
}

// Lista: filtrar → contar → ordenar → paginar → pintar
function renderCodigos() {
    prepararLista();
    let filas = getFilteredCodigos();
    setText('codigos-count', `${filas.length} resultado${filas.length !== 1 ? 's' : ''}`);
    const btnClear = document.getElementById('btn-clear-filters');
    if (btnClear) btnClear.hidden = !hayFiltros();

    const tbody = document.getElementById('codigos-tbody');
    if (!tbody) return;
    if (filas.length === 0) {
        const hayDatos = datosCod().length > 0;
        tbody.innerHTML = `<tr><td colspan="5"><div class="empty-state">
            <i class="fas ${hayDatos ? 'fa-search' : 'fa-barcode'}"></i>
            <p>${hayDatos ? 'Ningún código coincide con los filtros' : 'No hay códigos de respuesta para mostrar'}</p>
            <span>${hayDatos ? 'Cambie la búsqueda o use «Limpiar»' : 'Use «Nuevo código» para registrar el primero'}</span>
        </div></td></tr>`;
        if (pag) pag.paginar([]);
        return;
    }
    if (orden) filas = orden.ordenar(filas);
    const pagina = pag ? pag.paginar(filas) : filas;
    tbody.innerHTML = pagina.map(c => {
        const i = datosCod().indexOf(c);
        const cod = escCod(c.id_codigo);
        return `<tr data-i="${i}">
            <td><span class="cod-bancario">${cod}</span></td>
            <td>${escCod(c.nom_banco)}</td>
            <td>${escCod(c.des_motivo)}</td>
            <td><span class="badge ${c.ind_borrado ? 'mute' : 'ok'}">${c.ind_borrado ? 'De baja' : 'Activo'}</span></td>
            <td class="col-acciones">
                <div class="actions-cell">
                    <button type="button" class="btn-icon-sm edit" data-action="editar" title="Editar" aria-label="Editar el código ${cod}"><i class="fas fa-pen"></i></button>
                    ${c.ind_borrado
                        ? `<button type="button" class="btn-icon-sm restore" data-action="reactivar" title="Reactivar" aria-label="Reactivar el código ${cod}"><i class="fas fa-undo"></i></button>`
                        : `<button type="button" class="btn-icon-sm reject" data-action="eliminar" title="Dar de baja" aria-label="Dar de baja el código ${cod}"><i class="fas fa-trash"></i></button>`}
                </div>
            </td>
        </tr>`;
    }).join('');
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
    // Los modales los mueve a <body> el componente "modales" (erp_ui.js); el aviso se mueve aquí
    const toastEl = document.getElementById('toast');
    if (toastEl && toastEl.parentElement !== document.body) document.body.appendChild(toastEl);

    document.getElementById('btn-add-codigo')?.addEventListener('click', openNewModal);

    document.getElementById('codigo-search')?.addEventListener('input', applyFilters);
    document.getElementById('codigo-banco-filter')?.addEventListener('change', applyFilters);
    document.getElementById('codigo-filtro-estado')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // ---------- BOTONES DE CADA FILA (editar / dar de baja / reactivar) ----------
    document.getElementById('codigos-tbody')?.addEventListener('click', function(e) {
        const btn = e.target.closest('button[data-action]');
        const tr = e.target.closest('tr[data-i]');
        if (!btn || !tr) return;
        const codigo = datosCod()[Number(tr.dataset.i)];
        if (!codigo) return;
        if (btn.dataset.action === 'editar')    openEditModal(codigo);
        if (btn.dataset.action === 'eliminar')  darDeBajaCodigo(codigo);
        if (btn.dataset.action === 'reactivar') reactivarCodigo(codigo);
    });

    // ---------- LISTA ----------
    updateStats();
    renderCodigos();
    if (window.ErpListaFija) ErpListaFija.ajustar();
    const mod = document.getElementById('mod-codigos');
    requestAnimationFrame(() => requestAnimationFrame(() => mod?.classList.add('is-listo')));

    // La confirmación es de solo lectura: Esc la cierra (los formularios, solo X o Cancelar)
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        const m = document.getElementById('modal-confirm-eliminar');
        if (m && !m.classList.contains('hidden')) cerrarConfirmEliminar();
    });

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
