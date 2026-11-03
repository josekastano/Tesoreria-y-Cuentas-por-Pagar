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
    toast.style.background = type === 'error' ? '#ef4444' : '#0f172a';
    toast.classList.remove('hidden');
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => toast.classList.add('hidden'), 3500);
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
// 3. MODAL: EDITAR BANCO  (lo llama el onclick de cada fila)
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
// 4. ACTIVAR / DESACTIVAR  (lo llama el onclick de cada fila)
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

// Las funciones que usan los onclick="" del HTML deben ser globales
window.openEditModal     = openEditModal;
window.toggleEstadoBanco = toggleEstadoBanco;
window.eliminarBanco     = eliminarBanco;

// ============================================================
// 6. FILTROS + PAGINACIÓN + ORDEN
// ============================================================
let bancosPage     = 1;
let bancosPageSize = 25; // coincide con el <option selected>
let bancosFiltro   = 'all';
let sortKey = null;
let sortDir = 'asc';

function filasTabla() {
    return Array.from(document.querySelectorAll('#bancos-tbody tr:not(.empty-row)'));
}

function getFilteredRows() {
    const query = val('banco-search').toLowerCase().trim();
    return filasTabla().filter(fila => {
        const codigo = (fila.cells[0]?.textContent || '').toLowerCase();
        const nombre = (fila.cells[1]?.textContent || '').toLowerCase();
        const coincideTexto  = !query || codigo.includes(query) || nombre.includes(query);
        const coincideEstado = bancosFiltro === 'all' || fila.dataset.tipo === bancosFiltro;
        return coincideTexto && coincideEstado;
    });
}

function applyFilters() {
    bancosPage = 1;
    renderPage();
    const hayFiltro = val('banco-search').trim() !== '' || bancosFiltro !== 'all';
    const clearBtn  = document.getElementById('btn-clear-filters');
    if (clearBtn) clearBtn.style.display = hayFiltro ? 'flex' : 'none';
}

function setFiltro(filtro) {
    bancosFiltro = filtro;
    document.querySelectorAll('#mod-bancos .filter-toggle').forEach(b => {
        b.classList.toggle('active', b.dataset.filter === filtro);
    });
    applyFilters();
}

function clearFilters() {
    setVal('banco-search', '');
    setFiltro('all');
}

function renderPage() {
    const coinciden = getFilteredRows();
    filasTabla().forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = bancosPageSize === 'all';
    const size         = esTodos ? total : bancosPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    bancosPage = Math.min(Math.max(bancosPage, 1), totalPaginas);

    const start = esTodos ? 0 : (bancosPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    setText('bancos-count', `${total} resultado${total !== 1 ? 's' : ''}`);
    setText('bancos-range', total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`);

    const btnPrev = document.getElementById('bancos-prev');
    const btnNext = document.getElementById('bancos-next');
    if (btnPrev) btnPrev.disabled = bancosPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || bancosPage >= totalPaginas;
}

function sortRows(key, type) {
    const tbody = document.getElementById('bancos-tbody');
    const filas = filasTabla();
    if (!tbody || filas.length === 0) return;

    sortDir = (sortKey === key && sortDir === 'asc') ? 'desc' : 'asc';
    sortKey = key;

    const getValor = fila => {
        const celda = fila.cells[Number(key)];
        const base  = celda?.dataset.sort ?? celda?.textContent.trim() ?? '';
        return type === 'number' ? (parseFloat(base) || 0) : base.toLowerCase();
    };

    filas.sort((a, b) => {
        const va = getValor(a), vb = getValor(b);
        const cmp = type === 'number' ? (va - vb) : va.localeCompare(vb, 'es');
        return sortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-bancos .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${sortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    bancosPage = 1;
    renderPage();
}

function ajustarAlturaTabla() {
    const scrollBox = document.getElementById('bancos-table-scroll');
    if (!scrollBox) return;
    const footer = document.querySelector('#mod-bancos .table-footer');
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
// 7. INICIALIZACIÓN
// ============================================================
function initBancosModule() {
    if (!document.getElementById('mod-bancos')) return;

    // Mover modales y toast al <body> para que el overlay cubra también
    // la barra superior (escapan del contexto de apilamiento del layout)
    ['modal-new-banco', 'modal-edit-banco', 'modal-confirm-eliminar', 'toast'].forEach(id => {
        const el = document.getElementById(id);
        if (el && el.parentElement !== document.body) document.body.appendChild(el);
    });

    document.getElementById('btn-add-banco')?.addEventListener('click', openNewModal);

    // Filtros
    document.getElementById('banco-search')?.addEventListener('input', applyFilters);
    document.querySelectorAll('#mod-bancos .filter-toggle').forEach(btn => {
        btn.addEventListener('click', () => setFiltro(btn.dataset.filter));
    });
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // Paginación
    document.getElementById('bancos-page-size')?.addEventListener('change', function () {
        bancosPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        bancosPage = 1;
        renderPage();
    });
    document.getElementById('bancos-prev')?.addEventListener('click', () => { bancosPage--; renderPage(); });
    document.getElementById('bancos-next')?.addEventListener('click', () => { bancosPage++; renderPage(); });

    // Orden
    document.querySelectorAll('#mod-bancos .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortRows(th.dataset.sortKey, th.dataset.sortType));
    });

    renderPage();
    ajustarAlturaTabla();
    window.addEventListener('resize', ajustarAlturaTabla);

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
