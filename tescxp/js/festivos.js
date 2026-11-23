'use strict';

// ============================================================
// 1. HELPERS GENERALES (mismos que proveedores.js)
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

function clearFieldError(spanId) {
    const el = document.getElementById(spanId);
    if (!el) return;
    clearTimeout(el._hideTimer);
    el.classList.remove('visible');
    el.textContent = '';
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

function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function formatDate(isoStr) {
    if (!isoStr) return '—';
    const [y, m, d] = isoStr.split('-');
    return `${d}/${m}/${y}`;
}

// ============================================================
// 1.1 CALENDARIO PARA ELEGIR FECHAS (mismo estilo que Cronograma)
// ------------------------------------------------------------
// Reemplaza a los <input type="date">. A diferencia del calendario
// de Cronograma de Pagos, aquí NO se bloquean días de pago ni
// festivos: se puede elegir cualquier fecha. Solo se respeta el
// data-min / data-max del campo (el mismo min/max que ya tenía el
// input de fecha).
// La fecha se guarda en un <input type="hidden"> con el mismo id y
// name que antes, así que el envío del formulario no cambia.
// ============================================================
const MESES_DP = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
const DIAS_DP  = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

// Fecha local en 'YYYY-MM-DD' (toISOString usa UTC y en la noche
// de Colombia ya devolvería el día siguiente)
function isoLocal(fecha) {
    return `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}-${String(fecha.getDate()).padStart(2, '0')}`;
}

function hoyLocal() { return isoLocal(new Date()); }

function fechaISO(anio, mes, dia) {
    return `${anio}-${String(mes + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`;
}

function mesIndice(iso) {
    const [y, m] = iso.split('-').map(Number);
    return y * 12 + (m - 1);
}

// Los festivos ya registrados se resaltan en rosa (como en Cronograma),
// pero NO se bloquean: se pueden seleccionar igual.
function marcaFecha(iso) {
    const lista = (typeof festivosData !== 'undefined' && Array.isArray(festivosData)) ? festivosData : [];
    const festivo = lista.find(f => f.fecha === iso);
    return festivo ? { clase: 'festivo', info: `Festivo registrado: ${festivo.nom_festivo}` } : null;
}

const selectorFecha = {
    hiddenId: null,   // input hidden que recibe la fecha
    anio: 0,
    mes: 0,           // 0-11
    min: '',          // 'YYYY-MM-DD' o ''
    max: '',
};

function triggerFecha(hiddenId) { return document.getElementById(`${hiddenId}-btn`); }

function fueraDeRango(iso) {
    return (selectorFecha.min && iso < selectorFecha.min) || (selectorFecha.max && iso > selectorFecha.max);
}

// Muestra en el botón del campo la fecha elegida (o el texto vacío)
function pintarCampoFecha(hiddenId) {
    const btn   = triggerFecha(hiddenId);
    const texto = btn?.querySelector('.dp-trigger-texto');
    if (!texto) return;
    const fecha = val(hiddenId);
    if (fecha) {
        const [y, m, d] = fecha.split('-').map(Number);
        texto.textContent = btn.dataset.formato === 'corto'
            ? formatDate(fecha)
            : `${DIAS_DP[new Date(y, m - 1, d).getDay()]}, ${formatDate(fecha)}`;
        texto.classList.remove('vacio');
    } else {
        texto.textContent = btn.dataset.placeholder || 'Seleccione una fecha';
        texto.classList.add('vacio');
    }
}

// Asigna una fecha al campo y actualiza el botón. Con disparar = true
// emite 'change' (un input hidden no lo hace solo).
function setFecha(hiddenId, iso, disparar = false) {
    setVal(hiddenId, iso);
    pintarCampoFecha(hiddenId);
    if (disparar) {
        document.getElementById(hiddenId)?.dispatchEvent(new Event('change', { bubbles: true }));
    }
}

function abrirSelectorFecha(hiddenId) {
    const pop = document.getElementById('dp-pop');
    const btn = triggerFecha(hiddenId);
    if (!pop || !btn) return;

    document.querySelectorAll('.dp-trigger.abierto').forEach(b => b.classList.remove('abierto'));

    selectorFecha.hiddenId = hiddenId;
    selectorFecha.min = btn.dataset.min || '';
    selectorFecha.max = btn.dataset.max || '';

    // Se abre en el mes de la fecha elegida; si no hay, en el mes actual
    // (o en el límite más cercano si hoy queda fuera del rango)
    let base = val(hiddenId);
    if (!base) {
        base = hoyLocal();
        if (selectorFecha.min && base < selectorFecha.min) base = selectorFecha.min;
        if (selectorFecha.max && base > selectorFecha.max) base = selectorFecha.max;
    }
    const [y, m] = base.split('-').map(Number);
    selectorFecha.anio = y;
    selectorFecha.mes  = m - 1;

    btn.classList.add('abierto');
    pop.classList.remove('hidden');
    renderSelectorFecha();
    posicionarSelectorFecha();
}

function cerrarSelectorFecha() {
    document.getElementById('dp-pop')?.classList.add('hidden');
    document.querySelectorAll('.dp-trigger.abierto').forEach(b => b.classList.remove('abierto'));
    selectorFecha.hiddenId = null;
}

function selectorFechaAbierto() {
    const pop = document.getElementById('dp-pop');
    return !!pop && !pop.classList.contains('hidden');
}

// El calendario es position:fixed para que no lo recorte el scroll del modal
function posicionarSelectorFecha() {
    const pop = document.getElementById('dp-pop');
    const btn = triggerFecha(selectorFecha.hiddenId);
    if (!pop || !btn) return;

    const r = btn.getBoundingClientRect();
    const w = pop.offsetWidth;
    const h = pop.offsetHeight;

    let left = Math.min(r.left, window.innerWidth - w - 8);
    left = Math.max(8, left);

    let top = r.bottom + 6;
    if (top + h > window.innerHeight - 8) top = Math.max(8, r.top - h - 6); // si no cabe abajo, arriba

    pop.style.left = `${left}px`;
    pop.style.top  = `${top}px`;
}

function renderSelectorFecha() {
    const { anio, mes, hiddenId, min, max } = selectorFecha;
    const grid = document.getElementById('dp-grid');
    if (!grid) return;

    setText('dp-titulo', `${MESES_DP[mes]} ${anio}`);
    setText('dp-info', '');

    // Flechas: solo se deshabilitan si el campo tiene min/max
    const actual = anio * 12 + mes;
    const minMes = min ? mesIndice(min) : -Infinity;
    const maxMes = max ? mesIndice(max) : Infinity;
    const setDis = (id, dis) => { const b = document.getElementById(id); if (b) b.disabled = dis; };
    setDis('dp-prev-anio', actual <= minMes);
    setDis('dp-prev',      actual <= minMes);
    setDis('dp-next',      actual >= maxMes);
    setDis('dp-next-anio', actual >= maxMes);

    const seleccion = val(hiddenId);
    const hoy       = hoyLocal();
    const primerDia = new Date(anio, mes, 1).getDay(); // 0 = domingo
    const diasMes   = new Date(anio, mes + 1, 0).getDate();

    let html = '';
    for (let i = 0; i < primerDia; i++) html += '<span class="dp-dia vacio"></span>';

    for (let d = 1; d <= diasMes; d++) {
        const iso    = fechaISO(anio, mes, d);
        const fuera  = fueraDeRango(iso);
        const marca  = marcaFecha(iso);
        const clases = ['dp-dia'];
        let titulo   = '';
        let info     = '';

        if (fuera) { clases.push('fuera'); titulo = 'Fuera del rango permitido'; }
        if (marca) { clases.push(marca.clase); titulo = marca.info; info = marca.info; }
        if (iso === hoy)       clases.push('hoy');
        if (iso === seleccion) clases.push('sel');

        html += `<button type="button" class="${clases.join(' ')}" data-fecha="${iso}"
                    ${titulo ? `title="${escapeHtml(titulo)}"` : ''}
                    ${info ? `data-info="${escapeHtml(info)}"` : ''}
                    ${fuera ? 'disabled' : ''}>${d}</button>`;
    }
    grid.innerHTML = html;

    grid.querySelectorAll('.dp-dia:not(.vacio)').forEach(btn => {
        btn.addEventListener('mouseenter', () => setText('dp-info', btn.dataset.info || ''));
        if (!btn.disabled) {
            btn.addEventListener('click', () => elegirFechaSelector(btn.dataset.fecha));
        }
    });

    const btnHoy = document.getElementById('dp-hoy');
    if (btnHoy) btnHoy.disabled = !!fueraDeRango(hoy);
}

function elegirFechaSelector(iso) {
    const hiddenId = selectorFecha.hiddenId;
    if (!hiddenId) return;
    cerrarSelectorFecha();
    setFecha(hiddenId, iso, true);
}

function moverMesSelector(delta) {
    const { min, max } = selectorFecha;
    let total = selectorFecha.anio * 12 + selectorFecha.mes + delta;
    if (min) total = Math.max(total, mesIndice(min));
    if (max) total = Math.min(total, mesIndice(max));
    selectorFecha.anio = Math.floor(total / 12);
    selectorFecha.mes  = total % 12;
    renderSelectorFecha();
    posicionarSelectorFecha();
}

function initSelectorFecha() {
    document.querySelectorAll('.dp-trigger').forEach(btn => {
        pintarCampoFecha(btn.dataset.target);
        btn.addEventListener('click', e => {
            e.stopPropagation();
            const hiddenId = btn.dataset.target;
            if (selectorFechaAbierto() && selectorFecha.hiddenId === hiddenId) {
                cerrarSelectorFecha();
                return;
            }
            abrirSelectorFecha(hiddenId);
        });
    });

    document.getElementById('dp-prev')?.addEventListener('click', () => moverMesSelector(-1));
    document.getElementById('dp-next')?.addEventListener('click', () => moverMesSelector(1));
    document.getElementById('dp-prev-anio')?.addEventListener('click', () => moverMesSelector(-12));
    document.getElementById('dp-next-anio')?.addEventListener('click', () => moverMesSelector(12));

    document.getElementById('dp-hoy')?.addEventListener('click', () => elegirFechaSelector(hoyLocal()));
    document.getElementById('dp-borrar')?.addEventListener('click', () => {
        const hiddenId = selectorFecha.hiddenId;
        if (!hiddenId) return;
        cerrarSelectorFecha();
        setFecha(hiddenId, '', true);
    });

    // Cerrar al hacer clic por fuera o con Escape
    document.addEventListener('mousedown', e => {
        if (!selectorFechaAbierto()) return;
        if (e.target.closest('#dp-pop') || e.target.closest('.dp-trigger')) return;
        cerrarSelectorFecha();
    });
    document.addEventListener('keydown', e => {
        if (e.key === 'Escape' && selectorFechaAbierto()) {
            e.stopPropagation();
            cerrarSelectorFecha();
        }
    }, true);

    // Seguir al campo si se hace scroll dentro del modal o cambia el tamaño
    window.addEventListener('resize', () => { if (selectorFechaAbierto()) posicionarSelectorFecha(); });
    document.addEventListener('scroll', e => {
        if (selectorFechaAbierto() && !e.target.closest?.('#dp-pop')) posicionarSelectorFecha();
    }, true);
}

// ============================================================
// 2. MODAL: NUEVO FESTIVO
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    setFecha('new-festivo-fecha', '');
    setVal('new-festivo-nombre', '');
    show('modal-new-festivo');
}

