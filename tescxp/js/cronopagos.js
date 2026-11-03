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
// 1.1 FECHAS DE PAGO PERMITIDAS (Parámetros + Festivos)
// ------------------------------------------------------------
// diasPagoPermitidos y festivosMap los inyecta cronopagos.php.
// Numeración de días: 1 = lunes ... 7 = domingo (ISO), igual que
// fec_diapago1..3 en tab_pmtros_tescxp.
// Esta validación es solo de ayuda al usuario: el servidor (PHP)
// y el trigger trg_validar_fecha_cronograma validan de nuevo.
// ============================================================
const NOMBRES_DIA_ISO = { 1: 'lunes', 2: 'martes', 3: 'miércoles', 4: 'jueves', 5: 'viernes', 6: 'sábado', 7: 'domingo' };

// Fecha local en 'YYYY-MM-DD' (toISOString usa UTC y en la noche
// de Colombia ya devolvería el día siguiente)
function isoLocal(fecha) {
    return `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}-${String(fecha.getDate()).padStart(2, '0')}`;
}

function hoyLocal() { return isoLocal(new Date()); }

function diaIso(fechaStr) {
    const [y, m, d] = fechaStr.split('-').map(Number);
    const js = new Date(y, m - 1, d).getDay(); // 0 = domingo
    return js === 0 ? 7 : js;
}

function getDiasPago() {
    return (typeof diasPagoPermitidos !== 'undefined' && Array.isArray(diasPagoPermitidos))
        ? diasPagoPermitidos.map(Number)
        : [];
}

function getFestivos() {
    return (typeof festivosMap !== 'undefined' && festivosMap) ? festivosMap : {};
}

// Devuelve null si la fecha es válida, o el mensaje de error
function validarFechaPago(fechaStr) {
    if (!fechaStr) return 'La fecha de programación es obligatoria.';

    const dias = getDiasPago();
    if (dias.length === 0) return 'No hay días de pago configurados en Parámetros de Tesorería.';

    const dia = diaIso(fechaStr);
    if (!dias.includes(dia)) {
        const permitidos = dias.slice().sort((a, b) => a - b).map(d => NOMBRES_DIA_ISO[d]).join(', ');
        return `El ${NOMBRES_DIA_ISO[dia]} no es día de pago. Días permitidos: ${permitidos}.`;
    }

    const festivo = getFestivos()[fechaStr];
    if (festivo) return `La fecha es festivo (${festivo}). Elija otro día de pago.`;

    return null;
}

// Clasifica un día para pintarlo en los calendarios:
//   'festivo' → festivo activo (bloqueado, color propio)
//   'pasado'  → anterior a hoy (bloqueado)
//   'no-pago' → no es uno de los días de pago de Parámetros (bloqueado)
//   'pago'    → día de pago disponible
function clasificarDia(iso) {
    const festivo = getFestivos()[iso];
    if (festivo)                               return { tipo: 'festivo', titulo: `Festivo: ${festivo}` };
    if (iso < hoyLocal())                      return { tipo: 'pasado',  titulo: 'Fecha pasada' };
    if (!getDiasPago().includes(diaIso(iso)))  return { tipo: 'no-pago', titulo: 'No es día de pago' };
    return { tipo: 'pago', titulo: 'Día de pago disponible' };
}

// Muestra en el botón del campo la fecha elegida (o el texto vacío)
function pintarCampoFecha(hiddenId) {
    const btn   = document.getElementById(`${hiddenId}-btn`);
    const texto = btn?.querySelector('.fecha-pago-texto');
    if (!texto) return;
    const fecha = val(hiddenId);
    if (fecha) {
        const dia = NOMBRES_DIA_ISO[diaIso(fecha)];
        texto.textContent = `${dia.charAt(0).toUpperCase()}${dia.slice(1)}, ${formatDate(fecha)}`;
        texto.classList.remove('vacio');
    } else {
        texto.textContent = 'Seleccione una fecha';
        texto.classList.add('vacio');
    }
    btn.classList.remove('fecha-invalida');
}

// Revisa la fecha elegida (respaldo antes de guardar; el calendario ya
// no deja elegir días bloqueados). Devuelve true si es válida.
function revisarFechaInput(inputId, errId, fechaOriginal = null) {
    const fecha = val(inputId);

    // En edición, si la fecha no cambió no se revalida (igual que el servidor)
    let error = null;
    if (fecha === '') {
        error = 'La fecha de programación es obligatoria.';
    } else if (fecha !== fechaOriginal) {
        error = fecha < hoyLocal()
            ? 'La fecha de programación no puede ser anterior a hoy.'
            : validarFechaPago(fecha);
    }

    document.getElementById(`${inputId}-btn`)?.classList.toggle('fecha-invalida', !!error);
    if (error) showFieldError(errId, error, 6000);
    return !error;
}

// ============================================================
// 1.2 CALENDARIO PARA ELEGIR LA FECHA DE PAGO
// ------------------------------------------------------------
// Reemplaza al <input type="date"> (que no permite bloquear días
// sueltos). Solo se pueden hacer clic en los días de pago; los
// festivos se ven en rojo y los demás días quedan deshabilitados.
// La fecha elegida se guarda en un <input type="hidden"> con el
// mismo id y name que antes, así que el resto del código no cambia.
// ============================================================
const selectorFecha = {
    hiddenId: null,   // input hidden que recibe la fecha
    original: null,   // fecha original (edición): se deja visible aunque ya no sea válida
    anio: 0,
    mes: 0,           // 0-11
};

function abrirSelectorFecha(hiddenId, original = null) {
    const pop = document.getElementById('dp-pop');
    if (!pop) return;

    selectorFecha.hiddenId = hiddenId;
    selectorFecha.original = original;

    // Se abre en el mes de la fecha elegida, o en el mes actual
    const base = val(hiddenId) || hoyLocal();
    const [y, m] = base.split('-').map(Number);
    selectorFecha.anio = y;
    selectorFecha.mes  = m - 1;

    pop.classList.remove('hidden');
    renderSelectorFecha();
    posicionarSelectorFecha();
}

