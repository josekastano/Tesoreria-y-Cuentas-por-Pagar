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

// En Cuentas por Pagar no hay días especiales que resaltar
function marcaFecha(/* iso */) { return null; }

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
// 2. CÁLCULO DE FECHA DE VENCIMIENTO EN VIVO
// ============================================================
function addDays(dateStr, days) {
    const date = new Date(dateStr + 'T00:00:00');
    date.setDate(date.getDate() + days);
    return date;
}

function formatDateLocal(date) {
    const d = String(date.getDate()).padStart(2, '0');
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const y = date.getFullYear();
    return `${m}/${d}/${y}`;
}

function updateVencimientoPreview() {
    const selProv       = document.getElementById('new-id-proveedor');
    const fecEmision    = val('new-fec-emision');
    const fecVencInput  = document.getElementById('new-fec-vencimiento');

    if (!selProv || !selProv.value || !fecEmision) {
        if (fecVencInput) {
            fecVencInput.value = '';
            fecVencInput.placeholder = 'Seleccione un proveedor';
        }
        return;
    }

    const dias = parseInt(selProv.selectedOptions[0]?.dataset.dias ?? '0', 10);
    const fechaVenc = addDays(fecEmision, dias);
    if (fecVencInput) {
        fecVencInput.value = `${formatDateLocal(fechaVenc)} (+${dias} días)`;
    }
}

function updateCuotaPreview() {
    const valorFactura = parseFloat(val('new-val-factura')) || 0;
    const numCuotas    = parseInt(val('new-num-cuotas'), 10) || 0;
    const preview      = document.getElementById('new-cuota-preview');
    if (!preview) return;

    // Sin modalidad definida (falta proveedor u orden) no se adelanta nada
    const cond = obtenerCondicionesPago();
    if (!cond || cond.estado !== 'ok') {
        preview.style.display = 'none';
        return;
    }

    if (valorFactura > 0 && numCuotas > 0 && numCuotas <= cond.max) {
        const valorCuota = valorFactura / numCuotas;
        preview.style.display = '';
        preview.innerHTML = `<i class="fas fa-info-circle"></i> Se generarán <strong>${numCuotas}</strong> cuota${numCuotas !== 1 ? 's' : ''} de aproximadamente <strong>${formatCurrency(valorCuota)}</strong> cada una.`;
    } else {
        preview.style.display = 'none';
    }
}

// ============================================================
// 2.0 MODALIDAD DE PAGO (CONTADO / CRÉDITO) Y NÚMERO DE CUOTAS
// ------------------------------------------------------------
// Reglas (las mismas que valida cuentasxpagar.php en el servidor):
//   - Con orden de compra: manda el método de pago de la orden.
//       Contado → 1 cuota fija, no editable.
//       Crédito → el usuario elige de 1 al máximo de cuotas pactado con
//                 el proveedor (tab_proveedores.ind_num_cuotas).
//   - Compra directa: manda lo pactado con el proveedor (ind_credito).
// ============================================================

// Devuelve:
//   null                                → falta el proveedor
//   { estado: 'sin-oc' }                → dijo que hay orden pero no la eligió
//   { estado: 'ok', credito, max, origen, orden }
function obtenerCondicionesPago() {
    const selProv = document.getElementById('new-id-proveedor');
    const opt     = selProv?.selectedOptions?.[0];
    if (!selProv || !selProv.value || !opt) return null;

    const creditoProv = opt.dataset.credito === '1';
    const maxProv     = Math.max(1, parseInt(opt.dataset.maxCuotas || '1', 10) || 1);

    if (tieneOrdenCompra()) {
        const orden = buscarOrden(val('new-id-ordencompra'));
        if (!orden) return { estado: 'sin-oc' };
        const credito = esCredito(orden);
        return { estado: 'ok', credito, max: credito ? maxProv : 1, origen: 'oc', orden };
    }

    return { estado: 'ok', credito: creditoProv, max: creditoProv ? maxProv : 1, origen: 'proveedor' };
}

// Saldo que le queda por facturar a una orden (si ya tiene facturas
// parciales, es menos que su total). Es el valor que lleva la factura.
function saldoOrden(orden) {
    if (!orden) return 0;
    return orden.val_saldo_disponible != null
        ? Number(orden.val_saldo_disponible)
        : Number(orden.val_total);
}

