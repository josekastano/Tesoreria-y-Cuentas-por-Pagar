'use strict';

// Evita que el archivo se ejecute dos veces si se incluye en dos sitios
(function () {
if (window.__bancosCargado) return;
window.__bancosCargado = true;

// ============================================================
// 1. HELPERS
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
    span.textContent = message && message.trim() ? message : (type === 'success' ? 'Operación exitosa' : 'Ocurrió un error');
    toast.classList.toggle('toast-error', type === 'error');
    toast.classList.remove('hidden');
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => toast.classList.add('hidden'), 3500);
}

function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

function resumenRespuesta(text) {
    const div = document.createElement('div');
    div.innerHTML = text || '';
    const plano = (div.textContent || '').replace(/\s+/g, ' ').trim();
    if (!plano) return '(respuesta vacía; revise el log de errores de PHP)';
    const i = plano.search(/(fatal|error|warning|notice|uncaught)/i);
    return (i >= 0 ? plano.slice(i) : plano).slice(0, 220);
}

async function enviarFormulario(formData, mensajeError, onSuccess) {
    try {
        const response = await fetch(window.location.href, { method: 'POST', body: formData });
        const text = await response.text();
        let result;
        try { result = JSON.parse(text); }
        catch (e) {
            console.error('Respuesta del servidor que no es JSON:', text);
            result = { success: false, message: 'Respuesta inválida del servidor: ' + resumenRespuesta(text) };
        }

        if (result.success) {
            showToast(result.message, 'success');
            if (typeof onSuccess === 'function') onSuccess();
            setTimeout(() => location.reload(), 700);
        } else if (result.errors && Object.keys(result.errors).length > 0) {
            Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
        } else {
            showToast(result.message || mensajeError, 'error');
        }
    } catch (err) {
        console.error(err);
        showToast('Error de conexión', 'error');
    }
}

function esActivo(valor) {
    return valor === true || valor === 't' || valor === 'true' || valor === 1 || valor === '1';
}

// ============================================================
// 2. MODAL: NUEVO BANCO
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    setVal('new-id-banco', '');
    setVal('new-nom-banco', '');
    setVal('new-estado', 'true');
    show('modal-new-banco');
    setTimeout(() => document.getElementById('new-id-banco')?.focus(), 50);
}

function closeNewModal() { hide('modal-new-banco'); }

// ============================================================
// 3. MODAL: EDITAR BANCO  (lo abre el botón Editar de cada fila)
// ============================================================
function openEditModal(banco) {
    clearAllFieldErrors('edit');
    setVal('edit-id-banco-hid', banco.id_banco);
    setVal('edit-id-banco-display', banco.id_banco);
    setVal('edit-nom-banco', banco.nom_banco);
    setVal('edit-estado', esActivo(banco.ind_estado) ? 'true' : 'false');
    show('modal-edit-banco');
    setTimeout(() => document.getElementById('edit-nom-banco')?.focus(), 50);
}

function closeEditModal() { hide('modal-edit-banco'); }

// ============================================================
// 4. ACTIVAR / DESACTIVAR  (botón de cada fila)
// ============================================================
function toggleEstadoBanco(idBanco, nuevoEstado) {
    const formData = new FormData();
    formData.append('btn_toggle_estado', '1');
    formData.append('hid_toggle_id_banco', idBanco);
    formData.append('hid_toggle_estado', nuevoEstado ? 'true' : 'false');
    enviarFormulario(formData, 'Error al cambiar el estado');
}

// ============================================================
// 5. ELIMINAR (con modal de confirmación)
// ============================================================
let _idEliminar = null;

function eliminarBanco(idBanco, nombre) {
    _idEliminar = idBanco;
    setText('confirm-eliminar-title', `Eliminar "${nombre}"`);
    setText('confirm-eliminar-body', `¿Desea eliminar el banco "${nombre}" (${idBanco})? Esta acción no se puede deshacer.`);
    show('modal-confirm-eliminar');
}

function cerrarConfirmEliminar() {
    hide('modal-confirm-eliminar');
    _idEliminar = null;
}

function confirmarEliminar() {
    if (!_idEliminar) return;
    const formData = new FormData();
    formData.append('btn_eliminar', '1');
    formData.append('hid_del_id_banco', _idEliminar);
    cerrarConfirmEliminar();
    enviarFormulario(formData, 'Error al eliminar');
}