function cerrarSelectorFecha() {
    document.getElementById('dp-pop')?.classList.add('hidden');
    selectorFecha.hiddenId = null;
}

function selectorFechaAbierto() {
    return !document.getElementById('dp-pop')?.classList.contains('hidden');
}

// El calendario es position:fixed para que no lo recorte el scroll del modal
function posicionarSelectorFecha() {
    const pop = document.getElementById('dp-pop');
    const btn = document.getElementById(`${selectorFecha.hiddenId}-btn`);
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

// No se navega a meses anteriores al actual (salvo el de la fecha original)
function mesMinimoSelector() {
    const hoy = hoyLocal();
    const ref = (selectorFecha.original && selectorFecha.original < hoy) ? selectorFecha.original : hoy;
    const [y, m] = ref.split('-').map(Number);
    return y * 12 + (m - 1);
}

function renderSelectorFecha() {
    const { anio, mes, hiddenId, original } = selectorFecha;
    const grid = document.getElementById('dp-grid');
    if (!grid) return;

    setText('dp-titulo', `${MESES[mes]} ${anio}`);
    setText('dp-festivo-info', '');

    const prev = document.getElementById('dp-prev');
    if (prev) prev.disabled = (anio * 12 + mes) <= mesMinimoSelector();

    const seleccion = val(hiddenId);
    const hoy       = hoyLocal();
    const primerDia = new Date(anio, mes, 1).getDay(); // 0 = domingo
    const diasMes   = new Date(anio, mes + 1, 0).getDate();

    let html = '';
    for (let i = 0; i < primerDia; i++) html += '<span class="dp-dia vacio"></span>';

    for (let d = 1; d <= diasMes; d++) {
        const iso = fechaISO(anio, mes, d);
        const { tipo, titulo } = clasificarDia(iso);
        // La fecha original de un cronograma en edición siempre se puede re-elegir
        const habilitado = tipo === 'pago' || iso === original;

        const clases = ['dp-dia', tipo];
        if (iso === hoy)       clases.push('hoy');
        if (iso === seleccion) clases.push('sel');

        html += `<button type="button" class="${clases.join(' ')}" data-fecha="${iso}"
                    title="${escapeHtml(titulo)}" ${habilitado ? '' : 'disabled'}>${d}</button>`;
    }
    grid.innerHTML = html;

    grid.querySelectorAll('.dp-dia:not(.vacio)').forEach(btn => {
        // Al pasar sobre un festivo se muestra su nombre
        btn.addEventListener('mouseenter', () => {
            setText('dp-festivo-info', btn.classList.contains('festivo') ? btn.title : '');
        });
        if (!btn.disabled) {
            btn.addEventListener('click', () => elegirFechaSelector(btn.dataset.fecha));
        }
    });
}

function elegirFechaSelector(iso) {
    const hiddenId = selectorFecha.hiddenId;
    if (!hiddenId) return;
    setVal(hiddenId, iso);
    pintarCampoFecha(hiddenId);
    cerrarSelectorFecha();
    // Un input hidden no dispara 'change' solo: se dispara a mano
    document.getElementById(hiddenId)?.dispatchEvent(new Event('change', { bubbles: true }));
}

function moverMesSelector(delta) {
    let total = selectorFecha.anio * 12 + selectorFecha.mes + delta;
    total = Math.max(total, mesMinimoSelector());
    selectorFecha.anio = Math.floor(total / 12);
    selectorFecha.mes  = total % 12;
    renderSelectorFecha();
    posicionarSelectorFecha();
}

function initSelectorFecha() {
    document.querySelectorAll('.fecha-pago-trigger').forEach(btn => {
        btn.addEventListener('click', e => {
            e.stopPropagation();
            const hiddenId = btn.dataset.target;
            if (selectorFechaAbierto() && selectorFecha.hiddenId === hiddenId) {
                cerrarSelectorFecha();
                return;
            }
            const original = hiddenId === 'edit-fec-prog' ? val('edit-fec-original') : null;
            abrirSelectorFecha(hiddenId, original);
        });
    });

    document.getElementById('dp-prev')?.addEventListener('click', () => moverMesSelector(-1));
    document.getElementById('dp-next')?.addEventListener('click', () => moverMesSelector(1));

    // Cerrar al hacer clic por fuera o con Escape
    document.addEventListener('mousedown', e => {
        if (!selectorFechaAbierto()) return;
        if (e.target.closest('#dp-pop') || e.target.closest('.fecha-pago-trigger')) return;
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
// 2. VISTA: TOGGLE TABLA / CALENDARIO
// ============================================================
function switchView(view) {
    document.querySelectorAll('.view-toggle').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.view === view);
    });
    document.getElementById('view-tabla')?.classList.toggle('active', view === 'tabla');
    document.getElementById('view-calendario')?.classList.toggle('active', view === 'calendario');

    // La barra de búsqueda y filtros solo aplica a la tabla
    document.getElementById('mod-cronograma')?.classList.toggle('vista-calendario', view === 'calendario');

    if (view === 'calendario') {
        renderCalendar();
    } else {
        ajustarAlturaTablaCronos();
    }
}

// ============================================================
// 2.1 CALENDARIO DE CRONOGRAMAS
// ============================================================
let calCurrentYear   = new Date().getFullYear();
let calCurrentMonth  = new Date().getMonth(); // 0-11
let calSelectedDate  = hoyLocal();
let calPrimerRender  = true;

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
const MESES_CORTO = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
const DIAS_SEMANA = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

function getCronogramasPorFecha() {
    const mapa = {};
    (cronogramasData || []).forEach(c => {
        const fecha = c.fec_programacion; // 'YYYY-MM-DD'
        if (!fecha) return;
        if (!mapa[fecha]) mapa[fecha] = [];
        mapa[fecha].push(c);
    });
    return mapa;
}

function estaPagado(crono) {
    return crono.ind_estado === 't' || crono.ind_estado === true;
}

function fechaISO(anio, mes, dia) {
    return `${anio}-${String(mes + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`;
}

// ---- Panel izquierdo: el día seleccionado y sus cronogramas ----
function renderSidePanel() {
    const [anio, mes, dia] = calSelectedDate.split('-').map(Number);
    const fecha = new Date(anio, mes - 1, dia);

    setText('cal-sel-day', String(dia).padStart(2, '0'));
    setText('cal-sel-weekday', DIAS_SEMANA[fecha.getDay()]);
    setText('cal-sel-month', `${MESES[mes - 1]} ${anio}`);

    const cronosDia = getCronogramasPorFecha()[calSelectedDate] || [];
    const lista = document.getElementById('cal-side-list');
    const btn = document.getElementById('cal-side-detail');
    if (!lista) return;

    // Si el día es festivo se avisa arriba de la lista
    const festivo = getFestivos()[calSelectedDate];
    const avisoFestivo = festivo
        ? `<li class="cal-side-festivo"><i class="fas fa-flag"></i> Festivo: ${escapeHtml(festivo)}</li>`
        : '';

    if (cronosDia.length === 0) {
        lista.innerHTML = avisoFestivo + '<li class="cal-side-vacio">No hay pagos programados este día.</li>';
        if (btn) {
            btn.disabled = true;
            const span = btn.querySelector('span');
            if (span) span.textContent = 'Ver detalle del día';
        }
        return;
    }

    // Máximo 3 cronogramas en el panel; el resto se resume en una línea
    // informativa "+N más". El único botón que abre el modal del día es el
    // de abajo, que indica cuántos cronogramas hay cuando no caben todos.
    const MAX_VISIBLES = 3;
    const visibles = cronosDia.slice(0, MAX_VISIBLES);
    const resto = cronosDia.length - visibles.length;

    lista.innerHTML = avisoFestivo + visibles.map(c => {
        const pagado = estaPagado(c);
        return `
            <li class="cal-side-item ${pagado ? 'pagado' : ''}">
                <i></i>
                <span>
                    <span class="cal-side-item-desc">${escapeHtml(c.nom_cronograma)}</span>
                    <span class="cal-side-item-meta">${formatCurrency(c.total_a_pagar)} · ${pagado ? 'Pagado' : 'Pendiente'}${Number(c.cant_rechazadas || 0) > 0 ? ` · ${c.cant_rechazadas} rechazada${Number(c.cant_rechazadas) !== 1 ? 's' : ''}` : ''}</span>
                </span>
            </li>`;
    }).join('') + (resto > 0
        ? `<li class="cal-side-more">+${resto} cronograma${resto !== 1 ? 's' : ''} más</li>`
        : '');

    const btnTexto = btn?.querySelector('span');
    if (btnTexto) {
        btnTexto.textContent = resto > 0
            ? `Ver los ${cronosDia.length} cronogramas`
            : 'Ver detalle del día';
    }

    if (btn) btn.disabled = false;
}

// ---- Tira de meses del año en curso ----
function renderMonthStrip() {
    const strip = document.getElementById('cal-months');
    if (!strip) return;

    strip.innerHTML = MESES_CORTO.map((m, i) => `
        <button type="button" class="cal-month ${i === calCurrentMonth ? 'active' : ''}" data-mes="${i}">${m}</button>
    `).join('');

    strip.querySelectorAll('.cal-month').forEach(btn => {
        btn.addEventListener('click', () => {
            calCurrentMonth = Number(btn.dataset.mes);
            renderCalendar();
        });
    });
}

// Al cambiar de mes se selecciona su primer día con pagos programados, para
// que el panel izquierdo no quede vacío; si no hay ninguno, cae en el día 1.
function seleccionarDiaDelMes() {
    const cronosPorFecha = getCronogramasPorFecha();
    const prefijo = `${calCurrentYear}-${String(calCurrentMonth + 1).padStart(2, '0')}`;

    const tieneP    = (cronosPorFecha[calSelectedDate] || []).length > 0;
    const mismoMes  = calSelectedDate.startsWith(prefijo);

    // Se respeta la selección del usuario; solo se reubica al cambiar de mes
    // o en la primera carga, si el día de hoy no tiene nada programado.
    if (mismoMes && (tieneP || !calPrimerRender)) {
        calPrimerRender = false;
        return;
    }
    calPrimerRender = false;

    const conPagos = Object.keys(cronosPorFecha)
        .filter(f => f.startsWith(prefijo))
        .sort();

    calSelectedDate = conPagos[0] || `${prefijo}-01`;
}

function renderCalendar() {
    const grid = document.getElementById('calendar-grid');
    if (!grid) return;

    seleccionarDiaDelMes();

    setText('cal-year-label', calCurrentYear);
    renderMonthStrip();

    const cronosPorFecha = getCronogramasPorFecha();
    const primerDiaSemana = new Date(calCurrentYear, calCurrentMonth, 1).getDay(); // 0=Dom
    const diasEnMes = new Date(calCurrentYear, calCurrentMonth + 1, 0).getDate();
    const diasMesPrevio = new Date(calCurrentYear, calCurrentMonth, 0).getDate();
    const hoyStr = hoyLocal();

    // La rejilla siempre muestra seis semanas completas: los días del mes
    // vecino se dibujan atenuados en vez de dejar huecos.
    const celdas = [];

    for (let i = primerDiaSemana; i > 0; i--) {
        celdas.push({ dia: diasMesPrevio - i + 1, otroMes: true, fecha: null });
    }
    for (let dia = 1; dia <= diasEnMes; dia++) {
        celdas.push({ dia, otroMes: false, fecha: fechaISO(calCurrentYear, calCurrentMonth, dia) });
    }
    let siguiente = 1;
    while (celdas.length % 7 !== 0 || celdas.length < 42) {
        celdas.push({ dia: siguiente++, otroMes: true, fecha: null });
        if (celdas.length >= 42) break;
    }

    grid.innerHTML = celdas.map(celda => {
        if (celda.otroMes) {
            return `<div class="cal-day otro-mes"><span class="cal-day-num">${String(celda.dia).padStart(2, '0')}</span></div>`;
        }

        const cronosDia = cronosPorFecha[celda.fecha] || [];
        const clases = ['cal-day'];
        let dotHtml = '';
        let titulo = '';

        // Festivos en rojo; los días que no son de pago, atenuados
        const festivo = getFestivos()[celda.fecha];
        if (festivo) {
            clases.push('festivo');
            titulo = `Festivo: ${festivo}`;
        } else if (!getDiasPago().includes(diaIso(celda.fecha))) {
            clases.push('no-pago');
        }

        if (cronosDia.length > 0) {
            clases.push('has-crono');
            const hayPendientes = cronosDia.some(c => !estaPagado(c));
            dotHtml = `<span class="cal-day-dot ${hayPendientes ? 'pendiente' : 'pagado'}"></span>`;
        }
        if (celda.fecha === hoyStr) clases.push('hoy');
        if (celda.fecha === calSelectedDate) clases.push('sel');

        return `
            <div class="${clases.join(' ')}" data-fecha="${celda.fecha}"${titulo ? ` title="${escapeHtml(titulo)}"` : ''}>
                <span class="cal-day-num">${String(celda.dia).padStart(2, '0')}</span>
                ${dotHtml}
            </div>`;
    }).join('');

    // Un clic selecciona el día: el detalle se muestra en el panel izquierdo
    // (también los festivos, para ver su nombre en el panel)
    grid.querySelectorAll('.cal-day.has-crono, .cal-day.festivo').forEach(dayEl => {
        dayEl.addEventListener('click', () => {
            calSelectedDate = dayEl.dataset.fecha;
            renderCalendar();
            renderSidePanel();
        });
    });

    renderSidePanel();
}

function changeYear(delta) {
    calCurrentYear += delta;
    renderCalendar();
}

// ============================================================
// 2.2 MODAL: CRONOGRAMAS DE UN DÍA
// ============================================================
function openDayModal(fechaStr) {
    const cronosPorFecha = getCronogramasPorFecha();
    const cronosDia = cronosPorFecha[fechaStr] || [];

    setText('day-modal-title', 'Cronogramas del día');
    setText('day-modal-subtitle', formatDate(fechaStr));

    const list = document.getElementById('day-modal-list');
    if (!list) return;

    if (cronosDia.length === 0) {
        list.innerHTML = '<p style="font-size:12px;color:#94a3b8;text-align:center;padding:12px">No hay cronogramas programados este día.</p>';
    } else {
        list.innerHTML = cronosDia.map(c => {
            const pagado = estaPagado(c);
            const rech   = Number(c.cant_rechazadas || 0);
            const badge = pagado
                ? '<span class="badge badge-active">Pagado</span>'
                : '<span class="badge badge-inactive" style="background:#fffbeb;color:#f59e0b">Pendiente</span>';
            return `
                <div class="day-crono-row" data-id="${c.id_cronograma}">
                    <div class="day-crono-info">
                        <span class="day-crono-nombre">${escapeHtml(c.nom_cronograma)}</span>
                        <span class="day-crono-total">${formatCurrency(c.total_a_pagar)}${rech > 0 ? ` · <b style="color:#b91c1c">${rech} rechazada${rech !== 1 ? 's' : ''}</b>` : ''}</span>
                    </div>
                    ${badge}
                    <i class="fas fa-chevron-right" style="color:#94a3b8;font-size:12px"></i>
                </div>
            `;
        }).join('');

        list.querySelectorAll('.day-crono-row').forEach(row => {
            row.addEventListener('click', () => {
                const crono = cronosDia.find(c => String(c.id_cronograma) === row.dataset.id);
                if (crono) {
                    closeDayModal();
                    openDetailModal(crono);
                }
            });
        });
    }

    show('modal-day');
}

function closeDayModal() {
    hide('modal-day');
}

// ============================================================
// 3. SELECCIÓN DE CUOTAS (checkboxes + total en vivo)
// ============================================================
function updateSeleccionCuotas() {
    const checkboxes = document.querySelectorAll('.cuota-checkbox:checked');
    const claves = Array.from(checkboxes).map(cb => cb.value);
    const total  = Array.from(checkboxes).reduce((sum, cb) => sum + parseFloat(cb.dataset.valor || '0'), 0);

    setVal('hid-cuotas-seleccionadas', claves.join(','));
    setText('crono-total-seleccionado', formatCurrency(total));
}

// ============================================================
// 3.1 MARCAR CUOTAS QUE VENCEN ANTES DE LA FECHA PROGRAMADA
// ------------------------------------------------------------
// - Todas las cuotas siempre están visibles y se pueden seleccionar.
// - Cada vez que cambia la fecha se reevalúan: las que vencen ANTES de
//   la fecha programada muestran la alerta roja "Vence antes de la fecha
//   programada"; las demás la ocultan.
// - Al guardar, si hay cuotas seleccionadas en ese estado, se pide
//   confirmación listando cuáles son (ver confirmarCuotasVencidas).
// ============================================================
function venceAntesDeFecha(cb, fecha) {
    return fecha !== '' && (cb.dataset.vence || '') !== '' && cb.dataset.vence < fecha;
}

function marcarCuotasPorFecha() {
    const fecha = val('new-fec-prog');
    let venceAntes = 0;

    document.querySelectorAll('.cuota-checkbox').forEach(cb => {
        const antes = venceAntesDeFecha(cb, fecha);
        cb.closest('.cuota-picker-row')?.classList.toggle('vence-antes', antes);
        if (antes) venceAntes++;
    });

    setText('cuotas-vencen-antes-info', venceAntes
        ? `${venceAntes} cuota(s) vencen antes del ${formatDate(fecha)}. Puede incluirlas, pero se le pedirá confirmación al guardar.`
        : '');
}

// Cuotas seleccionadas que vencen antes de la fecha programada
function getCuotasSeleccionadasVencidas() {
    const fecha = val('new-fec-prog');
    return Array.from(document.querySelectorAll('.cuota-checkbox:checked'))
        .filter(cb => venceAntesDeFecha(cb, fecha))
        .map(cb => {
            const [idFactura, idCuota] = cb.value.split(':');
            const proveedor = (cb.closest('.cuota-picker-row')
                ?.querySelector('.cuota-picker-prov')?.textContent || '')
                .split(' — ')[0].trim();
            return { idFactura, idCuota, proveedor, vence: cb.dataset.vence, valor: cb.dataset.valor };
        });
}

// ============================================================
// 3.2 MODAL: CONFIRMAR CUOTAS QUE VENCEN ANTES DE LA FECHA
// ============================================================
function confirmarCuotasVencidas(vencidas) {
    const fecha = val('new-fec-prog');
    setText('confirm-vencidas-body',
        `Está incluyendo ${vencidas.length} cuota(s) que vencen antes de la fecha de pago programada (${formatDate(fecha)}):`);

    const lista = document.getElementById('confirm-vencidas-list');
    if (lista) {
        lista.innerHTML = vencidas.map(v => `
            <li>
                <span class="cv-principal">
                    <strong>Factura #${escapeHtml(v.idFactura)} · Cuota ${escapeHtml(v.idCuota)}</strong>
                    <small>${escapeHtml(v.proveedor)} · ${formatCurrency(v.valor)}</small>
                </span>
                <span class="cv-vence">Vence ${formatDate(v.vence)}</span>
            </li>
        `).join('');
    }

    show('modal-confirm-vencidas');
}

function cerrarConfirmVencidas() {
    hide('modal-confirm-vencidas');
}

// ============================================================
// 3. MODAL: NUEVO CRONOGRAMA
// ============================================================
function openNewModal() {
    clearAllFieldErrors('new');
    setVal('new-nom-crono', '');
    setVal('new-fec-prog', '');
    setVal('hid-cuotas-seleccionadas', '');
    pintarCampoFecha('new-fec-prog');
    document.querySelectorAll('.cuota-checkbox').forEach(cb => { cb.checked = false; });
    updateSeleccionCuotas();
    marcarCuotasPorFecha();
    show('modal-new-crono');
}

// Envía el formulario del nuevo cronograma al servidor
async function enviarNuevoCronograma() {
    const form = document.getElementById('new-crono-form');
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
}

function closeNewModal() {
    cerrarSelectorFecha();
    hide('modal-new-crono');
}

// ============================================================
// 4. MODAL: EDITAR CRONOGRAMA
// ============================================================
function openEditModal(crono) {
    // Un cronograma ya pagado no se puede editar (el servidor también lo valida)
    if (estaPagado(crono)) {
        showToast('El cronograma ya fue pagado y no se puede editar.', 'error');
        return;
    }

    clearAllFieldErrors('edit');
    setVal('edit-crono-id', crono.id_cronograma);
    setVal('edit-nom-crono', crono.nom_cronograma);
    setVal('edit-fec-prog', crono.fec_programacion);
    setVal('edit-fec-original', crono.fec_programacion);
    pintarCampoFecha('edit-fec-prog');
    show('modal-edit-crono');
}

function closeEditModal() {
    cerrarSelectorFecha();
    hide('modal-edit-crono');
}

window.openEditModal = openEditModal;

// ============================================================
// 5. MODAL: DETALLE DE CRONOGRAMA
// ------------------------------------------------------------
// Cada cuota trae estado_cuota (lo calcula $list_det_cronopagos):
//   PAGADA · RECHAZADA · PENDIENTE · EN_ARCHIVO · SIN_ENVIAR
// Un cronograma "Pagado" puede tener cuotas rechazadas: se cerró porque el
// banco ya respondió todo. Las rechazadas vuelven a la lista de cuotas
// pendientes para incluirlas en un cronograma nuevo.
// ============================================================
const ESTADOS_CUOTA = {
    PAGADA:     { texto: 'Pagada',            clase: 'pagada',     icono: 'fa-circle-check' },
    RECHAZADA:  { texto: 'Rechazada',         clase: 'rechazada',  icono: 'fa-circle-xmark' },
    PENDIENTE:  { texto: 'Pendiente banco',   clase: 'pendiente',  icono: 'fa-clock' },
    EN_ARCHIVO: { texto: 'Enviada al banco',  clase: 'en-archivo', icono: 'fa-paper-plane' },
    SIN_ENVIAR: { texto: 'Sin enviar',        clase: 'sin-enviar', icono: 'fa-circle' },
};

function estadoCuota(d) {
    return ESTADOS_CUOTA[d.estado_cuota] || ESTADOS_CUOTA.SIN_ENVIAR;
}

function renderResumenCuotas(detalle) {
    const cuenta = {};
    detalle.forEach(d => { cuenta[d.estado_cuota] = (cuenta[d.estado_cuota] || 0) + 1; });

    const chips = ['PAGADA', 'RECHAZADA', 'PENDIENTE', 'EN_ARCHIVO', 'SIN_ENVIAR']
        .filter(k => cuenta[k])
        .map(k => {
            const e = ESTADOS_CUOTA[k];
            return `<span class="cuota-estado ${e.clase}"><i class="fas ${e.icono}"></i> ${cuenta[k]} ${e.texto.toLowerCase()}</span>`;
        }).join('');

    return `<div class="cuotas-resumen">${chips}</div>`;
}

function renderCuotaDetalle(d, crono, pagado) {
    const e = estadoCuota(d);

    // Datos de la respuesta del banco bajo el nombre del proveedor
    let respuesta = '';
    if (d.estado_cuota === 'RECHAZADA') {
        respuesta = `<span class="cuota-motivo rechazo">
                <i class="fas fa-circle-exclamation"></i>
                ${escapeHtml(d.des_motivo || 'Sin motivo registrado')}${d.id_codigo ? ' (' + escapeHtml(d.id_codigo) + ')' : ''}
                · Archivo #${escapeHtml(d.id_archivo_plano)}${d.fec_pago ? ' · ' + formatDate(d.fec_pago) : ''}
            </span>`;
    } else if (d.estado_cuota === 'PAGADA' && d.id_pago) {
        respuesta = `<span class="cuota-motivo">Archivo #${escapeHtml(d.id_archivo_plano)}${d.fec_pago ? ' · pagada el ' + formatDate(d.fec_pago) : ''}</span>`;
    }

    // Solo se puede quitar una cuota que todavía no ha ido al banco
    const puedeEliminar = !pagado && d.estado_cuota === 'SIN_ENVIAR';
    const accion = puedeEliminar
        ? `<button class="btn-icon-sm reject btn-del-detalle"
                data-cronograma="${crono.id_cronograma}"
                data-factura="${d.id_factura}"
                data-cuota="${d.id_cuota}"
                title="Eliminar cuota del cronograma">
                <i class="fas fa-trash"></i>
           </button>`
        : '<span></span>';

    return `
        <div class="cuota-row estado-${e.clase}">
            <span class="cuota-num">
                ${escapeHtml(d.nom_tercero)}<br>
                <small style="color:#94a3b8;font-weight:400">Factura #${d.id_factura}, Cuota ${d.id_cuota} · Vence ${formatDate(d.fec_vencimiento)}</small>
                ${respuesta}
            </span>
            <span class="cuota-estado ${e.clase}"><i class="fas ${e.icono}"></i> ${e.texto}</span>
            <span class="cuota-valor">${formatCurrency(d.val_a_pagar)}</span>
            ${accion}
        </div>`;
}

function openDetailModal(crono) {
    window._cronoDetalleActual = crono;
    const pagado = estaPagado(crono);
    const rechazadas = Number(crono.cant_rechazadas || 0);

    setText('detail-title', crono.nom_cronograma);
    setText('detail-subtitle', `#${crono.id_cronograma} — ${pagado
        ? (rechazadas > 0 ? `Pagado (con ${rechazadas} rechazada${rechazadas !== 1 ? 's' : ''})` : 'Pagado')
        : 'Pendiente'}`);

    const avisoCerrado = pagado ? `
        <div class="crono-cerrado-aviso">
            <i class="fas fa-lock"></i>
            <span>El banco ya respondió este cronograma, así que quedó cerrado y no se puede editar.${rechazadas > 0
                ? ' Las cuotas rechazadas siguen sin pagar: ya están disponibles para incluirlas en un cronograma nuevo.'
                : ''}</span>
        </div>` : '';

    const content = document.getElementById('detail-content');
    content.innerHTML = `
        ${avisoCerrado}
        <div class="detail-grid">
            <div class="detail-item"><span class="detail-label">Fecha Programada</span><span class="detail-value">${formatDate(crono.fec_programacion)}</span></div>
            <div class="detail-item"><span class="detail-label">Total a Pagar</span><span class="detail-value">${formatCurrency(crono.total_a_pagar)}</span></div>
        </div>
    `;

    show('modal-detail');

    const detalleList = document.getElementById('detalle-cuotas-list');
    if (detalleList) detalleList.innerHTML = '<div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>Cargando...</p></div>';

    const formData = new FormData();
    formData.append('btn_ver_detalle', '1');
    formData.append('hid_id_cronograma', crono.id_cronograma);

    fetch(window.location.href, { method: 'POST', body: formData })
        .then(res => res.text())
        .then(text => {
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false }; }
            if (!detalleList) return;

            if (result.success && result.detalle && result.detalle.length > 0) {
                detalleList.innerHTML = renderResumenCuotas(result.detalle)
                    + result.detalle.map(d => renderCuotaDetalle(d, crono, pagado)).join('');

                // Conectar los botones de eliminar recién creados
                detalleList.querySelectorAll('.btn-del-detalle').forEach(btn => {
                    btn.addEventListener('click', () => eliminarDetalleCronograma(
                        btn.dataset.cronograma,
                        btn.dataset.factura,
                        btn.dataset.cuota
                    ));
                });
            } else {
                detalleList.innerHTML = '<p style="font-size:12px;color:#94a3b8;text-align:center;padding:12px">No se encontraron cuotas para este cronograma.</p>';
            }
        })
        .catch(() => {
            if (detalleList) detalleList.innerHTML = '<p style="font-size:12px;color:#ef4444;text-align:center;padding:12px">Error al cargar el detalle.</p>';
        });
}