// Con orden de compra elegida, el valor de la factura se toma de la orden
// y no se puede editar. Sin orden (compra directa) se digita libremente.
let valorBloqueadoPorOC = false;

function actualizarBloqueoValor() {
    const input = document.getElementById('new-val-factura');
    const lock  = document.getElementById('valor-lock');
    if (!input) return;

    const orden = tieneOrdenCompra() ? buscarOrden(val('new-id-ordencompra')) : null;

    if (orden) {
        input.value    = saldoOrden(orden);
        input.readOnly = true;
        input.classList.add('bloqueado');
        if (lock) lock.style.display = '';
        const facturado = Number(orden.val_facturado ?? 0);
        setText('valor-hint', facturado > 0
            ? `Saldo por facturar de la OC #${orden.id_ordencompra} (ya tiene ${formatCurrency(facturado)} facturado).`
            : `Tomado de la OC #${orden.id_ordencompra}. No se puede modificar.`);
        valorBloqueadoPorOC = true;
    } else {
        // Al quitar la orden se libera el campo y se borra el valor que
        // venía de ella, para que no quede un valor "heredado" sin querer.
        if (valorBloqueadoPorOC) input.value = '';
        input.readOnly = false;
        input.classList.remove('bloqueado');
        if (lock) lock.style.display = 'none';
        setText('valor-hint', '');
        valorBloqueadoPorOC = false;
    }
}

// Pinta el aviso de modalidad y muestra/bloquea el campo de cuotas
function actualizarModalidadPago() {
    actualizarBloqueoValor();
    const cond    = obtenerCondicionesPago();
    const caja    = document.getElementById('pago-modalidad');
    const icono   = document.getElementById('pago-modalidad-icono');
    const badge   = document.getElementById('pago-modalidad-badge');
    const input   = document.getElementById('new-num-cuotas');
    const fijas   = document.getElementById('cuotas-fijas');
    if (!caja || !input || !fijas) return;

    const ponerFijo = (texto, hint) => {
        input.style.display = 'none';
        input.min = 1;
        input.max = 1;
        input.value = 1;           // el input oculto se envía igual con el formulario
        fijas.style.display = '';
        setText('cuotas-fijas-texto', texto);
        setText('cuotas-hint', hint);
    };

    if (!cond) {
        caja.dataset.estado = 'pendiente';
        if (icono) icono.className = 'fas fa-hand-holding-dollar';
        setText('pago-modalidad-titulo', 'Modalidad de pago');
        setText('pago-modalidad-detalle', 'Seleccione un proveedor para conocer la modalidad de pago.');
        if (badge) badge.style.display = 'none';
        ponerFijo('—', '');
    } else if (cond.estado === 'sin-oc') {
        caja.dataset.estado = 'pendiente';
        if (icono) icono.className = 'fas fa-hand-holding-dollar';
        setText('pago-modalidad-titulo', 'Modalidad de pago');
        setText('pago-modalidad-detalle', 'Seleccione la orden de compra: ella define si la factura es de contado o a crédito.');
        if (badge) badge.style.display = 'none';
        ponerFijo('—', '');
    } else if (!cond.credito) {
        caja.dataset.estado = 'contado';
        if (icono) icono.className = 'fas fa-money-bill-wave';
        setText('pago-modalidad-titulo', 'Pago de contado');
        setText('pago-modalidad-detalle', cond.origen === 'oc'
            ? `La orden de compra OC #${cond.orden.id_ordencompra} se pactó de contado. La factura se registra en una sola cuota.`
            : 'Este proveedor no acepta crédito. La factura se registra en una sola cuota.');
        if (badge) { badge.textContent = 'Contado'; badge.style.display = ''; }
        ponerFijo('1 cuota (contado)', 'No se puede modificar: es un pago de contado.');
    } else {
        caja.dataset.estado = 'credito';
        if (icono) icono.className = 'fas fa-credit-card';
        setText('pago-modalidad-titulo', 'Pago a crédito');
        setText('pago-modalidad-detalle', cond.origen === 'oc'
            ? `La orden de compra OC #${cond.orden.id_ordencompra} se pactó a crédito. Puede dividir la factura hasta en ${cond.max} cuota${cond.max !== 1 ? 's' : ''}.`
            : `Este proveedor acepta crédito. Puede dividir la factura hasta en ${cond.max} cuota${cond.max !== 1 ? 's' : ''}.`);
        if (badge) { badge.textContent = `Hasta ${cond.max} cuota${cond.max !== 1 ? 's' : ''}`; badge.style.display = ''; }

        if (cond.max <= 1) {
            // Crédito, pero el proveedor solo pactó 1 cuota
            ponerFijo('1 cuota', 'El máximo pactado con el proveedor es 1 cuota.');
        } else {
            fijas.style.display = 'none';
            input.style.display = '';
            input.min = 1;
            input.max = cond.max;
            input.placeholder = `1 a ${cond.max}`;
            const actual = parseInt(input.value, 10);
            if (!actual || actual < 1) input.value = 1;
            else if (actual > cond.max) input.value = cond.max;
            setText('cuotas-hint', `Entre 1 y ${cond.max} cuotas (máximo pactado con el proveedor).`);
        }
    }

    updateCuotaPreview();
}