// ============================================================
// 6. LISTA: INDICADORES, FILTROS, ORDEN Y PAGINADOR
// La tabla la pinta este archivo desde bancosData (PHP). Paginador y
// orden: componentes compartidos del ERP (erp_ui.js) — GUIA_PANTALLAS_ERP §4-§5.
// ============================================================
let pag = null, orden = null;
const norm = t => (window.erpNormalizar ? erpNormalizar(t) : String(t ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim());
const datos = () => (typeof bancosData !== 'undefined' && Array.isArray(bancosData) ? bancosData : []);

function updateStats() {
    const data = datos();
    const activos = data.filter(b => esActivo(b.ind_estado)).length;
    const conUso = data.filter(b => Number(b.num_cuentas) > 0).length;
    setText('stat-total', data.length);
    setText('stat-activos', activos);
    setText('stat-inactivos', data.length - activos);
    setText('stat-uso', conUso);
    setText('ban-cnt-all', data.length);
    setText('ban-cnt-activo', activos);
    setText('ban-cnt-inactivo', data.length - activos);
}

function prepararLista() {
    if (!pag && window.ErpPaginador) {
        pag = ErpPaginador.crear({ lista: document.getElementById('bancos-tbody'), onCambio: renderPage, tam: 25 });
    }
    if (!orden && window.ErpOrden) {
        orden = ErpOrden.crear({
            tabla: document.getElementById('bancos-table'),
            columnas: {
                'Código':           { valor: b => b.id_banco },
                'Nombre del banco': { valor: b => b.nom_banco },
                'Cuentas':          { valor: b => Number(b.num_cuentas) || 0, tipo: 'numero' },
                'Estado':           { valor: b => (esActivo(b.ind_estado) ? 1 : 0), tipo: 'numero' },
            },
            onCambio: () => { if (pag) pag.inicio(); renderPage(); },
        });
    }
}

function hayFiltros() {
    return val('banco-search').trim() !== '' || (val('banco-filtro-estado') || 'all') !== 'all';
}

function getFiltered() {
    const q = norm(val('banco-search'));
    const estado = val('banco-filtro-estado') || 'all';
    return datos().filter(b => {
        const activo = esActivo(b.ind_estado);
        if (estado === 'activo' && !activo) return false;
        if (estado === 'inactivo' && activo) return false;
        if (q && !norm(`${b.id_banco} ${b.nom_banco}`).includes(q)) return false;
        return true;
    });
}

function applyFilters() {
    if (pag) pag.inicio();
    renderPage();
}

function clearFilters() {
    setVal('banco-search', '');
    setVal('banco-filtro-estado', 'all');
    if (window.ErpFiltros) ErpFiltros.sincronizar();
    applyFilters();
}

// Lista: filtrar → contar → ordenar → paginar → pintar
function renderPage() {
    prepararLista();
    let filas = getFiltered();
    setText('bancos-count', `${filas.length} resultado${filas.length !== 1 ? 's' : ''}`);
    const btnClear = document.getElementById('btn-clear-filters');
    if (btnClear) btnClear.hidden = !hayFiltros();

    const tbody = document.getElementById('bancos-tbody');
    if (!tbody) return;
    if (filas.length === 0) {
        const hayDatos = datos().length > 0;
        tbody.innerHTML = `<tr><td colspan="5"><div class="empty-state">
            <i class="fas ${hayDatos ? 'fa-search' : 'fa-university'}"></i>
            <p>${hayDatos ? 'Ningún banco coincide con los filtros' : 'No hay bancos para mostrar'}</p>
            <span>${hayDatos ? 'Cambie la búsqueda o use «Limpiar»' : 'Use «Nuevo banco» para registrar el primero'}</span>
        </div></td></tr>`;
        if (pag) pag.paginar([]);
        return;
    }
    if (orden) filas = orden.ordenar(filas);
    const pagina = pag ? pag.paginar(filas) : filas;
    tbody.innerHTML = pagina.map(b => {
        const id = escapeHtml(b.id_banco);
        const nombre = escapeHtml(b.nom_banco);
        const activo = esActivo(b.ind_estado);
        const n = Number(b.num_cuentas) || 0;
        return `<tr data-id="${id}">
            <td class="tcx-num"><span class="tcx-fuerte">${id}</span></td>
            <td>${nombre}</td>
            <td class="text-center tcx-num">${n ? n : '<span class="tcx-muted">—</span>'}</td>
            <td><span class="badge ${activo ? 'ok' : 'mute'}">${activo ? 'Activo' : 'Inactivo'}</span></td>
            <td class="col-acciones">
                <div class="actions-cell">
                    <button type="button" class="btn-icon-sm ${activo ? 'toggle-off' : 'approve'}" data-ban-accion="estado" title="${activo ? 'Desactivar' : 'Activar'}" aria-label="${activo ? 'Desactivar' : 'Activar'} ${nombre}"><i class="fas fa-power-off"></i></button>
                    <button type="button" class="btn-icon-sm edit" data-ban-accion="editar" title="Editar" aria-label="Editar ${nombre}"><i class="fas fa-pen"></i></button>
                    <button type="button" class="btn-icon-sm reject" data-ban-accion="eliminar" title="Eliminar" aria-label="Eliminar ${nombre}"><i class="fas fa-trash"></i></button>
                </div>
            </td>
        </tr>`;
    }).join('');
}

// ============================================================
// 7. INICIALIZACIÓN
// ============================================================
function initBancosModule() {
    if (!document.getElementById('mod-bancos')) return;

    // Los modales los mueve a <body> el componente "modales" (erp_ui.js); el aviso se mueve aquí
    const toastEl = document.getElementById('toast');
    if (toastEl && toastEl.parentElement !== document.body) document.body.appendChild(toastEl);

    document.getElementById('btn-add-banco')?.addEventListener('click', openNewModal);

    // Filtros
    document.getElementById('banco-search')?.addEventListener('input', applyFilters);
    document.getElementById('banco-filtro-estado')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // Acciones de cada fila (sin onclick en línea)
    document.getElementById('bancos-tbody')?.addEventListener('click', e => {
        const btn = e.target.closest('[data-ban-accion]');
        const tr = e.target.closest('tr[data-id]');
        if (!btn || !tr) return;
        const banco = datos().find(x => String(x.id_banco) === tr.dataset.id);
        if (!banco) return;
        const accion = btn.dataset.banAccion;
        if (accion === 'estado')   toggleEstadoBanco(banco.id_banco, !esActivo(banco.ind_estado));
        if (accion === 'editar')   openEditModal(banco);
        if (accion === 'eliminar') eliminarBanco(banco.id_banco, banco.nom_banco);
    });

    // Lista
    updateStats();
    renderPage();
    if (window.ErpListaFija) ErpListaFija.ajustar();
    const mod = document.getElementById('mod-bancos');
    requestAnimationFrame(() => requestAnimationFrame(() => mod?.classList.add('is-listo')));

    // La confirmación es de solo lectura: Esc la cierra (los formularios, solo X o Cancelar)
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        const m = document.getElementById('modal-confirm-eliminar');
        if (m && !m.classList.contains('hidden')) cerrarConfirmEliminar();
    });

    // Cerrar modales
    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));
    document.querySelectorAll('.btn-close-edit-modal, .btn-cancel-edit-modal')
        .forEach(btn => btn.addEventListener('click', closeEditModal));

    // Confirmar eliminación
    document.getElementById('confirm-eliminar-cancel-btn')?.addEventListener('click', cerrarConfirmEliminar);
    document.getElementById('confirm-eliminar-ok-btn')?.addEventListener('click', confirmarEliminar);

    // Guardar
    document.getElementById('new-btn-save')?.addEventListener('click', () => {
        clearAllFieldErrors('new');
        const formData = new FormData(document.getElementById('new-banco-form'));
        enviarFormulario(formData, 'Error al guardar', closeNewModal);
    });
    document.getElementById('edit-btn-save')?.addEventListener('click', () => {
        clearAllFieldErrors('edit');
        const formData = new FormData(document.getElementById('edit-banco-form'));
        enviarFormulario(formData, 'Error al actualizar', closeEditModal);
    });

    // Enter dentro de un formulario = guardar
    document.getElementById('new-banco-form')?.addEventListener('submit', e => {
        e.preventDefault(); document.getElementById('new-btn-save')?.click();
    });
    document.getElementById('edit-banco-form')?.addEventListener('submit', e => {
        e.preventDefault(); document.getElementById('edit-btn-save')?.click();
    });
}

// Funciona tanto si el script carga antes como después de que la página termine
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initBancosModule);
} else {
    initBancosModule();
}
})();
