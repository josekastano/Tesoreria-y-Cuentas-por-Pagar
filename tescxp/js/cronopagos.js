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
    toast.classList.toggle('toast-error', type === 'error');
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
        btn.setAttribute('aria-pressed', btn.dataset.view === view ? 'true' : 'false');
    });
    document.getElementById('view-tabla')?.classList.toggle('active', view === 'tabla');
    document.getElementById('view-calendario')?.classList.toggle('active', view === 'calendario');

    // La barra de búsqueda y filtros solo aplica a la tabla
    document.getElementById('mod-cronograma')?.classList.toggle('vista-calendario', view === 'calendario');

    // Lista fija (componente "lista_fija"): solo en la vista Tabla. En el calendario
    // no hay lista ([data-lista]) y la página se desplaza normal.
    const tabla = document.getElementById('view-tabla');
    if (view === 'calendario') {
        tabla?.removeAttribute('data-lista');
        renderCalendar();
    } else {
        tabla?.setAttribute('data-lista', '');
    }
    if (window.ErpListaFija) ErpListaFija.ajustar();
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
        list.innerHTML = '<p class="tcx-lista-msg">No hay cronogramas programados este día.</p>';
    } else {
        list.innerHTML = cronosDia.map(c => {
            const pagado = estaPagado(c);
            const rech   = Number(c.cant_rechazadas || 0);
            const badge = pagado
                ? '<span class="badge ok">Pagado</span>'
                : '<span class="badge warn">Pendiente</span>';
            return `
                <div class="day-crono-row" data-id="${c.id_cronograma}">
                    <div class="day-crono-info">
                        <span class="day-crono-nombre">${escapeHtml(c.nom_cronograma)}</span>
                        <span class="day-crono-total">${formatCurrency(c.total_a_pagar)}${rech > 0 ? ` · <b class="tcx-rechazo">${rech} rechazada${rech !== 1 ? 's' : ''}</b>` : ''}</span>
                    </div>
                    ${badge}
                    <i class="fas fa-chevron-right day-crono-ir" aria-hidden="true"></i>
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
        ? `<button type="button" class="btn-icon-sm reject btn-del-detalle"
                data-cronograma="${crono.id_cronograma}"
                data-factura="${d.id_factura}"
                data-cuota="${d.id_cuota}"
                title="Eliminar cuota del cronograma" aria-label="Quitar la cuota ${d.id_cuota} de la factura ${d.id_factura}">
                <i class="fas fa-trash"></i>
           </button>`
        : '<span></span>';

    return `
        <div class="cuota-row estado-${e.clase}">
            <span class="cuota-num">
                ${escapeHtml(d.nom_tercero)}<br>
                <small class="cuota-sub">Factura #${d.id_factura}, Cuota ${d.id_cuota} · Vence ${formatDate(d.fec_vencimiento)}</small>
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
                detalleList.innerHTML = '<p class="tcx-lista-msg">No se encontraron cuotas para este cronograma.</p>';
            }
        })
        .catch(() => {
            if (detalleList) detalleList.innerHTML = '<p class="tcx-lista-msg error">Error al cargar el detalle.</p>';
        });
}