// Valida el número de cuotas contra la modalidad. Devuelve el mensaje de
// error o '' si está bien.
function errorCuotas() {
    const cond = obtenerCondicionesPago();
    if (!cond || cond.estado !== 'ok') return '';   // ya lo marca proveedor / orden
    const n = parseInt(val('new-num-cuotas'), 10);
    if (!Number.isInteger(n) || n < 1) return 'Ingrese un número de cuotas válido.';
    if (n > cond.max) {
        return cond.credito
            ? `El máximo de cuotas pactado con el proveedor es ${cond.max}.`
            : 'Es un pago de contado: la factura va en 1 sola cuota.';
    }
    return '';
}

// ============================================================
// 2.1 ORDEN DE COMPRA DE LA FACTURA
// ============================================================
// Solo se listan las órdenes aprobadas sin factura. La búsqueda vive en su
// propio modal; el formulario solo guarda el id y muestra un resumen.
let ocPendiente = '';   // marcada dentro del modal, aún sin confirmar
let ocMetodo    = 'all';

function tieneOrdenCompra() {
    return document.querySelector('input[name="rad_tiene_oc"]:checked')?.value === 'si';
}

function esCredito(orden) {
    return orden.met_pago === 't' || orden.met_pago === true;
}

function buscarOrden(idOC) {
    return (ordenesData || []).find(o => String(o.id_ordencompra) === String(idOC));
}

// Nombre del proveedor de una orden para mostrar en el selector. La columna
// que devuelve la consulta se llama "proveedor_nombre" (no "nom_tercero").
// Si por cualquier motivo no viene, se muestra al menos el NIT del
// proveedor en vez de dejarlo en blanco (o mostrar "undefined").
function nombreProveedorOC(orden) {
    const nombre = (orden?.proveedor_nombre ?? '').trim();
    if (nombre) return nombre;
    return orden?.id_proveedor ? `Proveedor NIT ${orden.id_proveedor}` : 'Proveedor desconocido';
}

// Valor a mostrar junto a la orden: si ya tiene algo facturado (orden
// parcialmente usada), se muestra el saldo disponible en vez del total,
// para que quede claro cuánto queda realmente por facturar.
function valorMostrarOC(orden) {
    const facturado = Number(orden?.val_facturado ?? 0);
    if (facturado > 0 && orden?.val_saldo_disponible != null) {
        return `${formatCurrency(orden.val_saldo_disponible)} disponible`;
    }
    return formatCurrency(orden?.val_total);
}

// ---- Resumen en el formulario ----
function renderOCSelected() {
    const idOC = val('new-id-ordencompra');
    const orden = idOC ? buscarOrden(idOC) : null;
    const caja = document.getElementById('oc-selected');

    if (!orden) {
        caja?.classList.remove('sel');
        setText('oc-selected-num', 'Ninguna orden seleccionada');
        setText('oc-selected-meta', 'Busque la orden que corresponde a esta factura.');
        return;
    }

    caja?.classList.add('sel');
    setText('oc-selected-num', `OC #${orden.id_ordencompra} — ${nombreProveedorOC(orden)}`);
    setText('oc-selected-meta', `${formatDate(orden.fec_emision)} · ${orden.ciudad_nombre ?? ''} · ${esCredito(orden) ? 'Crédito' : 'Contado'} · ${valorMostrarOC(orden)}`);
}