function closeNewModal() {
    cerrarSelectorFecha();
    hide('modal-new-festivo');
}

// ============================================================
// 3. MODAL: EDITAR FESTIVO
// ============================================================
function openEditModal(festivo) {
    clearAllFieldErrors('edit');
    setVal('edit-festivo-id', festivo.id_festivo);
    setFecha('edit-festivo-fecha', festivo.fecha);
    setVal('edit-festivo-nombre', festivo.nom_festivo);
    show('modal-edit-festivo');
}

function closeEditModal() {
    cerrarSelectorFecha();
    hide('modal-edit-festivo');
}

// ============================================================
// 4. LISTA: INDICADORES, FILTROS, ORDEN Y PAGINADOR
// La tabla la pinta este archivo desde festivosData (PHP). Paginador y
// orden: componentes compartidos del ERP (erp_ui.js) — GUIA_PANTALLAS_ERP §4-§5.
// ============================================================
let pag = null, orden = null;
const normFes = t => (window.erpNormalizar ? erpNormalizar(t) : String(t ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim());
const datosFes = () => (Array.isArray(window.festivosData) ? window.festivosData : (typeof festivosData !== 'undefined' ? festivosData : []));

function updateStats() {
    const data  = datosFes();
    const hoy   = hoyLocal();
    const lim   = new Date(); lim.setDate(lim.getDate() + 30);
    const en30  = isoLocal(lim);
    const anio  = hoy.slice(0, 4);
    const futuros = data.filter(f => f.fecha >= hoy).sort((x, y) => x.fecha.localeCompare(y.fecha));
    setText('stat-total', data.length);
    setText('stat-proximos', futuros.filter(f => f.fecha <= en30).length);
    setText('stat-anio', data.filter(f => String(f.fecha).slice(0, 4) === anio).length);
    setText('stat-anio-hint', `Del año ${anio}`);
    if (futuros.length) {
        setText('stat-siguiente', formatDate(futuros[0].fecha).slice(0, 5));
        setText('stat-siguiente-hint', futuros[0].nom_festivo);
    } else {
        setText('stat-siguiente', '—');
        setText('stat-siguiente-hint', 'Sin festivos próximos');
    }
    setText('fes-cnt-all', data.length);
    setText('fes-cnt-proximos', futuros.length);
    setText('fes-cnt-pasados', data.length - futuros.length);
}

function prepararLista() {
    if (!pag && window.ErpPaginador) {
        pag = ErpPaginador.crear({ lista: document.getElementById('festivos-tbody'), onCambio: renderFestivos, tam: 25 });
    }
    if (!orden && window.ErpOrden) {
        orden = ErpOrden.crear({
            tabla: document.getElementById('festivos-table'),
            columnas: {
                'ID':                 { valor: f => Number(f.id_festivo), tipo: 'numero' },
                'Fecha':              { valor: f => f.fecha, tipo: 'fecha' },
                'Nombre del festivo': { valor: f => f.nom_festivo },
            },
            onCambio: () => { if (pag) pag.inicio(); renderFestivos(); },
        });
    }
}

function hayFiltros() {
    return val('festivo-search').trim() !== '' || (val('festivo-filtro-periodo') || 'all') !== 'all';
}

function getFilteredFestivos() {
    const q       = normFes(val('festivo-search'));
    const periodo = val('festivo-filtro-periodo') || 'all';
    const hoy     = hoyLocal();
    return datosFes().filter(f => {
        if (periodo === 'proximos' && f.fecha < hoy) return false;
        if (periodo === 'pasados' && f.fecha >= hoy) return false;
        if (q && !normFes(`${f.id_festivo} ${f.nom_festivo} ${formatDate(f.fecha)}`).includes(q)) return false;
        return true;
    });
}

function applyFilters() {
    if (pag) pag.inicio();
    renderFestivos();
}

function clearFilters() {
    setVal('festivo-search', '');
    setVal('festivo-filtro-periodo', 'all');
    if (window.ErpFiltros) ErpFiltros.sincronizar();
    applyFilters();
}

// Lista: filtrar → contar → ordenar → paginar → pintar
function renderFestivos() {
    prepararLista();
    let filas = getFilteredFestivos();
    setText('festivos-count', `${filas.length} resultado${filas.length !== 1 ? 's' : ''}`);
    const btnClear = document.getElementById('btn-clear-filters');
    if (btnClear) btnClear.hidden = !hayFiltros();

    const tbody = document.getElementById('festivos-tbody');
    if (!tbody) return;
    if (filas.length === 0) {
        const hayDatos = datosFes().length > 0;
        tbody.innerHTML = `<tr><td colspan="4"><div class="empty-state">
            <i class="fas ${hayDatos ? 'fa-search' : 'fa-calendar-times'}"></i>
            <p>${hayDatos ? 'Ningún festivo coincide con los filtros' : 'No hay festivos para mostrar'}</p>
            <span>${hayDatos ? 'Cambie la búsqueda o use «Limpiar»' : 'Use «Nuevo festivo» para registrar el primero'}</span>
        </div></td></tr>`;
        if (pag) pag.paginar([]);
        return;
    }
    if (orden) filas = orden.ordenar(filas);
    const pagina = pag ? pag.paginar(filas) : filas;
    tbody.innerHTML = pagina.map(f => {
        const id = escapeHtml(f.id_festivo);
        const nombre = escapeHtml(f.nom_festivo);
        return `<tr data-id="${id}">
            <td class="tcx-num"><span class="tcx-fuerte">#${id}</span></td>
            <td class="tcx-num">${escapeHtml(formatDate(f.fecha))}</td>
            <td>${nombre}</td>
            <td class="col-acciones">
                <div class="actions-cell">
                    <button type="button" class="btn-icon-sm edit" data-fes-accion="editar" title="Editar" aria-label="Editar ${nombre}"><i class="fas fa-pen"></i></button>
                    <button type="button" class="btn-icon-sm reject" data-fes-accion="eliminar" title="Eliminar" aria-label="Eliminar ${nombre}"><i class="fas fa-trash"></i></button>
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
// 5.1 ELIMINAR FESTIVO (función global)
// ============================================================
window.eliminarFestivo = function(id, nombre) {
    abrirConfirmEliminar(
        `Eliminar "${nombre}"`,
        `¿Desea eliminar el festivo "${nombre}"? Esta acción es reversible desde la base de datos.`,
        () => ejecutarEliminarFestivo(id)
    );
};

function ejecutarEliminarFestivo(id) {
    const formData = new FormData();
    formData.append('btn_eliminar', '1');
    formData.append('hid_del_id', id);
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
    initFestivoModule();
});

function initFestivoModule() {
    // Los modales los mueve a <body> el componente "modales" (erp_ui.js).
    // El calendario y el aviso se mueven aquí: así no los tapa el difuminado.
    ['dp-pop', 'toast'].forEach(id => {
        const el = document.getElementById(id);
        if (el && el.parentElement !== document.body) document.body.appendChild(el);
    });

    document.getElementById('btn-add-festivo')?.addEventListener('click', openNewModal);

    // ---------- CALENDARIO DE FECHAS ----------
    initSelectorFecha();

    document.getElementById('festivo-search')?.addEventListener('input', applyFilters);
    document.getElementById('festivo-filtro-periodo')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // Acciones de cada fila (sin onclick en línea)
    document.getElementById('festivos-tbody')?.addEventListener('click', e => {
        const b = e.target.closest('[data-fes-accion]');
        const tr = e.target.closest('tr[data-id]');
        if (!b || !tr) return;
        const f = datosFes().find(x => String(x.id_festivo) === tr.dataset.id);
        if (!f) return;
        if (b.dataset.fesAccion === 'editar') openEditModal(f);
        if (b.dataset.fesAccion === 'eliminar') window.eliminarFestivo(f.id_festivo, f.nom_festivo);
    });

    // ---------- LISTA ----------
    updateStats();
    renderFestivos();
    if (window.ErpListaFija) ErpListaFija.ajustar();
    const mod = document.getElementById('mod-festivos');
    requestAnimationFrame(() => requestAnimationFrame(() => mod?.classList.add('is-listo')));

    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));
    document.querySelectorAll('.btn-close-edit-modal, .btn-cancel-edit-modal')
        .forEach(btn => btn.addEventListener('click', closeEditModal));

    // Los modales NO se cierran al hacer clic por fuera (en el fondo oscuro):
    // así no se pierde lo que se lleva escrito en un formulario por un clic
    // accidental. Se cierran solo con la X, "Cancelar" o "Cerrar".

    // ---------- MODAL: CONFIRMAR ELIMINACIÓN ----------
    // Es de solo lectura: Esc lo cierra (los formularios solo con la X o Cancelar)
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape' || selectorFechaAbierto()) return;
        const m = document.getElementById('modal-confirm-eliminar');
        if (m && !m.classList.contains('hidden')) cerrarConfirmEliminar();
    });
    document.getElementById('confirm-eliminar-cancel-btn')?.addEventListener('click', cerrarConfirmEliminar);
    document.getElementById('confirm-eliminar-ok-btn')?.addEventListener('click', () => {
        const accion = _confirmDeleteAction;
        cerrarConfirmEliminar();
        if (typeof accion === 'function') accion();
    });

    // ---------- SUBMIT: NUEVO FESTIVO ----------
    document.getElementById('new-btn-save')?.addEventListener('click', async function() {
        const form = document.getElementById('new-festivo-form');
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

    // ---------- SUBMIT: EDITAR FESTIVO ----------
    document.getElementById('edit-btn-save')?.addEventListener('click', async function() {
        const form = document.getElementById('edit-festivo-form');
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