function closeDetailModal() {
    hide('modal-detail');
}


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
// 7. LISTA: INDICADORES, FILTROS, ORDEN Y PAGINADOR (vista Tabla)
// La tabla la pinta este archivo desde cronogramasData (PHP). Paginador y
// orden: componentes compartidos del ERP (erp_ui.js) — GUIA_PANTALLAS_ERP §4-§5.
// Sin botón de "ver": clic (o Enter/espacio) en la fila abre el detalle.
// ============================================================
let pag = null, orden = null;
const normCro = t => (window.erpNormalizar ? erpNormalizar(t) : String(t ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim());
const datosCro = () => (typeof cronogramasData !== 'undefined' && Array.isArray(cronogramasData) ? cronogramasData : []);
const fechaCortaCro = v => String(v || '').slice(0, 10);

function updateStats() {
    const data = datosCro();
    const pagados = data.filter(estaPagado);
    const pendientes = data.filter(c => !estaPagado(c));
    const conRechazo = pagados.filter(c => Number(c.cant_rechazadas || 0) > 0).length;
    setText('stat-total', data.length);
    setText('stat-pendientes', pendientes.length);
    setText('stat-pagados', pagados.length);
    setText('stat-pagados-hint', conRechazo ? `${conRechazo} con cuotas rechazadas` : 'El banco ya respondió');
    setText('stat-programado', formatCurrency(pendientes.reduce((t, c) => t + (Number(c.total_a_pagar) || 0), 0)));
    setText('cro-cnt-all', data.length);
    setText('cro-cnt-pendiente', pendientes.length);
    setText('cro-cnt-pagado', pagados.length);
}

function prepararLista() {
    if (!pag && window.ErpPaginador) {
        pag = ErpPaginador.crear({ lista: document.getElementById('cronos-tbody'), onCambio: renderCronos, tam: 25 });
    }
    if (!orden && window.ErpOrden) {
        orden = ErpOrden.crear({
            tabla: document.getElementById('cronos-table'),
            columnas: {
                'Cronograma':       { valor: c => c.nom_cronograma },
                'Fecha programada': { valor: c => fechaCortaCro(c.fec_programacion), tipo: 'fecha' },
                'Total a pagar':    { valor: c => Number(c.total_a_pagar) || 0, tipo: 'numero' },
                'Estado':           { valor: c => (estaPagado(c) ? 1 : 0), tipo: 'numero' },
            },
            onCambio: () => { if (pag) pag.inicio(); renderCronos(); },
        });
    }
}

function hayFiltros() {
    return val('crono-search').trim() !== '' || (val('crono-filtro-estado') || 'all') !== 'all';
}

function getFilteredCronos() {
    const q = normCro(val('crono-search'));
    const estado = val('crono-filtro-estado') || 'all';
    return datosCro().filter(c => {
        const pagado = estaPagado(c);
        if (estado === 'pendiente' && pagado) return false;
        if (estado === 'pagado' && !pagado) return false;
        if (q && !normCro(`${c.id_cronograma} ${c.nom_cronograma} ${formatDate(fechaCortaCro(c.fec_programacion))}`).includes(q)) return false;
        return true;
    });
}

function applyFilters() {
    if (pag) pag.inicio();
    renderCronos();
}

function clearFilters() {
    setVal('crono-search', '');
    setVal('crono-filtro-estado', 'all');
    if (window.ErpFiltros) ErpFiltros.sincronizar();
    applyFilters();
}

function badgeCrono(c) {
    const pagado = estaPagado(c);
    let html = pagado ? '<span class="badge ok">Pagado</span>' : '<span class="badge warn">Pendiente</span>';
    // Resumen bajo el estado: cuántas cuotas pagó el banco y cuántas rechazó
    const total = Number(c.cant_cuotas || 0), pag_ = Number(c.cant_pagadas || 0), rech = Number(c.cant_rechazadas || 0);
    if (pag_ > 0 || rech > 0) {
        html += `<span class="crono-resumen-pago">${pag_}/${total} pagada${pag_ !== 1 ? 's' : ''}${rech > 0 ? ` · <b>${rech} rechazada${rech !== 1 ? 's' : ''}</b>` : ''}</span>`;
    }
    return html;
}

// Lista: filtrar → contar → ordenar → paginar → pintar
function renderCronos() {
    prepararLista();
    let filas = getFilteredCronos();
    setText('cronos-count', `${filas.length} resultado${filas.length !== 1 ? 's' : ''}`);
    const btnClear = document.getElementById('btn-clear-filters');
    if (btnClear) btnClear.hidden = !hayFiltros();

    const tbody = document.getElementById('cronos-tbody');
    if (!tbody) return;
    if (filas.length === 0) {
        const hayDatos = datosCro().length > 0;
        tbody.innerHTML = `<tr><td colspan="5"><div class="empty-state">
            <i class="fas ${hayDatos ? 'fa-search' : 'fa-calendar-alt'}"></i>
            <p>${hayDatos ? 'Ningún cronograma coincide con los filtros' : 'No hay cronogramas para mostrar'}</p>
            <span>${hayDatos ? 'Cambie la búsqueda o use «Limpiar»' : 'Use «Nuevo cronograma» para registrar el primero'}</span>
        </div></td></tr>`;
        if (pag) pag.paginar([]);
        return;
    }
    if (orden) filas = orden.ordenar(filas);
    const pagina = pag ? pag.paginar(filas) : filas;
    tbody.innerHTML = pagina.map(c => {
        const id = escapeHtml(c.id_cronograma);
        const nombre = escapeHtml(c.nom_cronograma);
        const acciones = estaPagado(c)
            ? `<span class="accion-bloqueada" title="Cronograma pagado (el banco ya respondió): no se puede editar ni eliminar"><i class="fas fa-lock" aria-hidden="true"></i></span>`
            : `<button type="button" class="btn-icon-sm edit" data-cro-accion="editar" title="Editar cronograma" aria-label="Editar ${nombre}"><i class="fas fa-pen"></i></button>
               <button type="button" class="btn-icon-sm reject" data-cro-accion="eliminar" title="Eliminar cronograma" aria-label="Eliminar ${nombre}"><i class="fas fa-trash"></i></button>`;
        return `<tr data-fila-abre data-id="${id}" tabindex="0" aria-label="Ver el cronograma ${nombre}">
            <td><span class="tcx-fuerte">${nombre}</span><span class="tcx-sub">#${id}</span></td>
            <td class="tcx-num">${escapeHtml(formatDate(fechaCortaCro(c.fec_programacion)))}</td>
            <td class="text-right tcx-num">${formatCurrency(c.total_a_pagar)}</td>
            <td><div class="crono-estado">${badgeCrono(c)}</div></td>
            <td class="col-acciones"><div class="actions-cell">${acciones}</div></td>
        </tr>`;
    }).join('');
}

// ============================================================
// 8. INICIALIZACIÓN GENERAL
// ============================================================
document.addEventListener('DOMContentLoaded', function() {
    initCronoModule();
});

function initCronoModule() {
    // Los modales los mueve a <body> el componente "modales" (erp_ui.js); en el HTML
    // las confirmaciones van después del modal que las abre, para quedar encima.
    // El calendario y el aviso se mueven aquí: así no los tapa el difuminado.
    ['dp-pop', 'toast'].forEach(id => {
        const el = document.getElementById(id);
        if (el && el.parentElement !== document.body) document.body.appendChild(el);
    });

    document.getElementById('btn-add-crono')?.addEventListener('click', openNewModal);

    document.getElementById('crono-search')?.addEventListener('input', applyFilters);
    document.getElementById('crono-filtro-estado')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // Clic (o Enter/espacio) en la fila abre el detalle; los botones hacen lo suyo
    const tbody = document.getElementById('cronos-tbody');
    const cronoDe = tr => datosCro().find(x => String(x.id_cronograma) === tr.dataset.id);
    tbody?.addEventListener('click', e => {
        const tr = e.target.closest('tr[data-fila-abre]');
        if (!tr) return;
        const crono = cronoDe(tr);
        if (!crono) return;
        const b = e.target.closest('[data-cro-accion]');
        if (b) {
            if (b.dataset.croAccion === 'editar') openEditModal(crono);
            if (b.dataset.croAccion === 'eliminar') window.eliminarCronograma(crono.id_cronograma, crono.nom_cronograma);
            return;
        }
        if (e.target.closest('button, a, input, select, textarea')) return;
        openDetailModal(crono);
    });
    tbody?.addEventListener('keydown', e => {
        if (e.key !== 'Enter' && e.key !== ' ') return;
        const tr = e.target.closest('tr[data-fila-abre]');
        if (!tr || e.target !== tr) return;
        e.preventDefault();
        const crono = cronoDe(tr);
        if (crono) openDetailModal(crono);
    });

    // ---------- LISTA (vista Tabla) ----------
    updateStats();
    renderCronos();
    if (window.ErpListaFija) ErpListaFija.ajustar();
    const mod = document.getElementById('mod-cronograma');
    requestAnimationFrame(() => requestAnimationFrame(() => mod?.classList.add('is-listo')));

    // Esc cierra solo las ventanas de lectura y confirmación (la de más arriba primero).
    // Los formularios (nuevo / editar) se cierran solo con la X o Cancelar.
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape' || selectorFechaAbierto()) return;
        const abierto = id => { const m = document.getElementById(id); return m && !m.classList.contains('hidden'); };
        if (abierto('modal-confirm-vencidas')) cerrarConfirmVencidas();
        else if (abierto('modal-confirm-eliminar')) cerrarConfirmEliminar();
        else if (abierto('modal-detail')) closeDetailModal();
        else if (abierto('modal-day')) closeDayModal();
    });

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