function limpiarSeleccionOC() {
    setVal('new-id-ordencompra', '');
    ocPendiente = '';
    renderOCSelected();
    actualizarModalidadPago();
}

// ---- Lista dentro del modal ----
function renderOrdenes() {
    const lista = document.getElementById('oc-list');
    if (!lista) return;

    const query  = val('oc-search').toLowerCase().trim();
    const prov   = val('oc-filtro-proveedor');
    const desde  = val('oc-fec-desde');
    const hasta  = val('oc-fec-hasta');

    const visibles = (ordenesData || []).filter(o => {
        const texto = `${o.id_ordencompra} ${nombreProveedorOC(o)}`.toLowerCase();
        if (query && !texto.includes(query)) return false;
        if (prov && o.id_proveedor !== prov) return false;
        if (desde && o.fec_emision < desde) return false;
        if (hasta && o.fec_emision > hasta) return false;
        if (ocMetodo === 'credito' && !esCredito(o)) return false;
        if (ocMetodo === 'contado' && esCredito(o)) return false;
        return true;
    });

    setText('oc-count', `${visibles.length} ${visibles.length === 1 ? 'orden' : 'órdenes'}`);

    // El proveedor bloqueado (por el proveedor ya elegido en el formulario)
    // no cuenta como "filtro activo" para mostrar el botón Limpiar, porque
    // Limpiar no puede (ni debe) quitarlo.
    const filtroProvEl  = document.getElementById('oc-filtro-proveedor');
    const provOpcional  = (filtroProvEl && !filtroProvEl.disabled) ? prov : '';

    const clearBtn = document.getElementById('btn-oc-clear');
    if (clearBtn) {
        clearBtn.style.display = (query || provOpcional || desde || hasta || ocMetodo !== 'all') ? '' : 'none';
    }

    if (visibles.length === 0) {
        lista.innerHTML = '<p class="oc-vacio">Ninguna orden coincide con estos filtros.</p>';
    } else {
        lista.innerHTML = visibles.map(o => `
            <label class="oc-row ${String(o.id_ordencompra) === ocPendiente ? 'sel' : ''}" data-id-oc="${escapeHtml(o.id_ordencompra)}">
                <input type="radio" name="rad_oc_sel" value="${escapeHtml(o.id_ordencompra)}"
                       ${String(o.id_ordencompra) === ocPendiente ? 'checked' : ''}>
                <span class="oc-row-info">
                    <span class="oc-row-num">OC #${escapeHtml(o.id_ordencompra)} — ${escapeHtml(nombreProveedorOC(o))}</span>
                    <span class="oc-row-meta">${formatDate(o.fec_emision)} · ${escapeHtml(o.ciudad_nombre ?? '')} · ${esCredito(o) ? 'Crédito' : 'Contado'}</span>
                </span>
                <span class="oc-row-valor">${valorMostrarOC(o)}</span>
            </label>
        `).join('');

        lista.querySelectorAll('.oc-row').forEach(row => {
            row.addEventListener('click', () => {
                ocPendiente = row.dataset.idOc;
                lista.querySelectorAll('.oc-row').forEach(r => r.classList.remove('sel'));
                row.classList.add('sel');
                const btn = document.getElementById('btn-confirm-oc');
                if (btn) btn.disabled = false;
            });
        });
    }

    const btn = document.getElementById('btn-confirm-oc');
    if (btn) btn.disabled = !ocPendiente;
}

function clearOCFilters() {
    setVal('oc-search', '');
    // El filtro de proveedor solo se limpia si no está bloqueado por el
    // proveedor ya elegido en el formulario principal.
    const filtroProv = document.getElementById('oc-filtro-proveedor');
    if (filtroProv && !filtroProv.disabled) {
        setVal('oc-filtro-proveedor', '');
    }
    setFecha('oc-fec-desde', '');
    setFecha('oc-fec-hasta', '');
    ocMetodo = 'all';
    document.querySelectorAll('.oc-toggle').forEach(b => b.classList.remove('active'));
    document.querySelector('.oc-toggle[data-met="all"]')?.classList.add('active');
    renderOrdenes();
}