function closeDetailModal() {
    hide('modal-detail');
}

window.openDetailModal = openDetailModal;

// ============================================================
// 5.1 MODAL DE CONFIRMACIÓN DE ELIMINACIÓN (estilo módulo Compras)
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
// 5.2 ELIMINAR LÍNEA DE DETALLE DEL CRONOGRAMA
// ============================================================
function eliminarDetalleCronograma(idCronograma, idFactura, idCuota) {
    abrirConfirmEliminar(
        `Eliminar Cuota ${idCuota}`,
        `¿Eliminar la Cuota ${idCuota} de la Factura #${idFactura} del cronograma? Esta acción no se puede deshacer.`,
        () => ejecutarEliminarDetalleCronograma(idCronograma, idFactura, idCuota)
    );
}

function ejecutarEliminarDetalleCronograma(idCronograma, idFactura, idCuota) {
    const formData = new FormData();
    formData.append('btn_eliminar_detalle', '1');
    formData.append('hid_det_id_cronograma', idCronograma);
    formData.append('hid_det_id_factura',    idFactura);
    formData.append('hid_det_id_cuota',      idCuota);

    fetch(window.location.href, { method: 'POST', body: formData })
        .then(res => res.text())
        .then(text => {
            let result;
            try { result = JSON.parse(text); } catch (e) { result = { success: false, message: 'Respuesta inválida' }; }

            if (result.success) {
                showToast(result.message, 'success');
                // Recargar el detalle sin cerrar el modal
                const cronoActual = window._cronoDetalleActual;
                if (cronoActual) {
                    // Actualizar el total en el header del modal (el trigger lo recalculó en BD)
                    openDetailModal(cronoActual);
                }
            } else {
                showToast(result.message || 'Error al eliminar la cuota', 'error');
            }
        })
        .catch(() => showToast('Error de conexión', 'error'));
}

