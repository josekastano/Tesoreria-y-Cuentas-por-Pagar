'use strict';

// ============================================================
// 0. AISLAMIENTO DEL MÓDULO
// ============================================================
// archivo_plano.php referencia este archivo dos veces ($page_extra_js y el
// <script> del final). La IIFE le da a cada copia su propio ámbito y el guard
// de initArchivoModule() evita que los listeners se registren dos veces.
(function () {

// ============================================================
// 1. HELPERS GENERALES
// ============================================================
function val(id)           { return document.getElementById(id)?.value ?? ''; }
function setVal(id, value) { const el = document.getElementById(id); if (el) el.value = value ?? ''; }
function setText(id, text) { const el = document.getElementById(id); if (el) el.textContent = text ?? ''; }
function show(id)          { document.getElementById(id)?.classList.remove('hidden'); }
function hide(id)          { document.getElementById(id)?.classList.add('hidden'); }

function showFieldError(spanId, mensaje, autoHideMs = 6000) {
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
    toast._timer = setTimeout(() => toast.classList.add('hidden'), 4000);
}

function formatCurrency(n) { return '$' + Number(n || 0).toLocaleString('es-CO'); }

function formatDate(isoStr) {
    if (!isoStr) return '—';
    const [y, m, d] = String(isoStr).slice(0, 10).split('-');
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

function tipoCuentaTxt(valor) {
    return (valor === true || valor === 't' || valor === 'true' || valor === '1') ? 'Corriente' : 'Ahorros';
}

// POST al mismo PHP; devuelve el JSON o un error legible (y deja la causa en consola)
async function enviarPost(formData, etiqueta) {
    const response = await fetch(window.location.href, { method: 'POST', body: formData });
    const text = await response.text();
    let result;
    try {
        result = JSON.parse(text);
    } catch (e) {
        console.error(`[archivo_plano] Respuesta no JSON en ${etiqueta}:`, text);
        return { success: false, message: 'El servidor no devolvió JSON (revise la consola).' };
    }
    if (!result.success) {
        if (result.debug_origen)        console.error(`[archivo_plano] ${etiqueta} origen:`, result.debug_origen);
        if (result.debug_salida_previa) console.error(`[archivo_plano] ${etiqueta} salida previa:`, result.debug_salida_previa);
    }
    return result;
}


// ============================================================
// 1.1 CALENDARIO DE FECHA DE APLICACIÓN (mismo estilo que Festivos)
// ------------------------------------------------------------
// Solo se pueden elegir los días de pago de Parámetros de Tesorería
// (fec_diapago1..3: 1 = lunes ... 6 = sábado) que no sean festivo ni
// anteriores a hoy. Los festivos se ven en rosa con su nombre; los
// demás días quedan deshabilitados. La fecha se guarda en un
// <input type="hidden">, así el envío del formulario no cambia.
// El servidor y la base de datos vuelven a validar la misma regla.
// ============================================================
const MESES_DP = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
const DIAS_DP  = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

let calendarioPagos = { dias_pago: [], festivos: {} };

function cargarCalendarioPagos() {
    try {
        const el = document.getElementById('calendario-pagos-json');
        if (el) calendarioPagos = Object.assign(calendarioPagos, JSON.parse(el.textContent));
    } catch (e) {
        console.error('[archivo_plano] No se pudieron leer los días de pago:', e);
    }
}

// Fecha local en 'YYYY-MM-DD' (toISOString usa UTC y en la noche de
// Colombia ya devolvería el día siguiente)
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

// 1 = lunes ... 7 = domingo (igual que EXTRACT(ISODOW) y fec_diapagoN)
function diaISO(iso) {
    const [y, m, d] = iso.split('-').map(Number);
    const js = new Date(y, m - 1, d).getDay();
    return js === 0 ? 7 : js;
}

const NOMBRES_DIA_ISO = { 1: 'lunes', 2: 'martes', 3: 'miércoles', 4: 'jueves', 5: 'viernes', 6: 'sábado', 7: 'domingo' };

// Devuelve null si la fecha se puede elegir, o el motivo si no
function motivoFechaBloqueada(iso) {
    if (iso < hoyLocal()) return 'Fecha pasada';
    const festivo = calendarioPagos.festivos[iso];
    if (festivo) return `Festivo: ${festivo}`;
    if (!calendarioPagos.dias_pago.map(Number).includes(diaISO(iso))) {
        return `No es día de pago (${NOMBRES_DIA_ISO[diaISO(iso)]})`;
    }
    return null;
}

function proximaFechaValida() {
    const d = new Date();
    for (let i = 0; i < 120; i++) {
        const iso = isoLocal(d);
        if (motivoFechaBloqueada(iso) === null) return iso;
        d.setDate(d.getDate() + 1);
    }
    return '';
}

const selectorFecha = { hiddenId: null, anio: 0, mes: 0, min: '', max: '' };

function triggerFecha(hiddenId) { return document.getElementById(`${hiddenId}-btn`); }

function pintarCampoFecha(hiddenId) {
    const btn   = triggerFecha(hiddenId);
    const texto = btn?.querySelector('.dp-trigger-texto');
    if (!texto) return;
    const fecha = val(hiddenId);
    if (fecha) {
        const [y, m, d] = fecha.split('-').map(Number);
        texto.textContent = `${DIAS_DP[new Date(y, m - 1, d).getDay()]}, ${formatDate(fecha)}`;
        texto.classList.remove('vacio');
    } else {
        texto.textContent = 'Seleccione una fecha';
        texto.classList.add('vacio');
    }
}

function setFecha(hiddenId, iso, disparar = false) {
    setVal(hiddenId, iso);
    pintarCampoFecha(hiddenId);
    if (disparar) document.getElementById(hiddenId)?.dispatchEvent(new Event('change', { bubbles: true }));
}

function abrirSelectorFecha(hiddenId) {
    const pop = document.getElementById('dp-pop');
    const btn = triggerFecha(hiddenId);
    if (!pop || !btn) return;

    document.querySelectorAll('.dp-trigger.abierto').forEach(b => b.classList.remove('abierto'));
    selectorFecha.hiddenId = hiddenId;
    selectorFecha.min = btn.dataset.min || '';
    selectorFecha.max = btn.dataset.max || '';

    const base = val(hiddenId) || proximaFechaValida() || hoyLocal();
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

// position:fixed para que el scroll del modal no lo recorte
function posicionarSelectorFecha() {
    const pop = document.getElementById('dp-pop');
    const btn = triggerFecha(selectorFecha.hiddenId);
    if (!pop || !btn) return;
    const r = btn.getBoundingClientRect();
    let left = Math.max(8, Math.min(r.left, window.innerWidth - pop.offsetWidth - 8));
    let top  = r.bottom + 6;
    if (top + pop.offsetHeight > window.innerHeight - 8) top = Math.max(8, r.top - pop.offsetHeight - 6);
    pop.style.left = `${left}px`;
    pop.style.top  = `${top}px`;
}

function renderSelectorFecha() {
    const { anio, mes, hiddenId, min, max } = selectorFecha;
    const grid = document.getElementById('dp-grid');
    if (!grid) return;

    setText('dp-titulo', `${MESES_DP[mes]} ${anio}`);
    setText('dp-info', calendarioPagos.dias_pago.length ? '' : 'No hay días de pago configurados en Parámetros de Tesorería.');

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
        const iso     = fechaISO(anio, mes, d);
        const motivo  = motivoFechaBloqueada(iso);
        const festivo = calendarioPagos.festivos[iso];
        const clases  = ['dp-dia'];

        if (festivo && iso >= hoy) clases.push('festivo');
        else if (motivo)           clases.push('bloqueado');
        else                       clases.push('pago');
        if (iso === hoy)       clases.push('hoy');
        if (iso === seleccion) clases.push('sel');

        html += `<button type="button" class="${clases.join(' ')}" data-fecha="${iso}"
                    ${motivo ? `title="${escapeHtml(motivo)}" data-info="${escapeHtml(motivo)}" disabled` : 'data-info="Día de pago"'}>${d}</button>`;
    }
    grid.innerHTML = html;

    grid.querySelectorAll('.dp-dia:not(.vacio)').forEach(btn => {
        // Los botones deshabilitados no disparan mouseenter en todos los
        // navegadores: el motivo se lee desde el contenedor (ver initSelectorFecha)
        if (!btn.disabled) btn.addEventListener('click', () => elegirFechaSelector(btn.dataset.fecha));
    });

    const btnHoy = document.getElementById('dp-hoy');
    if (btnHoy) btnHoy.disabled = !proximaFechaValida();
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

    // Motivo del día bajo el mouse (funciona también con días deshabilitados)
    const grid = document.getElementById('dp-grid');
    grid?.addEventListener('mousemove', e => {
        const dia = e.target.closest('.dp-dia:not(.vacio)');
        setText('dp-info', dia ? (dia.dataset.info || '') : '');
    });
    grid?.addEventListener('mouseleave', () => setText('dp-info', ''));

    document.getElementById('dp-prev')?.addEventListener('click', () => moverMesSelector(-1));
    document.getElementById('dp-next')?.addEventListener('click', () => moverMesSelector(1));
    document.getElementById('dp-prev-anio')?.addEventListener('click', () => moverMesSelector(-12));
    document.getElementById('dp-next-anio')?.addEventListener('click', () => moverMesSelector(12));

    document.getElementById('dp-hoy')?.addEventListener('click', () => {
        const iso = proximaFechaValida();
        if (iso) elegirFechaSelector(iso);
    });
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

    window.addEventListener('resize', () => { if (selectorFechaAbierto()) posicionarSelectorFecha(); });
    document.addEventListener('scroll', e => {
        if (selectorFechaAbierto() && !e.target.closest?.('#dp-pop')) posicionarSelectorFecha();
    }, true);
}

// ============================================================
// 2. PROVEEDORES Y CUENTAS DEL CRONOGRAMA ELEGIDO
// ============================================================
// El servidor devuelve un arreglo de proveedores, cada uno con su tipo de
// documento (de tab_terceros), sus cuotas disponibles (las rechazadas vuelven
// con es_reintento = true) y sus cuentas activas. Por proveedor solo se elige
// la cuenta.
let proveedoresCronograma = [];

function setHint(texto) {
    const hint = document.getElementById('prov-cuentas-hint');
    if (!hint) return;
    hint.style.display = texto ? '' : 'none';
    hint.textContent = texto || '';
}

function limpiarProveedores() {
    proveedoresCronograma = [];
    setVal('hid-ctas-proveedor', '');
    const list  = document.getElementById('prov-cuentas-list');
    const total = document.getElementById('prov-cuentas-total');
    if (list)  { list.style.display = 'none';  list.innerHTML = ''; }
    if (total) { total.style.display = 'none'; total.innerHTML = ''; }
}

async function onCronogramaChange() {
    const idCronograma = val('new-id-cronograma');
    limpiarProveedores();

    if (!idCronograma) {
        setHint('Seleccione un cronograma para ver los proveedores a pagar.');
        return;
    }
    setHint('Cargando proveedores del cronograma...');

    const formData = new FormData();
    formData.append('btn_cargar_crono', '1');
    formData.append('hid_id_cronograma', idCronograma);

    try {
        const result = await enviarPost(formData, 'btn_cargar_crono');
        // Si el usuario cambió de cronograma mientras cargaba, se ignora esta respuesta
        if (val('new-id-cronograma') !== idCronograma) return;

        if (!result.success) {
            setHint('Error al cargar el cronograma: ' + (result.message || 'sin detalle del servidor.'));
            return;
        }
        if (!Array.isArray(result.proveedores) || result.proveedores.length === 0) {
            setHint('Este cronograma no tiene cuotas disponibles: ya están pagadas o en otro archivo plano que el banco no ha rechazado.');
            return;
        }

        proveedoresCronograma = result.proveedores;
        renderProveedorCuentas(proveedoresCronograma);
    } catch (err) {
        console.error('[archivo_plano] Error de red en btn_cargar_crono:', err);
        setHint('Error de conexión al cargar el cronograma.');
    }
}

function renderProveedorCuentas(proveedores) {
    const list  = document.getElementById('prov-cuentas-list');
    const total = document.getElementById('prov-cuentas-total');
    if (!list) return;

    const sinCuenta  = proveedores.filter(p => !p.cuentas || p.cuentas.length === 0);
    const reintentos = proveedores.reduce((n, p) => n + (p.cuotas || []).filter(c => c.es_reintento).length, 0);

    const avisos = [];
    if (sinCuenta.length > 0) {
        avisos.push(`${sinCuenta.length} proveedor(es) sin cuenta bancaria activa: regístrela en Bancos por Proveedor para poder crear el archivo.`);
    }
    if (reintentos > 0) {
        avisos.push(`${reintentos} cuota(s) son reintento de un pago rechazado: revise que la cuenta del proveedor sea la correcta.`);
    }
    setHint(avisos.join(' '));

    list.style.display = '';
    list.innerHTML = proveedores.map(p => {
        const cuentas = p.cuentas || [];
        const cuotas  = (p.cuotas || []).map(c =>
            `Fact. ${c.id_factura} · cuota ${c.id_cuota}` + (c.es_reintento ? ' <span class="tag-reintento">Reintento</span>' : '')
        ).join(', ');

        let cuentaHtml;
        if (cuentas.length === 0) {
            cuentaHtml = '<span class="picker-sin-cuenta">Sin cuenta bancaria activa</span>';
        } else if (cuentas.length === 1) {
            const c = cuentas[0];
            cuentaHtml = `<span class="picker-cuenta-unica">${escapeHtml(c.nom_banco)} — ${escapeHtml(c.cta_proveedor)} (${tipoCuentaTxt(c.ind_tipocuenta)})</span>`;
        } else {
            cuentaHtml = `
                <select class="form-select picker-select prov-cta-select" data-id-prov="${escapeHtml(p.id_proveedor)}" aria-label="Cuenta de ${escapeHtml(p.nom_tercero)}">
                    ${cuentas.map(c => `<option value="${escapeHtml(c.cta_proveedor)}">${escapeHtml(c.nom_banco)} — ${escapeHtml(c.cta_proveedor)} (${tipoCuentaTxt(c.ind_tipocuenta)})</option>`).join('')}
                </select>`;
        }

        return `
            <div class="cuota-picker-row${cuentas.length === 0 ? ' sin-cuenta' : ''}">
                <div class="cuota-picker-info">
                    <span class="cuota-picker-prov">${escapeHtml(p.nom_tercero)} <small>${escapeHtml(p.id_tipo)} ${escapeHtml(p.id_proveedor)}</small></span>
                    <span class="cuota-picker-fecha">${cuotas}</span>
                    <div class="picker-controles">${cuentaHtml}</div>
                </div>
                <span class="cuota-picker-valor">${formatCurrency(p.total)}</span>
            </div>
        `;
    }).join('');

    const cantCuotas = proveedores.reduce((n, p) => n + (p.cuotas || []).length, 0);
    const suma       = proveedores.reduce((n, p) => n + Number(p.total || 0), 0);
    if (total) {
        total.style.display = '';
        total.innerHTML = `<span>${cantCuotas} pago(s) a ${proveedores.length} proveedor(es)</span><strong>${formatCurrency(suma)}</strong>`;
    }

    list.querySelectorAll('.prov-cta-select').forEach(sel => {
        sel.addEventListener('change', buildCtasProveedorPayload);
    });

    buildCtasProveedorPayload();
}

// {"id_proveedor": {"cta": "..."}, ...}. Las cuotas y el tipo de documento
// no se envían: el servidor los vuelve a leer (cronograma y tab_terceros).
function buildCtasProveedorPayload() {
    const payload = {};
    proveedoresCronograma
        .filter(p => p.cuentas && p.cuentas.length > 0)
        .forEach(p => {
            const id  = String(p.id_proveedor);
            const cta = document.querySelector(`#prov-cuentas-list .prov-cta-select[data-id-prov="${CSS.escape(id)}"]`);
            payload[id] = { cta: cta ? cta.value : p.cuentas[0].cta_proveedor };
        });
    setVal('hid-ctas-proveedor', JSON.stringify(payload));
}

// ============================================================
// 3. MODAL: NUEVO ARCHIVO PLANO
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    setVal('new-cta-empresa', '');
    setVal('new-id-tipo-pago', '');
    // Fecha de aplicación: la próxima fecha válida (día de pago y no festivo)
    setFecha('new-fecha-aplicacion', proximaFechaValida() || '');
    setVal('new-nom-archivo', '');
    setVal('new-concepto', '');
    setVal('new-id-cronograma', '');
    mostrarEmpresaCuenta();

    // Si solo hay un tipo de pago, se deja elegido
    const tipoPago = document.getElementById('new-id-tipo-pago');
    if (tipoPago && tipoPago.options.length === 2) tipoPago.selectedIndex = 1;

    limpiarProveedores();
    setHint('Seleccione un cronograma para ver los proveedores a pagar.');
    show('modal-new-archivo');
}

// Nombre de la empresa (tab_pmtros_grales) de la cuenta de origen elegida.
// No se digita: el servidor lo vuelve a tomar de la base al crear el archivo.
function mostrarEmpresaCuenta() {
    const sel  = document.getElementById('new-cta-empresa');
    const info = document.getElementById('new-empresa-info');
    if (!sel || !info) return;
    const empresa = sel.selectedOptions[0]?.dataset.empresa || '';
    info.textContent = empresa;
    info.style.display = empresa ? '' : 'none';
}

function closeNewModal() {
    cerrarSelectorFecha();
    hide('modal-new-archivo');
}

// ============================================================
// 4. MODAL: EDITAR ARCHIVO PLANO (solo el nombre)
// ============================================================
function openEditModal(archivo) {
    if (archivo.generado) {
        showToast('El archivo plano ya fue generado y no se puede editar.', 'error');
        return;
    }
    clearAllFieldErrors('edit');
    setVal('edit-archivo-id', archivo.id_archivo_plano);
    setVal('edit-origen-display', `${archivo.nom_banco} — ${archivo.cta_empresa} (${archivo.tipo_cuenta})`);
    setVal('edit-nom-archivo', archivo.nom_archivo);
    show('modal-edit-archivo');
}

function closeEditModal() {
    hide('modal-edit-archivo');
}

// ============================================================
// 5. MODAL: DETALLE DE ARCHIVO PLANO
// ============================================================
let idArchivoDetalleActual = null;

// Respuesta del banco para una línea. Sin pago registrado = todavía sin respuesta.
function badgeEstadoPago(d) {
    switch (Number(d.estado_pago)) {
        case 2: return '<span class="badge badge-active">Aprobado</span>';
        case 3: return `<span class="badge badge-inactive" title="${escapeHtml((d.id_codigo || '') + ' ' + (d.des_motivo || ''))}">Rechazado</span>`;
        case 1: return '<span class="badge badge-pending">Pendiente</span>';
        default: return '<span class="badge badge-muted">Sin respuesta</span>';
    }
}

async function openDetailModal(archivo) {
    idArchivoDetalleActual = archivo.id_archivo_plano;

    setText('detail-title', archivo.nom_archivo);
    setText('detail-subtitle', `#${archivo.id_archivo_plano} — ${archivo.generado ? 'Generado' : 'Por generar'}`);

    document.getElementById('detail-content').innerHTML = `
        <div class="detail-grid">
            <div class="detail-item"><span class="detail-label">Empresa</span><span class="detail-value">${escapeHtml(archivo.nom_empresa)}<br><small>${escapeHtml(archivo.id_empresa)}</small></span></div>
            <div class="detail-item"><span class="detail-label">Cuenta de Origen</span><span class="detail-value">${escapeHtml(archivo.nom_banco)}<br><small>${escapeHtml(archivo.cta_empresa)} · ${escapeHtml(archivo.tipo_cuenta)}</small></span></div>
            <div class="detail-item"><span class="detail-label">Tipo de Pago</span><span class="detail-value">${escapeHtml(archivo.nom_tipo_pago)}</span></div>
            <div class="detail-item"><span class="detail-label">Fecha de Aplicación</span><span class="detail-value">${formatDate(archivo.fecha_aplicacion)}</span></div>
            <div class="detail-item"><span class="detail-label">Fecha de Generación</span><span class="detail-value">${formatDate(archivo.fec_generacion)}</span></div>
            <div class="detail-item"><span class="detail-label">Total</span><span class="detail-value" id="detail-total">—</span></div>
        </div>
    `;

    show('modal-detail');

    const detalleList = document.getElementById('detalle-pagos-list');
    detalleList.innerHTML = '<div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>Cargando...</p></div>';

    const formData = new FormData();
    formData.append('btn_ver_detalle', '1');
    formData.append('hid_id_archivo_plano', archivo.id_archivo_plano);

    try {
        const result = await enviarPost(formData, 'btn_ver_detalle');
        if (!result.success) {
            detalleList.innerHTML = `<p class="detalle-msg error">${escapeHtml(result.message || 'Error al cargar el detalle.')}</p>`;
            return;
        }
        const detalle = result.detalle || [];
        if (detalle.length === 0) {
            detalleList.innerHTML = '<p class="detalle-msg">Este archivo no tiene pagos.</p>';
            return;
        }

        setText('detail-total', `${formatCurrency(detalle.reduce((n, d) => n + Number(d.val_a_pagar || 0), 0))} (${detalle.length} pago${detalle.length !== 1 ? 's' : ''})`);

        detalleList.innerHTML = detalle.map(d => `
            <div class="cuota-row">
                <span class="cuota-num">
                    ${escapeHtml(d.nom_tercero)}
                    <small>${escapeHtml(d.id_tipo)} ${escapeHtml(d.id_proveedor)} · ${escapeHtml(d.nom_banco)} ${escapeHtml(d.cta_proveedor)} (${escapeHtml(d.tipo_cuenta)})</small>
                    <small>Fact. ${escapeHtml(d.id_factura)} · cuota ${escapeHtml(d.id_cuota)}${d.concepto ? ' · ' + escapeHtml(d.concepto) : ''}</small>
                    ${Number(d.estado_pago) === 3 && d.des_motivo ? `<small class="motivo-rechazo">${escapeHtml(d.id_codigo)}: ${escapeHtml(d.des_motivo)}</small>` : ''}
                </span>
                ${badgeEstadoPago(d)}
                <span class="cuota-valor">${formatCurrency(d.val_a_pagar)}</span>
            </div>
        `).join('');
    } catch (err) {
        detalleList.innerHTML = '<p class="detalle-msg error">Error de conexión al cargar el detalle.</p>';
    }
}

function closeDetailModal() {
    hide('modal-detail');
}

// ============================================================
// 5.1 DESCARGA DEL ARCHIVO PLANO (CSV)
// ============================================================
// Si el servidor pudo armar el CSV responde text/csv y se descarga como blob;
// si algo falló responde JSON y se muestra el mensaje.
async function descargarArchivoPlano(id) {
    if (!id) return;

    const formData = new FormData();
    formData.append('btn_descargar_archivo_plano', '1');
    formData.append('hid_id_archivo_plano', id);

    try {
        const response = await fetch(window.location.href, { method: 'POST', body: formData });
        const contentType = response.headers.get('Content-Type') || '';

        if (contentType.includes('application/json')) {
            let result;
            try { result = await response.json(); } catch (e) { result = {}; }
            console.error('[archivo_plano] btn_descargar_archivo_plano falló:', result);
            showToast(result.message || 'No se pudo descargar el archivo.', 'error');
            return;
        }
        if (!response.ok) {
            showToast('No se pudo descargar el archivo (error del servidor).', 'error');
            return;
        }

        const blob = await response.blob();
        let nombreArchivo = `archivo_plano_${id}.csv`;
        const match = (response.headers.get('Content-Disposition') || '').match(/filename="?([^"]+)"?/);
        if (match && match[1]) nombreArchivo = match[1].trim();

        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = nombreArchivo;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);

        showToast('Archivo plano descargado correctamente.');
        // La primera descarga lo marca como generado: se refresca la tabla
        setTimeout(() => location.reload(), 600);
    } catch (err) {
        console.error('[archivo_plano] Error de red al descargar:', err);
        showToast('Error de conexión al descargar el archivo.', 'error');
    }
}