// ---- Abrir / cerrar el modal del selector ----
function openOCModal() {
    ocPendiente = val('new-id-ordencompra');

    // El filtro arranca en el proveedor ya elegido para la factura. Si ya hay
    // un proveedor elegido, el filtro se BLOQUEA para que solo se puedan ver
    // y seleccionar órdenes de ese proveedor (antes se podía cambiar/borrar
    // el filtro y elegir una orden de otro proveedor, que luego pisaba
    // silenciosamente el proveedor del formulario). Si aún no hay proveedor
    // elegido, el filtro queda libre y la orden que se elija define el
    // proveedor de la factura, como ya funcionaba.
    const prov = val('new-id-proveedor');
    setVal('oc-search', '');
    setVal('oc-filtro-proveedor', prov || '');
    setFecha('oc-fec-desde', '');
    setFecha('oc-fec-hasta', '');
    ocMetodo = 'all';
    document.querySelectorAll('.oc-toggle').forEach(b => b.classList.remove('active'));
    document.querySelector('.oc-toggle[data-met="all"]')?.classList.add('active');

    const filtroProv = document.getElementById('oc-filtro-proveedor');
    if (filtroProv) filtroProv.disabled = !!prov;
    setOCProvLockHint(prov);

    renderOrdenes();
    show('modal-oc');
}

// Muestra un aviso cuando el filtro de proveedor está bloqueado por el
// proveedor ya elegido en el formulario principal.
function setOCProvLockHint(prov) {
    const hint = document.getElementById('oc-prov-lock-hint');
    if (!hint) return;
    if (prov) {
        const selProv = document.getElementById('new-id-proveedor');
        const nombre  = selProv?.selectedOptions?.[0]?.textContent?.trim() ?? '';
        hint.textContent = `Mostrando solo órdenes de ${nombre}. Para ver otras, cambie el proveedor de la factura.`;
        hint.style.display = '';
    } else {
        hint.textContent = '';
        hint.style.display = 'none';
    }
}

function closeOCModal() {
    cerrarSelectorFecha();
    hide('modal-oc');
}

function confirmOC() {
    if (!ocPendiente) return;

    const orden = buscarOrden(ocPendiente);
    setVal('new-id-ordencompra', ocPendiente);

    // La orden manda: su proveedor, su saldo por facturar (valor bloqueado)
    // y su modalidad de pago (contado / crédito) pasan a la factura.
    // El valor lo pone actualizarModalidadPago() → actualizarBloqueoValor().
    if (orden) {
        setVal('new-id-proveedor', orden.id_proveedor);
        updateVencimientoPreview();
    }

    renderOCSelected();
    actualizarModalidadPago();
    closeOCModal();
}

function toggleOCPicker() {
    const picker = document.getElementById('oc-picker');
    if (!picker) return;

    if (tieneOrdenCompra()) {
        picker.style.display = '';
        renderOCSelected();
        actualizarModalidadPago();
        // Decir "sí" lleva directo a buscar la orden
        if (!val('new-id-ordencompra')) openOCModal();
    } else {
        picker.style.display = 'none';
        limpiarSeleccionOC();
    }
}

// ============================================================
// 3. MODAL: NUEVA FACTURA
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    const radNo = document.querySelector('input[name="rad_tiene_oc"][value="no"]');
    if (radNo) radNo.checked = true;
    limpiarSeleccionOC();
    toggleOCPicker();
    setVal('new-id-factura', '');
    setVal('new-id-proveedor', '');
    setFecha('new-fec-emision', hoyLocal());
    setVal('new-val-factura', '');
    setVal('new-num-cuotas', '1');
    updateVencimientoPreview();
    actualizarModalidadPago();
    show('modal-new-factura');
}

function closeNewModal() {
    cerrarSelectorFecha();
    hide('modal-new-factura');
}

