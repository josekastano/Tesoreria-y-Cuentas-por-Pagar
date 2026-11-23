'use strict';

// ============================================================
// 0. AISLAMIENTO DEL MÓDULO
// ============================================================
// La IIFE le da al archivo su propio ámbito y el guard de initArchivoModule()
// evita que los listeners se registren dos veces si se carga de nuevo.
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
    toast.classList.toggle('toast-error', type === 'error');
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

// Cuentas a dejar elegidas la próxima vez que se pinte la lista
// ({"id_proveedor": "cta"}): se usa al recargar el cronograma después de
// crear una cuenta, para no perder lo que el usuario ya había escogido.
let seleccionPendiente = null;

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
        avisos.push(`${sinCuenta.length} proveedor(es) sin cuenta bancaria activa: use "+ Cuenta" en su fila para registrarla sin salir del archivo.`);
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
                <select class="form-input picker-select prov-cta-select" data-id-prov="${escapeHtml(p.id_proveedor)}" aria-label="Cuenta de ${escapeHtml(p.nom_tercero)}">
                    ${cuentas.map(c => `<option value="${escapeHtml(c.cta_proveedor)}">${escapeHtml(c.nom_banco)} — ${escapeHtml(c.cta_proveedor)} (${tipoCuentaTxt(c.ind_tipocuenta)})</option>`).join('')}
                </select>`;
        }

        // Crear una cuenta para este proveedor sin salir del archivo
        cuentaHtml += `
            <button type="button" class="btn-link-inline picker-add-cta" data-action="add-cta"
                    data-id-prov="${escapeHtml(p.id_proveedor)}"
                    data-nom-prov="${escapeHtml(p.nom_tercero)}"
                    title="Registrar una cuenta bancaria para ${escapeHtml(p.nom_tercero)}">
                <i class="fas fa-plus"></i> Cuenta
            </button>`;

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
        // Recupera la cuenta que estaba elegida (o la recién creada)
        const preferida = seleccionPendiente?.[sel.dataset.idProv];
        if (preferida && Array.from(sel.options).some(o => o.value === preferida)) sel.value = preferida;
        sel.addEventListener('change', buildCtasProveedorPayload);
    });
    seleccionPendiente = null;

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
    // Fecha de aplicación: la próxima fecha válida (día de pago y no festivo)
    setFecha('new-fecha-aplicacion', proximaFechaValida() || '');
    setVal('new-nom-archivo', '');
    setVal('new-concepto', '');
    setVal('new-id-cronograma', '');
    mostrarEmpresaCuenta();

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
    closeBancoRapidoModal();
    closeCtaEmpRapida();
    closeCtaProvRapida();
    hide('modal-new-archivo');
}

// ============================================================
// 3.1 MODALES RÁPIDOS: NUEVA CUENTA (EMPRESA / PROVEEDOR) Y NUEVO BANCO
// ------------------------------------------------------------
// Se abren encima de "Nuevo Archivo Plano" para no perder lo que ya se
// llevaba diligenciado. El de banco lo comparten los dos modales de cuenta:
// el banco creado queda en todos los selects de banco y seleccionado en el
// modal que lo pidió (bancoDestino).
// ============================================================
let bancoDestino = null;

function limpiarErrorCampo(spanId) {
    const el = document.getElementById(spanId);
    if (el) { clearTimeout(el._hideTimer); el.classList.remove('visible'); el.textContent = ''; }
}

// Respuesta del servidor con errores por campo o mensaje general
function mostrarResultadoError(result, porDefecto) {
    if (result.errors && Object.keys(result.errors).length > 0) {
        Object.entries(result.errors).forEach(([spanId, mensaje]) => showFieldError(spanId, mensaje));
    } else {
        showToast(result.message || porDefecto, 'error');
    }
}

// ¿El select de banco tiene al menos un banco para escoger?
function selectTieneBancos(sel) {
    return !!sel && Array.from(sel.options).some(o => o.value !== '');
}

function actualizarPlaceholdersBanco() {
    document.querySelectorAll('.select-banco').forEach(sel => {
        const ph = sel.querySelector('option[value=""]');
        if (ph) ph.textContent = selectTieneBancos(sel) ? 'Seleccione...' : 'No hay bancos registrados';
    });
}

// ---------- NUEVO BANCO ----------
function openBancoRapidoModal(destino) {
    bancoDestino = destino || null;
    clearAllFieldErrors('banco');
    setVal('banco-rapido-id', '');
    setVal('banco-rapido-nombre', '');
    show('modal-banco-rapido');
    setTimeout(() => document.getElementById('banco-rapido-id')?.focus(), 50);
}

function closeBancoRapidoModal() {
    hide('modal-banco-rapido');
}

// Agrega el banco a todos los selects de banco, en orden alfabético
function agregarBancoASelects(banco) {
    document.querySelectorAll('.select-banco').forEach(sel => {
        if (Array.from(sel.options).some(o => o.value === banco.id_banco)) return;
        const opt = document.createElement('option');
        opt.value = banco.id_banco;
        opt.textContent = banco.nom_banco;
        const siguiente = Array.from(sel.options).find(o =>
            o.value !== '' && o.textContent.localeCompare(banco.nom_banco, 'es', { sensitivity: 'base' }) > 0
        );
        sel.insertBefore(opt, siguiente || null);
    });
    actualizarPlaceholdersBanco();
}

async function guardarBancoRapido() {
    const btn = document.getElementById('banco-rapido-save');
    if (btn?.disabled) return;
    clearAllFieldErrors('banco');
    if (btn) btn.disabled = true;

    try {
        const result = await enviarPost(new FormData(document.getElementById('banco-rapido-form')), 'btn_nuevo_banco');
        if (result.success && result.banco) {
            agregarBancoASelects(result.banco);
            if (bancoDestino) {
                setVal(bancoDestino, result.banco.id_banco);
                limpiarErrorCampo(`err-${bancoDestino}`);
            }
            closeBancoRapidoModal();
            showToast(result.message, 'success');
        } else {
            mostrarResultadoError(result, 'Error al guardar el banco');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    } finally {
        if (btn) btn.disabled = false;
    }
}

// ---------- NUEVA CUENTA DE ORIGEN (EMPRESA) ----------
function openCtaEmpRapida() {
    cerrarSelectorFecha();
    clearAllFieldErrors('ctaemp');
    setVal('ctaemp-banco', '');
    setVal('ctaemp-cta', '');
    setVal('ctaemp-tipocuenta', 'false');
    show('modal-ctaemp-rapida');
}

function closeCtaEmpRapida() {
    hide('modal-ctaemp-rapida');
}

// Agrega la cuenta al select de cuenta de origen y la deja elegida
function agregarCuentaOrigen(c) {
    const sel = document.getElementById('new-cta-empresa');
    if (!sel) return;
    const valor = `${c.id_empresa}:${c.cta_empresa}`;
    let opt = Array.from(sel.options).find(o => o.value === valor);
    if (!opt) {
        opt = document.createElement('option');
        opt.value = valor;
        opt.dataset.empresa = c.nom_empresa ? `${c.nom_empresa} · ${c.id_empresa}` : c.id_empresa;
        opt.textContent = `${c.nom_banco} — ${c.cta_empresa} (${c.tipo_cuenta})`;
        sel.appendChild(opt);
    }
    const ph = sel.querySelector('option[value=""]');
    if (ph) ph.textContent = 'Seleccione...';
    sel.value = valor;
    mostrarEmpresaCuenta();
    limpiarErrorCampo('err-new-cuenta-empresa');
}

async function guardarCtaEmpRapida() {
    const btn = document.getElementById('ctaemp-rapida-save');
    if (btn?.disabled) return;
    clearAllFieldErrors('ctaemp');
    if (btn) btn.disabled = true;

    try {
        const result = await enviarPost(new FormData(document.getElementById('ctaemp-rapida-form')), 'btn_nueva_cta_empresa');
        if (result.success && result.cuenta) {
            agregarCuentaOrigen(result.cuenta);
            closeCtaEmpRapida();
            showToast(result.message, 'success');
        } else {
            mostrarResultadoError(result, 'Error al guardar la cuenta');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    } finally {
        if (btn) btn.disabled = false;
    }
}

// ---------- NUEVA CUENTA DE PROVEEDOR ----------
function openCtaProvRapida(idProveedor, nomProveedor) {
    clearAllFieldErrors('ctaprov');
    setVal('ctaprov-proveedor-hid', idProveedor);
    setVal('ctaprov-proveedor-display', `${nomProveedor} — ${idProveedor}`);
    setVal('ctaprov-banco', '');
    setVal('ctaprov-cta', '');
    setVal('ctaprov-tipocuenta', 'false');
    show('modal-ctaprov-rapida');
}

function closeCtaProvRapida() {
    hide('modal-ctaprov-rapida');
}

async function guardarCtaProvRapida() {
    const btn = document.getElementById('ctaprov-rapida-save');
    if (btn?.disabled) return;
    clearAllFieldErrors('ctaprov');
    if (btn) btn.disabled = true;

    try {
        const result = await enviarPost(new FormData(document.getElementById('ctaprov-rapida-form')), 'btn_nueva_cta_proveedor');
        if (result.success && result.cuenta) {
            // Se recarga el cronograma conservando las cuentas ya elegidas
            // y dejando elegida la nueva para este proveedor.
            buildCtasProveedorPayload();
            let actuales = {};
            try {
                const payload = JSON.parse(val('hid-ctas-proveedor') || '{}');
                Object.entries(payload).forEach(([id, v]) => { actuales[id] = v.cta; });
            } catch (e) { actuales = {}; }
            actuales[String(result.cuenta.id_proveedor)] = String(result.cuenta.cta_proveedor);
            seleccionPendiente = actuales;

            closeCtaProvRapida();
            showToast(result.message, 'success');
            limpiarErrorCampo('err-new-cronograma');
            await onCronogramaChange();
        } else {
            mostrarResultadoError(result, 'Error al guardar la cuenta');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    } finally {
        if (btn) btn.disabled = false;
    }
}

function initModalesRapidos() {
    // Abrir
    document.getElementById('btn-open-ctaemp-rapida')?.addEventListener('click', openCtaEmpRapida);
    document.querySelectorAll('.btn-open-banco-rapido').forEach(btn =>
        btn.addEventListener('click', () => openBancoRapidoModal(btn.dataset.destino)));

    // Si un select de banco está vacío, al intentar abrirlo se abre "Nuevo banco"
    document.querySelectorAll('.select-banco').forEach(sel => {
        sel.addEventListener('mousedown', e => {
            if (!selectTieneBancos(sel)) { e.preventDefault(); openBancoRapidoModal(sel.id); }
        });
        sel.addEventListener('keydown', e => {
            if (!selectTieneBancos(sel) && ['Enter', ' ', 'ArrowDown', 'ArrowUp'].includes(e.key)) {
                e.preventDefault();
                openBancoRapidoModal(sel.id);
            }
        });
    });

    // Si no hay cuentas de origen, el select abre "Nueva cuenta"
    const selOrigen = document.getElementById('new-cta-empresa');
    const sinCuentas = () => !Array.from(selOrigen?.options || []).some(o => o.value !== '');
    selOrigen?.addEventListener('mousedown', e => {
        if (sinCuentas()) { e.preventDefault(); openCtaEmpRapida(); }
    });

    // "+ Cuenta" en las filas de proveedores (la lista se repinta: delegación)
    document.getElementById('prov-cuentas-list')?.addEventListener('click', e => {
        const btn = e.target.closest('button[data-action="add-cta"]');
        if (btn) openCtaProvRapida(btn.dataset.idProv, btn.dataset.nomProv);
    });

    // Cerrar
    document.querySelectorAll('.btn-close-banco-modal, .btn-cancel-banco-modal')
        .forEach(btn => btn.addEventListener('click', closeBancoRapidoModal));
    document.querySelectorAll('.btn-close-ctaemp-modal, .btn-cancel-ctaemp-modal')
        .forEach(btn => btn.addEventListener('click', closeCtaEmpRapida));
    document.querySelectorAll('.btn-close-ctaprov-modal, .btn-cancel-ctaprov-modal')
        .forEach(btn => btn.addEventListener('click', closeCtaProvRapida));

    // Guardar (botón o Enter dentro del formulario)
    [
        ['banco-rapido-save', 'banco-rapido-form', guardarBancoRapido],
        ['ctaemp-rapida-save', 'ctaemp-rapida-form', guardarCtaEmpRapida],
        ['ctaprov-rapida-save', 'ctaprov-rapida-form', guardarCtaProvRapida],
    ].forEach(([btnId, formId, accion]) => {
        document.getElementById(btnId)?.addEventListener('click', accion);
        document.getElementById(formId)?.addEventListener('submit', e => { e.preventDefault(); accion(); });
    });

    actualizarPlaceholdersBanco();
}

// ============================================================
// 4. MODAL: EDITAR ARCHIVO PLANO
// ------------------------------------------------------------
// Proveedores: solo el nombre. Nómina e inversiones: nombre, cuenta de origen
// y fecha de aplicación (el módulo que lo envió no elige de qué cuenta sale el
// dinero). Esos campos se deshabilitan cuando no aplican, así no viajan en el POST.
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

    const esNomina   = !!archivo.es_externo;   // nómina o inversiones
    const camposNom  = document.getElementById('edit-nomina-campos');
    const origenFijo = document.getElementById('edit-origen-fijo');
    const selCta     = document.getElementById('edit-cta-empresa');
    const hidFecha   = document.getElementById('edit-fecha-aplicacion');

    if (camposNom)  camposNom.style.display  = esNomina ? '' : 'none';
    if (origenFijo) origenFijo.style.display = esNomina ? 'none' : '';
    if (selCta)     selCta.disabled   = !esNomina;
    if (hidFecha)   hidFecha.disabled = !esNomina;

    setText('edit-subtitulo', esNomina
        ? 'Elija de qué cuenta sale el pago y cuándo se aplica'
        : 'Solo se puede cambiar el nombre mientras no se haya generado');

    if (esNomina) {
        setText('edit-nomina-periodo', `${archivo.periodo_nomina} — enviado por el módulo ${archivo.es_inversion ? 'Financiero' : 'de Nómina'}.`);
        if (selCta) selCta.value = archivo.cta_combo || '';
        // Si la fecha que puso Nómina ya pasó o no es válida, se propone la próxima válida
        const fecha = archivo.fecha_aplicacion && !motivoFechaBloqueada(archivo.fecha_aplicacion)
            ? archivo.fecha_aplicacion
            : proximaFechaValida();
        setFecha('edit-fecha-aplicacion', fecha || '');
    }

    show('modal-edit-archivo');
}

function closeEditModal() {
    cerrarSelectorFecha();
    hide('modal-edit-archivo');
}

// ============================================================
// 4.1 DEVOLVER UN ARCHIVO A NÓMINA O A FINANCIERO (solo si no se ha descargado)
// ============================================================
let idArchivoDevolver = null;

function openDevolverModal(archivo) {
    if (archivo.generado) {
        showToast('El archivo ya se descargó para el banco: no se puede devolver.', 'error');
        return;
    }
    idArchivoDevolver = archivo.id_archivo_plano;
    const modulo = archivo.modulo_origen || 'Nómina';
    setText('devolver-titulo', `Devolver a ${modulo}`);
    setText('devolver-subtitulo', `${archivo.nom_archivo} — ${archivo.periodo_nomina || ''}`);
    setText('devolver-texto', archivo.es_inversion
        ? 'El archivo se elimina de Tesorería y las cuotas vuelven a quedar pendientes en el módulo Financiero, para que corrijan y las envíen otra vez.'
        : 'El archivo se elimina de Tesorería y los empleados vuelven a quedar pendientes en el módulo de Nómina, para que corrijan y lo envíen otra vez.');
    show('modal-devolver-nomina');
}

function closeDevolverModal() {
    idArchivoDevolver = null;
    hide('modal-devolver-nomina');
}

async function confirmarDevolver() {
    const btn = document.getElementById('devolver-btn-ok');
    if (!idArchivoDevolver || btn?.disabled) return;
    if (btn) btn.disabled = true;

    const formData = new FormData();
    formData.append('btn_devolver_archivo', '1');
    formData.append('hid_id_archivo_plano', idArchivoDevolver);

    try {
        const result = await enviarPost(formData, 'btn_devolver_archivo');
        if (result.success) {
            showToast(result.message, 'success');
            closeDevolverModal();
            setTimeout(() => location.reload(), 800);
        } else {
            showToast(result.message || 'No se pudo devolver el archivo.', 'error');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    } finally {
        if (btn) btn.disabled = false;
    }
}

// ============================================================
// 5. MODAL: DETALLE DE ARCHIVO PLANO
// ============================================================
let idArchivoDetalleActual = null;

// Respuesta del banco para una línea. Sin pago registrado = todavía sin respuesta.
function badgeEstadoPago(d) {
    switch (Number(d.estado_pago)) {
        case 2: return '<span class="badge ok">Aprobado</span>';
        case 3: return `<span class="badge bad" title="${escapeHtml((d.id_codigo || '') + ' ' + (d.des_motivo || ''))}">Rechazado</span>`;
        case 1: return '<span class="badge warn">Pendiente</span>';
        default: return '<span class="badge mute">Sin respuesta</span>';
    }
}

async function openDetailModal(archivo) {
    idArchivoDetalleActual = archivo.id_archivo_plano;

    const esNomina    = !!archivo.es_nomina;
    const esInversion = !!archivo.es_inversion;
    const esExterno   = esNomina || esInversion;
    setText('detail-title', archivo.nom_archivo);
    setText('detail-subtitle', `#${archivo.id_archivo_plano} — ${archivo.generado ? 'Generado' : 'Por generar'}${esExterno ? ' — ' + archivo.periodo_nomina : ''}`);

    document.getElementById('detail-content').innerHTML = `
        <div class="detail-grid">
            <div class="detail-item"><span class="detail-label">Empresa</span><span class="detail-value">${escapeHtml(archivo.nom_empresa)}<br><small>${escapeHtml(archivo.id_empresa)}</small></span></div>
            <div class="detail-item"><span class="detail-label">Cuenta de Origen</span><span class="detail-value">${escapeHtml(archivo.nom_banco)}<br><small>${escapeHtml(archivo.cta_empresa)} · ${escapeHtml(archivo.tipo_cuenta)}</small></span></div>
            <div class="detail-item"><span class="detail-label">Tipo de Archivo</span><span class="detail-value">${escapeHtml(archivo.nom_tipo_pago)}${esExterno ? '<br><small>' + escapeHtml(archivo.periodo_nomina) + '</small>' : ''}</span></div>
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
            detalleList.innerHTML = `<p class="tcx-lista-msg error">${escapeHtml(result.message || 'Error al cargar el detalle.')}</p>`;
            return;
        }
        const detalle = result.detalle || [];
        if (detalle.length === 0) {
            detalleList.innerHTML = '<p class="tcx-lista-msg">Este archivo no tiene pagos.</p>';
            return;
        }

        const unidad = esNomina ? 'empleado' : (esInversion ? 'cuota' : 'pago');
        setText('detail-total', `${formatCurrency(detalle.reduce((n, d) => n + Number(d.val_a_pagar || 0), 0))} (${detalle.length} ${unidad}${detalle.length !== 1 ? 's' : ''})`);

        detalleList.innerHTML = detalle.map(d => `
            <div class="cuota-row">
                <span class="cuota-num">
                    ${escapeHtml(d.nom_tercero)}
                    <small>${escapeHtml(d.id_tipo)} ${escapeHtml(d.id_proveedor)} · ${escapeHtml(d.nom_banco)} ${escapeHtml(d.cta_proveedor)} (${escapeHtml(d.tipo_cuenta)})</small>
                    <small>${esNomina
                        ? escapeHtml(d.concepto || 'Pago de nómina')
                        : esInversion
                            ? `Proyecto ${escapeHtml(d.id_proyecto)} · cuota ${escapeHtml(d.id_cuota)}`
                            : `Fact. ${escapeHtml(d.id_factura)} · cuota ${escapeHtml(d.id_cuota)}${d.concepto ? ' · ' + escapeHtml(d.concepto) : ''}`}</small>
                    ${Number(d.estado_pago) === 3 && d.des_motivo ? `<small class="motivo-rechazo">${escapeHtml(d.id_codigo)}: ${escapeHtml(d.des_motivo)}</small>` : ''}
                </span>
                ${badgeEstadoPago(d)}
                <span class="cuota-valor">${formatCurrency(d.val_a_pagar)}</span>
            </div>
        `).join('');
    } catch (err) {
        detalleList.innerHTML = '<p class="tcx-lista-msg error">Error de conexión al cargar el detalle.</p>';
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
// 6. LISTA: SECCIONES, INDICADORES, FILTROS, ORDEN Y PAGINADOR
// ------------------------------------------------------------
// Las tablas las pinta este archivo desde archivosData (PHP). Tres secciones
// (Proveedores / Nómina / Inversiones), cada una con su tabla y su orden; el
// paginador es uno solo (componentes compartidos de erp_ui.js).
// Indicadores y conteos: sobre TODOS los archivos de la sección activa.
// Clic (o Enter/espacio) en la fila abre el detalle. La sección se recuerda
// en sessionStorage para que al recargar (después de editar, devolver o
// descargar) se quede en la misma.
// ============================================================
const SECCIONES = ['proveedores', 'nomina', 'inversiones'];
let seccion = 'proveedores';
let pag = null;
const ordenes = {};
const normArc = t => (window.erpNormalizar ? erpNormalizar(t) : String(t ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim());
const archivosSeccion = () => ((typeof archivosData !== 'undefined' && archivosData && archivosData[seccion]) || []);
const todosArchivos = () => (typeof archivosData !== 'undefined' && archivosData ? SECCIONES.flatMap(s => archivosData[s] || []) : []);
const fechaCortaArc = v => String(v || '').slice(0, 10);
const periodoArc = a => `${a.ano_nomina}-${String(Number(a.mes_nomina)).padStart(2, '0')}`;
const plural = (n, uno, varios) => `${n} ${n === 1 ? uno : varios}`;

function columnasOrden(sec) {
    const comunes = {
        'Archivo':          { valor: a => a.nom_archivo },
        'Cuenta de origen': { valor: a => `${a.nom_banco} ${a.cta_empresa}` },
        'Aplicación':       { valor: a => fechaCortaArc(a.fecha_aplicacion), tipo: 'fecha' },
        'Generación':       { valor: a => fechaCortaArc(a.fec_generacion), tipo: 'fecha' },
        'Estado':           { valor: a => a.estado },
    };
    const total = { valor: a => Number(a.total) || 0, tipo: 'numero' };
    if (sec === 'nomina') return { ...comunes, 'Periodo': { valor: a => `${periodoArc(a)}-${a.val_periodo}` }, 'Empleados': total };
    if (sec === 'inversiones') return { ...comunes, 'Inversores': { valor: a => fechaCortaArc(a.max_vencimiento), tipo: 'fecha' }, 'Cuotas': total };
    return { ...comunes, 'Pagos': total };
}

function prepararLista() {
    if (!pag && window.ErpPaginador) {
        pag = ErpPaginador.crear({ lista: document.getElementById('tbody-proveedores'), onCambio: renderArchivos, tam: 25 });
    }
    if (window.ErpOrden) {
        SECCIONES.forEach(sec => {
            if (ordenes[sec]) return;
            ordenes[sec] = ErpOrden.crear({
                tabla: document.getElementById(`tabla-${sec}`),
                columnas: columnasOrden(sec),
                onCambio: () => { if (pag) pag.inicio(); renderArchivos(); },
            });
        });
    }
}

function cambiarSeccion(nueva, guardar = true) {
    if (!SECCIONES.includes(nueva)) nueva = 'proveedores';
    seccion = nueva;

    document.querySelectorAll('#mod-archivo-plano .ap-tab').forEach(tab => {
        const activa = tab.dataset.tab === nueva;
        tab.classList.toggle('active', activa);
        tab.setAttribute('aria-selected', activa ? 'true' : 'false');
    });
    SECCIONES.forEach(sec => {
        const t = document.getElementById(`tabla-${sec}`);
        if (t) t.hidden = sec !== nueva;
    });
    document.querySelectorAll('#mod-archivo-plano .ap-hint-seccion').forEach(el => { el.hidden = el.dataset.seccion !== nueva; });
    // Solo los archivos de proveedores se arman aquí
    const btnNuevo = document.getElementById('btn-add-archivo');
    if (btnNuevo) btnNuevo.hidden = nueva !== 'proveedores';

    const buscador = document.getElementById('archivo-search');
    if (buscador) {
        buscador.placeholder = {
            nomina:      'Buscar por nombre, periodo, banco o cuenta...',
            inversiones: 'Buscar por nombre, banco o cuenta...',
        }[nueva] || 'Buscar por nombre, banco o cuenta...';
    }

    if (guardar) {
        try { sessionStorage.setItem('archivo_plano_seccion', nueva); } catch (e) { /* sin almacenamiento */ }
    }
    updateStats();
    clearFilters();
    if (window.ErpListaFija) ErpListaFija.ajustar();
}

function seccionGuardada() {
    const delHash = location.hash.slice(1);
    if (SECCIONES.includes(delHash)) return delHash;
    try { return sessionStorage.getItem('archivo_plano_seccion') || 'proveedores'; } catch (e) { return 'proveedores'; }
}

function poneIndicador(n, label, icono, valor, hint) {
    setText(`stat-${n}-label`, label);
    const ico = document.getElementById(`stat-${n}-icono`);
    if (ico && icono) ico.className = `fas ${icono}`;
    setText(`stat-${n}`, valor);
    setText(`stat-${n}-hint`, hint);
}

function updateStats() {
    const data = archivosSeccion();
    const generados = data.filter(a => a.generado).length;
    const porGenerar = data.length - generados;
    setText('stat-2', porGenerar);
    if (seccion === 'proveedores') {
        const valorPend = data.filter(a => !a.generado).reduce((t, a) => t + (Number(a.total) || 0), 0);
        poneIndicador(1, 'Total archivos', 'fa-file-invoice', data.length, 'Armados desde un cronograma');
        poneIndicador(3, 'Generados', 'fa-check-circle', generados, 'CSV descargado para el banco');
        poneIndicador(4, 'Valor por generar', 'fa-coins', formatCurrency(valorPend), plural(porGenerar, 'archivo pendiente', 'archivos pendientes'));
    } else {
        const esperando = data.filter(a => a.estado === 'esperando').length;
        const rechazos  = data.filter(a => a.estado === 'rechazos').length;
        poneIndicador(1, seccion === 'nomina' ? 'Recibidos de Nómina' : 'Recibidos de Financiero', 'fa-inbox', data.length,
            seccion === 'nomina' ? 'Enviados por Gestión Humana' : 'Enviados por el área Financiera');
        poneIndicador(3, 'Esperando al banco', 'fa-building-columns', esperando, 'Generados, sin respuesta completa');
        poneIndicador(4, 'Con rechazos', 'fa-circle-exclamation', rechazos, 'Hay que corregir y reenviar');
    }
    setText('arc-cnt-all', data.length);
    setText('arc-cnt-generado', generados);
    setText('arc-cnt-pendiente', porGenerar);
}

function hayFiltros() {
    return val('archivo-search').trim() !== '' || (val('archivo-filtro-estado') || 'all') !== 'all';
}

function getFilteredArchivos() {
    const q = normArc(val('archivo-search'));
    const estado = val('archivo-filtro-estado') || 'all';
    return archivosSeccion().filter(a => {
        if (estado === 'generado' && !a.generado) return false;
        if (estado === 'pendiente' && a.generado) return false;
        const texto = `${a.id_archivo_plano} ${a.nom_archivo} ${a.nom_banco} ${a.cta_empresa} ${a.es_nomina ? periodoArc(a) : ''} ${a.periodo_nomina || ''}`;
        if (q && !normArc(texto).includes(q)) return false;
        return true;
    });
}

function applyFilters() {
    if (pag) pag.inicio();
    renderArchivos();
}

function clearFilters() {
    setVal('archivo-search', '');
    setVal('archivo-filtro-estado', 'all');
    if (window.ErpFiltros) ErpFiltros.sincronizar();
    applyFilters();
}

function celdaEstado(a) {
    if (!a.es_externo) return a.generado ? '<span class="badge ok">Generado</span>' : '<span class="badge warn">Por generar</span>';
    const cant = Number(a.cant_lineas) || 0, apr = Number(a.nom_aprobados) || 0, rec = Number(a.nom_rechazados) || 0;
    const fem = a.es_inversion;   // cuotas (femenino) / empleados (masculino)
    switch (a.estado) {
        case 'por_generar': return '<span class="badge warn">Por generar</span>';
        case 'esperando':   return `<span class="badge info">Esperando banco</span><span class="tcx-sub">${apr + rec} de ${cant} con respuesta</span>`;
        case 'pagado':      return '<span class="badge ok">Pagado</span>';
        default:            return `<span class="badge bad">Con rechazos</span><span class="tcx-sub">${rec} rechazad${fem ? 'a' : 'o'}${rec !== 1 ? 's' : ''} · ${apr} pagad${fem ? 'a' : 'o'}${apr !== 1 ? 's' : ''}</span>`;
    }
}

function celdaAcciones(a) {
    const nombre = escapeHtml(a.nom_archivo);
    let html = `<button type="button" class="btn-icon-sm view" data-action="descargar" title="Descargar CSV" aria-label="Descargar el CSV de ${nombre}"><i class="fas fa-download"></i></button>`;
    if (a.generado) {
        html += `<span class="accion-bloqueada" title="Archivo generado: no se puede editar${a.es_externo ? ' ni devolver' : ''}"><i class="fas fa-lock" aria-hidden="true"></i></span>`;
    } else {
        html += `<button type="button" class="btn-icon-sm edit" data-action="editar" title="${a.es_externo ? 'Editar nombre, cuenta de origen y fecha' : 'Editar nombre'}" aria-label="Editar ${nombre}"><i class="fas fa-pen"></i></button>`;
        if (a.es_externo) html += `<button type="button" class="btn-icon-sm reject" data-action="devolver" title="Devolver a ${escapeHtml(a.modulo_origen || (a.es_inversion ? 'Financiero' : 'Nómina'))}" aria-label="Devolver ${nombre}"><i class="fas fa-rotate-left"></i></button>`;
    }
    return `<td class="col-acciones"><div class="actions-cell">${html}</div></td>`;
}

function filaArchivo(a) {
    const id = escapeHtml(a.id_archivo_plano);
    const cant = Number(a.cant_lineas) || 0;
    const archivo = `<td><span class="tcx-fuerte">${escapeHtml(a.nom_archivo)}</span><span class="tcx-sub">#${id}</span></td>`;
    const origen = `<td>${escapeHtml(a.nom_banco)}<span class="tcx-sub">${escapeHtml(a.cta_empresa)} · ${escapeHtml(a.tipo_cuenta)}</span></td>`;
    const unidad = a.es_nomina ? ['empleado', 'empleados'] : a.es_inversion ? ['cuota', 'cuotas'] : ['pago', 'pagos'];
    const total = `<td class="text-right tcx-num"><span class="tcx-fuerte">${formatCurrency(a.total)}</span><span class="tcx-sub">${plural(cant, unidad[0], unidad[1])}</span></td>`;
    const fechas = `<td class="tcx-num">${escapeHtml(formatDate(fechaCortaArc(a.fecha_aplicacion)))}</td><td class="tcx-num">${escapeHtml(formatDate(fechaCortaArc(a.fec_generacion)))}</td>`;
    let segunda = '';
    if (seccion === 'nomina') {
        segunda = `<td><span class="tcx-fuerte">${escapeHtml(periodoArc(a))}</span><span class="tcx-sub">Periodo ${escapeHtml(Number(a.val_periodo))}</span></td>`;
    } else if (seccion === 'inversiones') {
        segunda = `<td><span class="tcx-fuerte">${plural(Number(a.cant_inversores) || 0, 'inversor', 'inversores')}</span><span class="tcx-sub">${plural(Number(a.cant_proyectos) || 0, 'proyecto', 'proyectos')} · vencen hasta ${escapeHtml(formatDate(fechaCortaArc(a.max_vencimiento)))}</span></td>`;
    }
    const cuerpo = seccion === 'proveedores' ? archivo + origen + total : archivo + segunda + origen + total;
    return `<tr data-fila-abre data-id="${id}" tabindex="0" aria-label="Ver el archivo ${escapeHtml(a.nom_archivo)}">
        ${cuerpo}${fechas}<td><div class="tcx-estado">${celdaEstado(a)}</div></td>${celdaAcciones(a)}
    </tr>`;
}