// ============================================================
// 6. FILTROS + PAGINACIÓN + ORDENAMIENTO (mismo sistema que Proveedores)
// ============================================================
let archivosPage     = 1;
let archivosPageSize = 25; // debe coincidir con el <option selected> de #archivos-page-size

function getFilteredArchivoRows() {
    const query  = val('archivo-search').toLowerCase().trim();
    const active = document.querySelector('#mod-archivo-plano .filter-toggle.active')?.dataset.filter ?? 'all';
    const filas  = Array.from(document.querySelectorAll('#archivos-tbody tr:not(.empty-row)'));
    return filas.filter(fila => {
        const texto = [0, 1, 2].map(i => (fila.children[i]?.textContent ?? '').toLowerCase()).join(' ');
        const pasaTexto  = !query || texto.includes(query);
        const pasaEstado = active === 'all' || fila.dataset.estado === active;
        return pasaTexto && pasaEstado;
    });
}

function applyFilters() {
    archivosPage = 1;
    renderArchivosPage();

    const query    = val('archivo-search').trim();
    const active   = document.querySelector('#mod-archivo-plano .filter-toggle.active')?.dataset.filter ?? 'all';
    const clearBtn = document.getElementById('btn-clear-filters');
    if (clearBtn) clearBtn.style.display = (query || active !== 'all') ? 'flex' : 'none';
}