// ============================================================
// 4. MODAL: DETALLE DE FACTURA (con cuotas)
// ============================================================
function openDetailModal(idFactura) {
    const factura = facturasData.find(f => parseInt(f.id_factura, 10) === idFactura);
    if (!factura) return;

    const pagada      = factura.ind_estado === 't' || factura.ind_estado === true;
    const hoy         = new Date().toISOString().slice(0, 10);
    const estaVencida = !pagada && factura.fec_vencimiento < hoy;
    const estadoTxt   = pagada ? 'Pagada' : (estaVencida ? 'Vencida' : 'En deuda');

    setText('detail-title', `Factura #${factura.id_factura}`);
    setText('detail-subtitle', `${factura.nom_tercero} — ${estadoTxt}`);

    const content = document.getElementById('detail-content');
    content.innerHTML = `
        <div class="detail-grid">
            <div class="detail-item"><span class="detail-label">Proveedor</span><span class="detail-value">${escapeHtml(factura.nom_tercero)}</span></div>
            <div class="detail-item"><span class="detail-label">NIT</span><span class="detail-value">${escapeHtml(factura.id_proveedor)}</span></div>
            <div class="detail-item"><span class="detail-label">Emisión</span><span class="detail-value">${formatDate(factura.fec_emision)}</span></div>
            <div class="detail-item"><span class="detail-label">Vencimiento</span><span class="detail-value">${formatDate(factura.fec_vencimiento)}</span></div>
            <div class="detail-item"><span class="detail-label">Valor Factura</span><span class="detail-value">${formatCurrency(factura.val_factura)}</span></div>
            <div class="detail-item"><span class="detail-label">Saldo Pendiente</span><span class="detail-value">${formatCurrency(factura.val_saldo)}</span></div>
        </div>
        <h4 class="detail-subheading"><i class="fas fa-list"></i> Cuotas (${factura.num_cuotas})</h4>
        <div id="cuotas-list">
            <div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>Cargando cuotas...</p></div>
        </div>
    `;

    show('modal-detail');

    // Cargar cuotas vía fetch
    const formData = new FormData();
    formData.append('btn_ver_cuotas', '1');
    formData.append('hid_id_factura', factura.id_factura);

    fetch(window.location.href, { method: 'POST', body: formData })
        .then(res => res.text())
        .then(text => {
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida del servidor' }; }
            const cuotasList = document.getElementById('cuotas-list');
            if (!cuotasList) return;

            // Error del servidor: se muestra el mensaje real en vez de "no hay cuotas"
            if (!result.success) {
                cuotasList.innerHTML = `<p style="font-size:12px;color:#ef4444;text-align:center;padding:12px">${escapeHtml(result.message || 'Error al cargar las cuotas.')}</p>`;
                return;
            }

            if (result.cuotas && result.cuotas.length > 0) {
                cuotasList.innerHTML = result.cuotas.map(c => {
                    const pagadaCuota = c.ind_pagada === 't' || c.ind_pagada === true;
                    return `
                        <div class="cuota-row">
                            <span class="cuota-num">Cuota ${escapeHtml(c.id_cuota)}</span>
                            <span class="cuota-fecha">${formatDate(c.fec_vencimiento)}</span>
                            <span class="cuota-valor">${formatCurrency(c.val_cuota)}</span>
                            <span class="badge ${pagadaCuota ? 'badge-active' : 'badge-inactive'}">${pagadaCuota ? 'Pagada' : 'Pendiente'}</span>
                        </div>
                    `;
                }).join('');
            } else {
                cuotasList.innerHTML = '<p style="font-size:12px;color:#94a3b8;text-align:center;padding:12px">No se encontraron cuotas para esta factura.</p>';
            }
        })
        .catch(() => {
            const cuotasList = document.getElementById('cuotas-list');
            if (cuotasList) cuotasList.innerHTML = '<p style="font-size:12px;color:#ef4444;text-align:center;padding:12px">Error al cargar las cuotas.</p>';
        });
}

function closeDetailModal() {
    hide('modal-detail');
}

window.openDetailModal = openDetailModal;

// ============================================================
// 5. FILTROS + PAGINACIÓN + ORDENAMIENTO (mismo sistema que Proveedores)
// ============================================================

// ---- ESTADO DE PAGINACIÓN ----
let facturasPage     = 1;
let facturasPageSize = 25; // debe coincidir con el <option selected> de #facturas-page-size

// Filas que pasan la búsqueda y el filtro de estado (sin tener en cuenta la página).
// Se busca en Factura, Orden de Compra y Proveedor (antes no se miraba la
// columna Proveedor, aunque el buscador dice "Buscar por proveedor...").
function getFilteredFacturaRows() {
    const query  = val('factura-search').toLowerCase().trim();
    const active = document.querySelector('#mod-cuentasxpagar .filter-toggle.active')?.dataset.filter ?? 'all';
    const filas  = Array.from(document.querySelectorAll('#facturas-tbody tr:not(.empty-row)'));
    return filas.filter(fila => {
        const texto = [0, 1, 2].map(i => fila.children[i]?.textContent.toLowerCase() ?? '').join(' ');
        const pasaTexto  = !query || texto.includes(query);
        const pasaEstado = active === 'all' || fila.dataset.estado === active;
        return pasaTexto && pasaEstado;
    });
}