// Lista: filtrar → contar → ordenar → paginar → pintar (sección activa)
function renderArchivos() {
    prepararLista();
    let filas = getFilteredArchivos();
    setText('archivos-count', `${filas.length} resultado${filas.length !== 1 ? 's' : ''}`);
    const btnClear = document.getElementById('btn-clear-filters');
    if (btnClear) btnClear.hidden = !hayFiltros();

    const tbody = document.getElementById(`tbody-${seccion}`);
    if (!tbody) return;
    const columnas = seccion === 'proveedores' ? 7 : 8;
    if (filas.length === 0) {
        const hayDatos = archivosSeccion().length > 0;
        const vacio = {
            proveedores: ['fa-file-invoice', 'No hay archivos planos de proveedores para mostrar', 'Use «Nuevo archivo plano» para crear el primero a partir de un cronograma'],
            nomina:      ['fa-users', 'No hay archivos de nómina para mostrar', 'Aparecen aquí cuando Gestión Humana pulsa «Enviar a Tesorería» en Liquidar Nómina'],
            inversiones: ['fa-hand-holding-dollar', 'No hay archivos de inversiones para mostrar', 'Aparecen aquí cuando el área Financiera envía las cuotas aprobadas a Tesorería'],
        }[seccion];
        tbody.innerHTML = `<tr><td colspan="${columnas}"><div class="empty-state">
            <i class="fas ${hayDatos ? 'fa-search' : vacio[0]}"></i>
            <p>${hayDatos ? 'Ningún archivo coincide con los filtros' : vacio[1]}</p>
            <span>${hayDatos ? 'Cambie la búsqueda o use «Limpiar»' : vacio[2]}</span>
        </div></td></tr>`;
        if (pag) pag.paginar([]);
        return;
    }
    const orden = ordenes[seccion];
    if (orden) filas = orden.ordenar(filas);
    const pagina = pag ? pag.paginar(filas) : filas;
    tbody.innerHTML = pagina.map(filaArchivo).join('');
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

    // Los modales los mueve a <body> el componente "modales" (erp_ui.js); en el HTML
    // los modales rápidos van después del que los abre, para quedar encima.
    // El calendario y el aviso se mueven aquí: así no los tapa el difuminado.
    ['dp-pop', 'toast'].forEach(id => {
        const el = document.getElementById(id);
        if (el && el.parentElement !== document.body) document.body.appendChild(el);
    });

    cargarCalendarioPagos();
    initSelectorFecha();

    document.getElementById('btn-add-archivo')?.addEventListener('click', openNewModal);
    document.getElementById('archivo-search')?.addEventListener('input', applyFilters);
    document.getElementById('archivo-filtro-estado')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // ---------- CLIC EN LA TABLA ----------
    // Clic (o Enter/espacio) en la fila = detalle; los botones de acciones hacen lo suyo.
    const archivoDe = tr => todosArchivos().find(x => String(x.id_archivo_plano) === tr.dataset.id);
    SECCIONES.forEach(sec => {
        const tb = document.getElementById(`tbody-${sec}`);
        tb?.addEventListener('click', e => {
            const fila = e.target.closest('tr[data-fila-abre]');
            if (!fila) return;
            const archivo = archivoDe(fila);
            if (!archivo) return;
            const btn = e.target.closest('button[data-action]');
            if (btn) {
                if (btn.dataset.action === 'descargar') descargarArchivoPlano(archivo.id_archivo_plano);
                if (btn.dataset.action === 'editar')    openEditModal(archivo);
                if (btn.dataset.action === 'devolver')  openDevolverModal(archivo);
                return;
            }
            if (e.target.closest('.accion-bloqueada, button, a, input, select, textarea')) return;
            openDetailModal(archivo);
        });
        tb?.addEventListener('keydown', e => {
            if (e.key !== 'Enter' && e.key !== ' ') return;
            const fila = e.target.closest('tr[data-fila-abre]');
            if (!fila || e.target !== fila) return;
            e.preventDefault();
            const archivo = archivoDe(fila);
            if (archivo) openDetailModal(archivo);
        });
    });

    // ---------- SECCIONES (pestañas Proveedores / Nómina / Inversiones) ----------
    document.querySelectorAll('#mod-archivo-plano .ap-tab').forEach(tab => {
        tab.addEventListener('click', () => cambiarSeccion(tab.dataset.tab));
    });
    cambiarSeccion(seccionGuardada(), false);   // también calcula los indicadores y pinta la lista
    const mod = document.getElementById('mod-archivo-plano');
    requestAnimationFrame(() => requestAnimationFrame(() => mod?.classList.add('is-listo')));

    // Esc cierra solo el detalle y la confirmación de devolver (de lectura).
    // Los formularios se cierran solo con la X o Cancelar.
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape' || selectorFechaAbierto()) return;
        const abierto = id => { const m = document.getElementById(id); return m && !m.classList.contains('hidden'); };
        if (abierto('modal-devolver-nomina')) closeDevolverModal();
        else if (abierto('modal-detail')) closeDetailModal();
    });

    document.getElementById('new-id-cronograma')?.addEventListener('change', onCronogramaChange);
    document.getElementById('new-cta-empresa')?.addEventListener('change', mostrarEmpresaCuenta);

    // ---------- MODALES RÁPIDOS: CUENTAS Y BANCO ----------
    initModalesRapidos();

    // Al corregir un campo se borra su mensaje de error
    ['new-archivo-form', 'edit-archivo-form', 'ctaemp-rapida-form', 'ctaprov-rapida-form', 'banco-rapido-form'].forEach(formId => {
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

    document.getElementById('close-devolver-modal')?.addEventListener('click', closeDevolverModal);
    document.getElementById('cancel-devolver-modal')?.addEventListener('click', closeDevolverModal);
    document.getElementById('devolver-btn-ok')?.addEventListener('click', confirmarDevolver);

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