// ============================================================
// 6. ELIMINAR CRONOGRAMA (función global)
// ============================================================
window.eliminarCronograma = function(id, nombre) {
    // Un cronograma ya pagado no se puede eliminar (el servidor también lo valida)
    const crono = (cronogramasData || []).find(c => String(c.id_cronograma) === String(id));
    if (crono && estaPagado(crono)) {
        showToast('El cronograma ya fue pagado y no se puede eliminar.', 'error');
        return;
    }

    abrirConfirmEliminar(
        `Eliminar "${nombre}"`,
        `¿Desea eliminar el cronograma "${nombre}"? Esta acción es reversible desde la base de datos.`,
        () => ejecutarEliminarCronograma(id)
    );
};

function ejecutarEliminarCronograma(id) {
    const formData = new FormData();
    formData.append('btn_eliminar', '1');
    formData.append('hid_del_id', id);
    fetch(window.location.href, { method: 'POST', body: formData })
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
// 7. FILTROS + PAGINACIÓN + ORDENAMIENTO (mismo sistema que Proveedores)
// ------------------------------------------------------------
// Solo aplica a la vista Tabla. En la vista Calendario la barra de
// filtros (con el selector de filas por página) se oculta sola.
// ============================================================

// ---- ESTADO DE PAGINACIÓN ----
let cronosPage     = 1;
let cronosPageSize = 25; // debe coincidir con el <option selected> de #cronos-page-size

// Filas que pasan la búsqueda y el filtro Todos/Pendientes/Pagados (sin tener en cuenta la página)
function getFilteredCronoRows() {
    const query  = val('crono-search').toLowerCase().trim();
    const active = document.querySelector('#mod-cronograma .filter-toggle.active')?.dataset.filter ?? 'all';
    const filas  = Array.from(document.querySelectorAll('#cronos-tbody tr:not(.empty-row)'));
    return filas.filter(fila => {
        const nombre = fila.children[0]?.textContent.toLowerCase() ?? '';
        const pasaTexto  = !query || nombre.includes(query);
        const pasaEstado = active === 'all' || fila.dataset.estado === active;
        return pasaTexto && pasaEstado;
    });
}

// Aplica búsqueda/estado y vuelve a la primera página
function applyFilters() {
    cronosPage = 1;
    renderCronosPage();

    const query    = val('crono-search').trim();
    const active   = document.querySelector('#mod-cronograma .filter-toggle.active')?.dataset.filter ?? 'all';
    const clearBtn = document.getElementById('btn-clear-filters');
    if (clearBtn) clearBtn.style.display = (query || active !== 'all') ? 'flex' : 'none';
}

function clearFilters() {
    setVal('crono-search', '');
    document.querySelectorAll('#mod-cronograma .filter-toggle').forEach(btn => btn.classList.remove('active'));
    document.querySelector('#mod-cronograma .filter-toggle[data-filter="all"]')?.classList.add('active');
    applyFilters();
}

// Muestra solo las filas que pasan el filtro Y caen en la página actual
function renderCronosPage() {
    const todas     = Array.from(document.querySelectorAll('#cronos-tbody tr:not(.empty-row)'));
    const coinciden = getFilteredCronoRows();
    todas.forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = cronosPageSize === 'all';
    const size         = esTodos ? total : cronosPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    if (cronosPage > totalPaginas) cronosPage = totalPaginas;
    if (cronosPage < 1) cronosPage = 1;

    const start = esTodos ? 0 : (cronosPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    setText('cronos-count', `${total} resultado${total !== 1 ? 's' : ''}`);

    const rangeEl = document.getElementById('cronos-range');
    if (rangeEl) {
        rangeEl.textContent = total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`;
    }

    const btnPrev = document.getElementById('cronos-prev');
    const btnNext = document.getElementById('cronos-next');
    if (btnPrev) btnPrev.disabled = cronosPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || cronosPage >= totalPaginas;
}

function initCronosPagination() {
    document.getElementById('cronos-page-size')?.addEventListener('change', function() {
        cronosPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        cronosPage = 1;
        renderCronosPage();
    });
    document.getElementById('cronos-prev')?.addEventListener('click', () => {
        cronosPage--;
        renderCronosPage();
    });
    document.getElementById('cronos-next')?.addEventListener('click', () => {
        cronosPage++;
        renderCronosPage();
    });
}

// ---- ORDENAMIENTO ASC / DESC ----
// Cada celda ordenable trae su valor "crudo" en data-sort: el nombre,
// la fecha en 'YYYY-MM-DD' y el total como número (no "$1.500.000").
let cronosSortKey = null; // índice de columna, coincide con data-sort-key del <th>
let cronosSortDir = 'asc';

function sortCronoRows(key, type) {
    const tbody = document.getElementById('cronos-tbody');
    if (!tbody) return;
    const filas = Array.from(tbody.querySelectorAll('tr:not(.empty-row)'));
    if (filas.length === 0) return;

    cronosSortDir = (cronosSortKey === key && cronosSortDir === 'asc') ? 'desc' : 'asc';
    cronosSortKey = key;

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
        return cronosSortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-cronograma .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${cronosSortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    cronosPage = 1;
    renderCronosPage();
}

function initCronosSorting() {
    document.querySelectorAll('#mod-cronograma .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortCronoRows(th.dataset.sortKey, th.dataset.sortType));
    });
}

// ---- ALTO DINÁMICO DE LA TABLA (evita el doble scroll) ----
// Si la vista Tabla está oculta (se está viendo el Calendario) no se mide:
// se vuelve a calcular al regresar a la tabla (ver switchView).
function ajustarAlturaTablaCronos() {
    const scrollBox = document.getElementById('cronos-table-scroll');
    if (!scrollBox || scrollBox.offsetParent === null) return;
    const footer = document.querySelector('#mod-cronograma .table-footer');
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
// 8. INICIALIZACIÓN GENERAL
// ============================================================
document.addEventListener('DOMContentLoaded', function() {
    initCronoModule();
});

function initCronoModule() {
    // Mover modales, calendario y toast al <body> para que el overlay cubra
    // también la barra superior (escapan del contexto de apilamiento del layout).
    // El orden importa: las confirmaciones van al final para quedar encima del
    // modal que las abre (detalle → eliminar cuota, nuevo → cuotas vencidas).
    ['modal-day', 'modal-new-crono', 'modal-edit-crono', 'modal-detail',
     'modal-confirm-eliminar', 'modal-confirm-vencidas', 'dp-pop', 'toast'].forEach(id => {
        const el = document.getElementById(id);
        if (el && el.parentElement !== document.body) document.body.appendChild(el);
    });

    document.getElementById('btn-add-crono')?.addEventListener('click', openNewModal);

    document.getElementById('crono-search')?.addEventListener('input', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    document.querySelectorAll('#mod-cronograma .filter-toggle').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('#mod-cronograma .filter-toggle').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            applyFilters();
        });
    });

    // ---------- PAGINACIÓN Y ORDENAMIENTO (vista Tabla) ----------
    initCronosPagination();
    initCronosSorting();
    renderCronosPage();
    ajustarAlturaTablaCronos();
    window.addEventListener('resize', ajustarAlturaTablaCronos);

    // ---------- TOGGLE TABLA / CALENDARIO ----------
    document.querySelectorAll('.view-toggle').forEach(btn => {
        btn.addEventListener('click', () => switchView(btn.dataset.view));
    });
    document.getElementById('cal-prev-year')?.addEventListener('click', () => changeYear(-1));
    document.getElementById('cal-next-year')?.addEventListener('click', () => changeYear(1));
    document.getElementById('cal-side-detail')?.addEventListener('click', () => openDayModal(calSelectedDate));
    document.getElementById('close-day-modal')?.addEventListener('click', closeDayModal);
    document.getElementById('close-day-btn')?.addEventListener('click', closeDayModal);

    // Los modales NO se cierran al hacer clic por fuera (en el fondo oscuro):
    // así no se pierde lo que se lleva escrito en un formulario por un clic
    // accidental. Se cierran solo con la X, "Cancelar" o "Cerrar".

    document.querySelectorAll('.cuota-checkbox').forEach(cb => {
        cb.addEventListener('change', updateSeleccionCuotas);
    });

    // ---------- CALENDARIO DE FECHA DE PAGO ----------
    initSelectorFecha();

    // Al elegir la fecha programada se marcan las cuotas que vencen antes
    document.getElementById('new-fec-prog')?.addEventListener('change', marcarCuotasPorFecha);

    // ---------- MODAL: CONFIRMAR CUOTAS QUE VENCEN ANTES ----------
    document.getElementById('confirm-vencidas-cancel-btn')?.addEventListener('click', cerrarConfirmVencidas);
    document.getElementById('confirm-vencidas-ok-btn')?.addEventListener('click', () => {
        cerrarConfirmVencidas();
        enviarNuevoCronograma();
    });

    document.querySelectorAll('.btn-close-new-modal, .btn-cancel-new-modal')
        .forEach(btn => btn.addEventListener('click', closeNewModal));
    document.querySelectorAll('.btn-close-edit-modal, .btn-cancel-edit-modal')
        .forEach(btn => btn.addEventListener('click', closeEditModal));

    document.getElementById('close-detail-modal')?.addEventListener('click', closeDetailModal);
    document.getElementById('close-detail-btn')?.addEventListener('click', closeDetailModal);


    // ---------- MODAL: CONFIRMAR ELIMINACIÓN ----------
    document.getElementById('confirm-eliminar-cancel-btn')?.addEventListener('click', cerrarConfirmEliminar);
    document.getElementById('confirm-eliminar-ok-btn')?.addEventListener('click', () => {
        const accion = _confirmDeleteAction;
        cerrarConfirmEliminar();
        if (typeof accion === 'function') accion();
    });

    // ---------- SUBMIT: NUEVO CRONOGRAMA ----------
    // 1) La fecha debe ser día de pago y no festivo (si no, no se envía).
    // 2) Si hay cuotas seleccionadas que vencen antes de la fecha programada,
    //    se muestra la advertencia; solo al aceptar se envía.
    document.getElementById('new-btn-save')?.addEventListener('click', function() {
        clearAllFieldErrors('new');

        if (!revisarFechaInput('new-fec-prog', 'err-new-fecha')) {
            return;
        }

        const vencidas = getCuotasSeleccionadasVencidas();
        if (vencidas.length > 0) {
            confirmarCuotasVencidas(vencidas);
        } else {
            enviarNuevoCronograma();
        }
    });

    // ---------- SUBMIT: EDITAR CRONOGRAMA ----------
    document.getElementById('edit-btn-save')?.addEventListener('click', async function() {
        const form = document.getElementById('edit-crono-form');
        clearAllFieldErrors('edit');

        if (!revisarFechaInput('edit-fec-prog', 'err-edit-fecha', val('edit-fec-original'))) {
            return;
        }

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
}