// Aplica búsqueda/estado y vuelve a la primera página
function applyFilters() {
    facturasPage = 1;
    renderFacturasPage();

    const query    = val('factura-search').trim();
    const active   = document.querySelector('#mod-cuentasxpagar .filter-toggle.active')?.dataset.filter ?? 'all';
    const clearBtn = document.getElementById('btn-clear-filters');
    if (clearBtn) clearBtn.style.display = (query || active !== 'all') ? 'flex' : 'none';
}

function clearFilters() {
    setVal('factura-search', '');
    document.querySelectorAll('#mod-cuentasxpagar .filter-toggle').forEach(btn => btn.classList.remove('active'));
    document.querySelector('#mod-cuentasxpagar .filter-toggle[data-filter="all"]')?.classList.add('active');
    applyFilters();
}

// Muestra solo las filas que pasan el filtro Y caen en la página actual
function renderFacturasPage() {
    const todas     = Array.from(document.querySelectorAll('#facturas-tbody tr:not(.empty-row)'));
    const coinciden = getFilteredFacturaRows();
    todas.forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = facturasPageSize === 'all';
    const size         = esTodos ? total : facturasPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    if (facturasPage > totalPaginas) facturasPage = totalPaginas;
    if (facturasPage < 1) facturasPage = 1;

    const start = esTodos ? 0 : (facturasPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    setText('facturas-count', `${total} resultado${total !== 1 ? 's' : ''}`);

    const rangeEl = document.getElementById('facturas-range');
    if (rangeEl) {
        rangeEl.textContent = total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`;
    }

    const btnPrev = document.getElementById('facturas-prev');
    const btnNext = document.getElementById('facturas-next');
    if (btnPrev) btnPrev.disabled = facturasPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || facturasPage >= totalPaginas;
}

function initFacturasPagination() {
    document.getElementById('facturas-page-size')?.addEventListener('change', function() {
        facturasPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        facturasPage = 1;
        renderFacturasPage();
    });
    document.getElementById('facturas-prev')?.addEventListener('click', () => {
        facturasPage--;
        renderFacturasPage();
    });
    document.getElementById('facturas-next')?.addEventListener('click', () => {
        facturasPage++;
        renderFacturasPage();
    });
}

// ---- ORDENAMIENTO ASC / DESC ----
// Cada celda ordenable trae su valor "crudo" en data-sort: números sin "$"
// ni puntos, fechas en 'YYYY-MM-DD' y 0 para "Compra directa" (sin orden),
// así esas quedan juntas al principio (asc) o al final (desc).
let facturasSortKey = null; // índice de columna, coincide con data-sort-key del <th>
let facturasSortDir = 'asc';

function sortFacturaRows(key, type) {
    const tbody = document.getElementById('facturas-tbody');
    if (!tbody) return;
    const filas = Array.from(tbody.querySelectorAll('tr:not(.empty-row)'));
    if (filas.length === 0) return;

    facturasSortDir = (facturasSortKey === key && facturasSortDir === 'asc') ? 'desc' : 'asc';
    facturasSortKey = key;

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
        return facturasSortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-cuentasxpagar .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${facturasSortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    facturasPage = 1;
    renderFacturasPage();
}

function initFacturasSorting() {
    document.querySelectorAll('#mod-cuentasxpagar .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortFacturaRows(th.dataset.sortKey, th.dataset.sortType));
    });
}

// ---- ALTO DINÁMICO DE LA TABLA (evita el doble scroll) ----
function ajustarAlturaTablaFacturas() {
    const scrollBox = document.getElementById('facturas-table-scroll');
    if (!scrollBox) return;
    const footer = document.querySelector('#mod-cuentasxpagar .table-footer');
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
    initFacturaModule();
});

function initFacturaModule() {
    // Mover modales, calendario y toast al <body> para que el overlay cubra
    // también la barra superior (escapan del contexto de apilamiento del layout).
    // El orden importa: el selector de OC va después de Nueva Factura para quedar encima.
    ['modal-new-factura', 'modal-oc', 'modal-detail', 'dp-pop', 'toast'].forEach(id => {
        const el = document.getElementById(id);
        if (el && el.parentElement !== document.body) document.body.appendChild(el);
    });

    document.getElementById('btn-add-factura')?.addEventListener('click', openNewModal);

    // ---------- CALENDARIO DE FECHAS ----------
    initSelectorFecha();

    document.querySelectorAll('input[name="rad_tiene_oc"]')
        .forEach(r => r.addEventListener('change', toggleOCPicker));
    document.getElementById('btn-open-oc-modal')?.addEventListener('click', openOCModal);
    document.getElementById('close-oc-modal')?.addEventListener('click', closeOCModal);
    document.getElementById('cancel-oc-modal')?.addEventListener('click', closeOCModal);
    document.getElementById('btn-confirm-oc')?.addEventListener('click', confirmOC);

    // Los modales NO se cierran al hacer clic por fuera (en el fondo oscuro):
    // así no se pierde lo que se lleva escrito en un formulario por un clic
    // accidental. Se cierran solo con la X, "Cancelar" o "Cerrar".

    ['oc-search', 'oc-filtro-proveedor', 'oc-fec-desde', 'oc-fec-hasta'].forEach(id => {
        const el = document.getElementById(id);
        el?.addEventListener(id === 'oc-search' ? 'input' : 'change', renderOrdenes);
    });
    document.getElementById('btn-oc-clear')?.addEventListener('click', clearOCFilters);

    document.querySelectorAll('.oc-toggle').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('.oc-toggle').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            ocMetodo = this.dataset.met;
            renderOrdenes();
        });
    });

    document.getElementById('factura-search')?.addEventListener('input', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    document.querySelectorAll('#mod-cuentasxpagar .filter-toggle').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('#mod-cuentasxpagar .filter-toggle').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            applyFilters();
        });
    });

    // ---------- PAGINACIÓN Y ORDENAMIENTO ----------
    initFacturasPagination();
    initFacturasSorting();
    renderFacturasPage();
    ajustarAlturaTablaFacturas();
    window.addEventListener('resize', ajustarAlturaTablaFacturas);

    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));

    document.getElementById('close-detail-modal')?.addEventListener('click', closeDetailModal);
    document.getElementById('close-detail-btn')?.addEventListener('click', closeDetailModal);

    // Recalcular vencimiento y preview de cuotas en vivo
    document.getElementById('new-id-proveedor')?.addEventListener('change', function() {
        updateVencimientoPreview();
        // Una orden de otro proveedor ya no aplica a esta factura
        const orden = buscarOrden(val('new-id-ordencompra'));
        if (orden && orden.id_proveedor !== this.value) limpiarSeleccionOC();
        // Cada proveedor tiene sus propias condiciones de crédito
        actualizarModalidadPago();
    });
    document.getElementById('new-fec-emision')?.addEventListener('change', updateVencimientoPreview);
    document.getElementById('new-val-factura')?.addEventListener('input', updateCuotaPreview);
    document.getElementById('new-num-cuotas')?.addEventListener('input', function() {
        const msg = errorCuotas();
        if (msg) showFieldError('err-new-cuotas', msg);
        updateCuotaPreview();
    });
    // Al salir del campo, se ajusta al rango permitido
    document.getElementById('new-num-cuotas')?.addEventListener('blur', function() {
        const cond = obtenerCondicionesPago();
        if (!cond || cond.estado !== 'ok') return;
        const n = parseInt(this.value, 10);
        if (!n || n < 1) this.value = 1;
        else if (n > cond.max) this.value = cond.max;
        updateCuotaPreview();
    });

    // ---------- SUBMIT: NUEVA FACTURA ----------
    document.getElementById('new-btn-save')?.addEventListener('click', async function() {
        const form = document.getElementById('new-factura-form');
        clearAllFieldErrors('new');
        if (tieneOrdenCompra() && !val('new-id-ordencompra')) {
            showFieldError('err-new-oc', 'Seleccione la orden de compra de la factura.');
            return;
        }
        const msgCuotas = errorCuotas();
        if (msgCuotas) {
            showFieldError('err-new-cuotas', msgCuotas);
            return;
        }

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
}
