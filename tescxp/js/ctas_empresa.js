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
    toast.style.background = type === 'error' ? '#ef4444' : '#0f172a';
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

window.openEditModal = openEditModal;

// ============================================================
// 4. FILTROS + PAGINACIÓN + ORDENAMIENTO (mismo sistema que Proveedores)
// ============================================================

// ---- ESTADO DE PAGINACIÓN ----
let cuentasPage     = 1;
let cuentasPageSize = 25; // debe coincidir con el <option selected> de #cuentas-page-size

// Filas que pasan la búsqueda y el filtro Todas/Corrientes/Ahorros (sin tener en cuenta la página)
function getFilteredCuentaRows() {
    const query  = val('cuenta-search').toLowerCase().trim();
    const active = document.querySelector('#mod-ctas-empresa .filter-toggle.active')?.dataset.filter ?? 'all';
    const filas  = Array.from(document.querySelectorAll('#cuentas-tbody tr:not(.empty-row)'));
    return filas.filter(fila => {
        const texto = [1, 2].map(i => fila.children[i]?.textContent.toLowerCase() ?? '').join(' ');
        const pasaTexto = !query || texto.includes(query);
        const pasaTipo  = active === 'all' || fila.dataset.tipo === active;
        return pasaTexto && pasaTipo;
    });
}

// Aplica búsqueda/tipo y vuelve a la primera página
function applyFilters() {
    cuentasPage = 1;
    renderCuentasPage();

    const query    = val('cuenta-search').trim();
    const active   = document.querySelector('#mod-ctas-empresa .filter-toggle.active')?.dataset.filter ?? 'all';
    const clearBtn = document.getElementById('btn-clear-filters');
    if (clearBtn) clearBtn.style.display = (query || active !== 'all') ? 'flex' : 'none';
}

function clearFilters() {
    setVal('cuenta-search', '');
    document.querySelectorAll('.filter-toggle').forEach(btn => btn.classList.remove('active'));
    document.querySelector('.filter-toggle[data-filter="all"]')?.classList.add('active');
    applyFilters();
}

// Muestra solo las filas que pasan el filtro Y caen en la página actual
function renderCuentasPage() {
    const todas     = Array.from(document.querySelectorAll('#cuentas-tbody tr:not(.empty-row)'));
    const coinciden = getFilteredCuentaRows();
    todas.forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = cuentasPageSize === 'all';
    const size         = esTodos ? total : cuentasPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    if (cuentasPage > totalPaginas) cuentasPage = totalPaginas;
    if (cuentasPage < 1) cuentasPage = 1;

    const start = esTodos ? 0 : (cuentasPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    setText('cuentas-count', `${total} resultado${total !== 1 ? 's' : ''}`);

    const rangeEl = document.getElementById('cuentas-range');
    if (rangeEl) {
        rangeEl.textContent = total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`;
    }

    const btnPrev = document.getElementById('cuentas-prev');
    const btnNext = document.getElementById('cuentas-next');
    if (btnPrev) btnPrev.disabled = cuentasPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || cuentasPage >= totalPaginas;
}

function initCuentasPagination() {
    document.getElementById('cuentas-page-size')?.addEventListener('change', function() {
        cuentasPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        cuentasPage = 1;
        renderCuentasPage();
    });
    document.getElementById('cuentas-prev')?.addEventListener('click', () => {
        cuentasPage--;
        renderCuentasPage();
    });
    document.getElementById('cuentas-next')?.addEventListener('click', () => {
        cuentasPage++;
        renderCuentasPage();
    });
}

// ---- ORDENAMIENTO ASC / DESC ----
// El texto se compara en español y con "numeric": los números de cuenta
// quedan en orden natural aunque tengan distinto largo (10 a 16 dígitos)
// y las tildes no descuadran los nombres.
let cuentasSortKey = null; // índice de columna, coincide con data-sort-key del <th>
let cuentasSortDir = 'asc';

function sortCuentaRows(key, type) {
    const tbody = document.getElementById('cuentas-tbody');
    if (!tbody) return;
    const filas = Array.from(tbody.querySelectorAll('tr:not(.empty-row)'));
    if (filas.length === 0) return;

    cuentasSortDir = (cuentasSortKey === key && cuentasSortDir === 'asc') ? 'desc' : 'asc';
    cuentasSortKey = key;

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
        return cuentasSortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-ctas-empresa .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${cuentasSortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    cuentasPage = 1;
    renderCuentasPage();
}

function initCuentasSorting() {
    document.querySelectorAll('#mod-ctas-empresa .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortCuentaRows(th.dataset.sortKey, th.dataset.sortType));
    });
}

// ---- ALTO DINÁMICO DE LA TABLA (evita el doble scroll) ----
function ajustarAlturaTablaCuentas() {
    const scrollBox = document.getElementById('cuentas-table-scroll');
    if (!scrollBox) return;
    const footer = document.querySelector('#mod-ctas-empresa .table-footer');
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
    document.getElementById('btn-add-cuenta')?.addEventListener('click', openNewModal);

    document.getElementById('cuenta-search')?.addEventListener('input', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    document.querySelectorAll('.filter-toggle').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('.filter-toggle').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            applyFilters();
        });
    });

    // ---------- PAGINACIÓN Y ORDENAMIENTO ----------
    initCuentasPagination();
    initCuentasSorting();
    renderCuentasPage();
    ajustarAlturaTablaCuentas();
    window.addEventListener('resize', ajustarAlturaTablaCuentas);

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