function clearFilters() {
    setVal('archivo-search', '');
    document.querySelectorAll('#mod-archivo-plano .filter-toggle').forEach(btn => btn.classList.remove('active'));
    document.querySelector('#mod-archivo-plano .filter-toggle[data-filter="all"]')?.classList.add('active');
    applyFilters();
}

function renderArchivosPage() {
    const todas     = Array.from(document.querySelectorAll('#archivos-tbody tr:not(.empty-row)'));
    const coinciden = getFilteredArchivoRows();
    todas.forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = archivosPageSize === 'all';
    const size         = esTodos ? total : archivosPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    if (archivosPage > totalPaginas) archivosPage = totalPaginas;
    if (archivosPage < 1) archivosPage = 1;

    const start = esTodos ? 0 : (archivosPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    setText('archivos-count', `${total} resultado${total !== 1 ? 's' : ''}`);

    const rangeEl = document.getElementById('archivos-range');
    if (rangeEl) rangeEl.textContent = total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`;

    const btnPrev = document.getElementById('archivos-prev');
    const btnNext = document.getElementById('archivos-next');
    if (btnPrev) btnPrev.disabled = archivosPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || archivosPage >= totalPaginas;
}

function initArchivosPagination() {
    document.getElementById('archivos-page-size')?.addEventListener('change', function() {
        archivosPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        archivosPage = 1;
        renderArchivosPage();
    });
    document.getElementById('archivos-prev')?.addEventListener('click', () => { archivosPage--; renderArchivosPage(); });
    document.getElementById('archivos-next')?.addEventListener('click', () => { archivosPage++; renderArchivosPage(); });
}

// ---- ORDENAMIENTO ASC / DESC ----
// Las fechas van en data-sort como 'YYYY-MM-DD'; sin fecha quedan al principio (asc).
let archivosSortKey = null;
let archivosSortDir = 'asc';

function sortArchivoRows(key, type) {
    const tbody = document.getElementById('archivos-tbody');
    if (!tbody) return;
    const filas = Array.from(tbody.querySelectorAll('tr:not(.empty-row)'));
    if (filas.length === 0) return;

    archivosSortDir = (archivosSortKey === key && archivosSortDir === 'asc') ? 'desc' : 'asc';
    archivosSortKey = key;

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
        return archivosSortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-archivo-plano .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${archivosSortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    archivosPage = 1;
    renderArchivosPage();
}

function initArchivosSorting() {
    document.querySelectorAll('#mod-archivo-plano .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortArchivoRows(th.dataset.sortKey, th.dataset.sortType));
    });
}

// ---- ALTO DINÁMICO DE LA TABLA (evita el doble scroll) ----
function ajustarAlturaTablaArchivos() {
    const scrollBox = document.getElementById('archivos-table-scroll');
    if (!scrollBox) return;
    const footer = document.querySelector('#mod-archivo-plano .table-footer');
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
// 7. INICIALIZACIÓN GENERAL
// ============================================================
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initArchivoModule);
} else {
    initArchivoModule();
}

function initArchivoModule() {
    if (window.__archivoPlanoInit) return;
    window.__archivoPlanoInit = true;

    cargarCalendarioPagos();
    initSelectorFecha();

    document.getElementById('btn-add-archivo')?.addEventListener('click', openNewModal);
    document.getElementById('archivo-search')?.addEventListener('input', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    document.querySelectorAll('#mod-archivo-plano .filter-toggle').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('#mod-archivo-plano .filter-toggle').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            applyFilters();
        });
    });

    // ---------- CLIC EN LA TABLA ----------
    // Los datos de cada archivo van en data-archivo (JSON). Clic en la fila =
    // detalle; los botones de acciones hacen lo suyo sin abrir el detalle.
    document.getElementById('archivos-tbody')?.addEventListener('click', function(e) {
        const fila = e.target.closest('tr[data-archivo]');
        if (!fila) return;
        let archivo;
        try { archivo = JSON.parse(fila.dataset.archivo); } catch (err) { return; }

        const btn = e.target.closest('button[data-action]');
        if (btn) {
            if (btn.dataset.action === 'descargar') descargarArchivoPlano(archivo.id_archivo_plano);
            if (btn.dataset.action === 'editar')    openEditModal(archivo);
            return;
        }
        if (e.target.closest('.accion-bloqueada')) return;
        openDetailModal(archivo);
    });

    // ---------- PAGINACIÓN Y ORDENAMIENTO ----------
    initArchivosPagination();
    initArchivosSorting();
    renderArchivosPage();
    ajustarAlturaTablaArchivos();
    window.addEventListener('resize', ajustarAlturaTablaArchivos);

    document.getElementById('new-id-cronograma')?.addEventListener('change', onCronogramaChange);
    document.getElementById('new-cta-empresa')?.addEventListener('change', mostrarEmpresaCuenta);

    // Al corregir un campo se borra su mensaje de error
    ['new-archivo-form', 'edit-archivo-form'].forEach(formId => {
        const form = document.getElementById(formId);
        const limpiar = e => {
            const err = e.target.closest('.form-field')?.querySelector('.field-error');
            if (err) { clearTimeout(err._hideTimer); err.classList.remove('visible'); err.textContent = ''; }
        };
        form?.addEventListener('input', limpiar);
        form?.addEventListener('change', limpiar);
    });

    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));
    document.querySelectorAll('.btn-close-edit-modal, .btn-cancel-edit-modal')
        .forEach(btn => btn.addEventListener('click', closeEditModal));

    document.getElementById('close-detail-modal')?.addEventListener('click', closeDetailModal);
    document.getElementById('close-detail-btn')?.addEventListener('click', closeDetailModal);
    document.getElementById('detail-btn-download')?.addEventListener('click', () => descargarArchivoPlano(idArchivoDetalleActual));

    // Los modales NO se cierran al hacer clic por fuera: así no se pierde lo
    // escrito por un clic accidental. Se cierran con la X, "Cancelar" o "Cerrar".

    // ---------- SUBMIT: NUEVO ARCHIVO PLANO ----------
    document.getElementById('new-btn-save')?.addEventListener('click', async function() {
        const btn = this;
        if (btn.disabled) return; // evita doble envío por doble clic
        btn.disabled = true;
        clearAllFieldErrors('new');

        try {
            buildCtasProveedorPayload();
        } catch (e) {
            // No aborta: el servidor usa la primera cuenta activa y NIT
            console.error('[archivo_plano] No se pudo armar la selección de cuentas:', e);
        }

        try {
            const result = await enviarPost(new FormData(document.getElementById('new-archivo-form')), 'btn_nuevo');
            if (result.success) {
                showToast(result.message, 'success');
                closeNewModal();
                setTimeout(() => location.reload(), 800);
            } else if (result.errors && Object.keys(result.errors).length > 0) {
                Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
            } else {
                showToast(result.message || 'Error al crear el archivo', 'error');
            }
        } catch (err) {
            showToast('Error de conexión', 'error');
        } finally {
            btn.disabled = false;
        }
    });

    // ---------- SUBMIT: EDITAR ARCHIVO PLANO ----------
    document.getElementById('edit-btn-save')?.addEventListener('click', async function() {
        clearAllFieldErrors('edit');
        try {
            const result = await enviarPost(new FormData(document.getElementById('edit-archivo-form')), 'btn_editar');
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
}

})();
