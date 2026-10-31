'use strict';

// ============================================================
// 1. HELPERS GENERALES (mismos que bancos.js)
// ============================================================
function val(id)           { return document.getElementById(id)?.value ?? ''; }
function setVal(id, value) { const el = document.getElementById(id); if (el) el.value = value ?? ''; }
function setText(id, text) { const el = document.getElementById(id); if (el) el.textContent = text ?? ''; }
function show(id)          { document.getElementById(id)?.classList.remove('hidden'); }
function hide(id)          { document.getElementById(id)?.classList.add('hidden'); }

function showToast(message, type = 'success') {
    const toast = document.getElementById('toast');
    const span  = document.getElementById('toast-message');
    if (!toast || !span) return;
    const text = message && message.trim() ? message : (type === 'success' ? 'Operación exitosa' : 'Ocurrió un error');
    span.textContent = text;
    toast.style.background = type === 'error' ? '#ef4444' : '#0f172a';
    toast.classList.remove('hidden');
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => toast.classList.add('hidden'), type === 'error' ? 7000 : 4000);
}

function formatMoney(valor) {
    return '$' + Number(valor || 0).toLocaleString('es-CO');
}

function formatFecha(iso) {
    if (!iso) return '—';
    const [y, m, d] = String(iso).split('-');
    return (y && m && d) ? `${d}/${m}/${y}` : iso;
}

function esc(texto) {
    return String(texto ?? '')
        .replace(/&/g, '&amp;').replace(/</g, '&lt;')
        .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function capEstado(estado) {
    const e = String(estado || '');
    return e.charAt(0) + e.slice(1).toLowerCase();
}

// ============================================================
// 2. FILTROS + PAGINACIÓN + ORDENAMIENTO (mismo sistema que Proveedores)
// ------------------------------------------------------------
// Filtros: búsqueda + estado + rango de fechas. El "Valor aprobado" de
// la tarjeta suma TODOS los pagos aprobados que pasan el filtro, no solo
// los de la página visible.
// ============================================================

// ---- ESTADO DE PAGINACIÓN ----
let pagosPage     = 1;
let pagosPageSize = 25; // debe coincidir con el <option selected> de #pagos-page-size

// Filas que pasan todos los filtros (sin tener en cuenta la página)
function getFilteredPagoRows() {
    const query  = val('pago-search').toLowerCase().trim();
    const active = document.querySelector('#mod-historial .filter-toggle.active')?.dataset.filter ?? 'all';
    const desde  = val('fec-desde');
    const hasta  = val('fec-hasta');
    const filas  = Array.from(document.querySelectorAll('#pagos-tbody tr:not(.empty-row)'));

    return filas.filter(fila => {
        const fecha  = fila.dataset.fecha ?? '';
        const estado = fila.dataset.estado ?? '';
        const pasaTexto  = !query || fila.textContent.toLowerCase().includes(query);
        const pasaEstado = active === 'all' || estado === active;
        const pasaDesde  = !desde || fecha >= desde;
        const pasaHasta  = !hasta || fecha <= hasta;
        return pasaTexto && pasaEstado && pasaDesde && pasaHasta;
    });
}

// Aplica los filtros, vuelve a la primera página y devuelve los id_pago
// que pasan el filtro (todas las páginas), en el orden de la tabla.
function applyFilters() {
    pagosPage = 1;
    const coinciden = renderPagosPage();

    const query  = val('pago-search').trim();
    const active = document.querySelector('#mod-historial .filter-toggle.active')?.dataset.filter ?? 'all';
    const desde  = val('fec-desde');
    const hasta  = val('fec-hasta');

    const clearBtn = document.getElementById('btn-clear-filters');
    if (clearBtn) {
        clearBtn.style.display = (query || active !== 'all' || desde || hasta) ? 'flex' : 'none';
    }

    return coinciden.map(fila => Number(fila.dataset.idPago));
}

function clearFilters() {
    setVal('pago-search', '');
    setVal('fec-desde', '');
    setVal('fec-hasta', '');
    document.querySelectorAll('#mod-historial .filter-toggle').forEach(btn => btn.classList.remove('active'));
    document.querySelector('#mod-historial .filter-toggle[data-filter="all"]')?.classList.add('active');
    applyFilters();
}

// Muestra solo las filas que pasan el filtro Y caen en la página actual.
// Devuelve todas las filas que pasan el filtro.
function renderPagosPage() {
    const todas     = Array.from(document.querySelectorAll('#pagos-tbody tr:not(.empty-row)'));
    const coinciden = getFilteredPagoRows();
    todas.forEach(fila => { fila.style.display = 'none'; });

    const total        = coinciden.length;
    const esTodos      = pagosPageSize === 'all';
    const size         = esTodos ? total : pagosPageSize;
    const totalPaginas = size > 0 ? Math.max(1, Math.ceil(total / size)) : 1;
    if (pagosPage > totalPaginas) pagosPage = totalPaginas;
    if (pagosPage < 1) pagosPage = 1;

    const start = esTodos ? 0 : (pagosPage - 1) * size;
    const end   = esTodos ? total : Math.min(start + size, total);
    coinciden.slice(start, end).forEach(fila => { fila.style.display = ''; });

    // Valor aprobado de TODO lo filtrado (no solo de la página visible)
    let valorAprobado = 0;
    coinciden.forEach(fila => {
        if (fila.dataset.estado !== 'APROBADO') return;
        const pago = pagosData.find(p => Number(p.id_pago) === Number(fila.dataset.idPago));
        if (pago) valorAprobado += Number(pago.val_pago);
    });

    setText('pagos-count', `${total} resultado${total !== 1 ? 's' : ''}`);
    setText('stat-valor', formatMoney(valorAprobado));

    const rangeEl = document.getElementById('pagos-range');
    if (rangeEl) {
        rangeEl.textContent = total === 0 ? '0 de 0' : `${start + 1}–${end} de ${total}`;
    }

    const btnPrev = document.getElementById('pagos-prev');
    const btnNext = document.getElementById('pagos-next');
    if (btnPrev) btnPrev.disabled = pagosPage <= 1;
    if (btnNext) btnNext.disabled = esTodos || pagosPage >= totalPaginas;

    return coinciden;
}

function initPagosPagination() {
    document.getElementById('pagos-page-size')?.addEventListener('change', function() {
        pagosPageSize = this.value === 'all' ? 'all' : parseInt(this.value, 10);
        pagosPage = 1;
        renderPagosPage();
    });
    document.getElementById('pagos-prev')?.addEventListener('click', () => {
        pagosPage--;
        renderPagosPage();
    });
    document.getElementById('pagos-next')?.addEventListener('click', () => {
        pagosPage++;
        renderPagosPage();
    });
}

// ---- ORDENAMIENTO ASC / DESC ----
// Cada celda ordenable trae su valor "crudo" en data-sort:
//   Factura / Cuota → factura × 1000 + cuota (primero por factura, luego por cuota)
//   Origen          → nombre del archivo plano; vacío si fue pago manual
//   Fecha           → 'YYYY-MM-DD'; Valor → número; Referencia → vacía si no tiene
let pagosSortKey = null; // índice de columna, coincide con data-sort-key del <th>
let pagosSortDir = 'asc';

function sortPagoRows(key, type) {
    const tbody = document.getElementById('pagos-tbody');
    if (!tbody) return;
    const filas = Array.from(tbody.querySelectorAll('tr:not(.empty-row)'));
    if (filas.length === 0) return;

    pagosSortDir = (pagosSortKey === key && pagosSortDir === 'asc') ? 'desc' : 'asc';
    pagosSortKey = key;

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
        return pagosSortDir === 'asc' ? cmp : -cmp;
    });
    filas.forEach(fila => tbody.appendChild(fila));

    document.querySelectorAll('#mod-historial .data-table th.sortable').forEach(th => {
        const icon   = th.querySelector('.sort-icon');
        const activo = th.dataset.sortKey === key;
        th.classList.toggle('sort-active', activo);
        if (icon) {
            icon.className = activo
                ? `fas sort-icon ${pagosSortDir === 'asc' ? 'fa-caret-up' : 'fa-caret-down'}`
                : 'fas fa-caret-down sort-icon';
        }
    });

    pagosPage = 1;
    renderPagosPage();
}

function initPagosSorting() {
    document.querySelectorAll('#mod-historial .data-table th.sortable').forEach(th => {
        th.addEventListener('click', () => sortPagoRows(th.dataset.sortKey, th.dataset.sortType));
    });
}

// ---- ALTO DINÁMICO DE LA TABLA (evita el doble scroll) ----
function ajustarAlturaTablaPagos() {
    const scrollBox = document.getElementById('pagos-table-scroll');
    if (!scrollBox) return;
    const footer = document.querySelector('#mod-historial .table-footer');
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
// 3. MODAL: DETALLE DEL PAGO
// ============================================================
function openDetailModal(pago) {
    // estado_pago es numérico (1, 2, 3); nom_estado_pago trae el nombre
    const estado = String(pago.nom_estado_pago || '');
    setText('detail-title', `Pago #${pago.id_pago}`);
    setText('detail-subtitle', `${capEstado(estado)} — ${formatFecha(pago.fec_pago)}`);

    const rechazado = estado === 'RECHAZADO';

    const bloqueMotivo = rechazado ? `
        <div class="motivo-rechazo">
            <i class="fas fa-circle-exclamation"></i>
            <div class="motivo-rechazo-texto">
                <span class="motivo-rechazo-label">Motivo del rechazo</span>
                <span class="motivo-rechazo-valor">${esc(pago.des_motivo) || 'Sin motivo registrado'}${pago.id_codigo ? ' (' + esc(pago.id_codigo) + ')' : ''}</span>
            </div>
        </div>` : '';

    const origen = `Archivo plano #${esc(pago.id_archivo_plano)} — Cronograma #${esc(pago.id_cronograma)}`;

    document.getElementById('detail-content').innerHTML = `
        ${bloqueMotivo}
        <div class="detail-grid">
            <div class="detail-item">
                <span class="detail-label">Proveedor</span>
                <span class="detail-value">${esc(pago.nom_tercero) || '—'}</span>
            </div>
            <div class="detail-item">
                <span class="detail-label">Factura / Cuota</span>
                <span class="detail-value">#${esc(pago.id_factura)} — Cuota ${esc(pago.id_cuota)}</span>
            </div>
            <div class="detail-item">
                <span class="detail-label">Valor del Pago</span>
                <span class="detail-value">${formatMoney(pago.val_pago)}</span>
            </div>
            <div class="detail-item">
                <span class="detail-label">Estado</span>
                <span class="detail-value">
                    <span class="badge-${estado.toLowerCase()}">${capEstado(estado)}</span>
                </span>
            </div>
            <div class="detail-item">
                <span class="detail-label">Fecha de Pago</span>
                <span class="detail-value">${formatFecha(pago.fec_pago)}</span>
            </div>
            <div class="detail-item">
                <span class="detail-label">Respuesta del Banco</span>
                <span class="detail-value">${esc(pago.id_codigo) || '—'}${pago.des_motivo ? '<br><small>' + esc(pago.des_motivo) + '</small>' : ''}</span>
            </div>
            <div class="detail-item" style="grid-column:1/-1">
                <span class="detail-label">Origen</span>
                <span class="detail-value">${origen}</span>
            </div>
        </div>
    `;

    show('modal-detail');
}

function closeDetailModal() {
    hide('modal-detail');
}

window.openDetailModal = openDetailModal;

// ============================================================
// 4. IMPORTAR RESPUESTA DEL BANCO (CSV)
// ============================================================
// Formato (el que genera simulador_respuesta_banco.html):
//   ID Archivo Plano; Consecutivo; <12 columnas del archivo plano>;
//   Estado; Código Respuesta; Descripción Respuesta; Fecha Pago
// El archivo plano no lleva factura ni cuota: el banco identifica cada pago
// por su consecutivo (línea 1, 2, 3...) y el servidor lo cruza con
// tab_det_archivo_plano en el mismo orden de la descarga.
let filasImportadas = [];

// Detecta ';' o ',' según cuál aparezca más en el encabezado
function detectarSeparador(linea) {
    const puntoYComa = (linea.match(/;/g) || []).length;
    const coma       = (linea.match(/,/g) || []).length;
    return puntoYComa >= coma ? ';' : ',';
}

// ="900123456" (formato texto para Excel) -> 900123456
function limpiarCelda(v) {
    v = String(v ?? '').trim();
    const m = v.match(/^="(.*)"$/);
    return m ? m[1].trim() : v;
}

// Parser de una línea CSV que respeta las comillas dobles
function parsearLinea(linea, sep) {
    const campos = [];
    let actual = '';
    let enComillas = false;

    for (let i = 0; i < linea.length; i++) {
        const c = linea[i];
        if (c === '"') {
            if (enComillas && linea[i + 1] === '"') { actual += '"'; i++; }
            else { enComillas = !enComillas; }
        } else if (c === sep && !enComillas) {
            campos.push(limpiarCelda(actual));
            actual = '';
        } else {
            actual += c;
        }
    }
    campos.push(limpiarCelda(actual));
    return campos;
}

function normalizarEncabezado(texto) {
    return texto.toLowerCase()
        .normalize('NFD').replace(/[̀-ͯ]/g, '')
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '');
}

// Primer nombre de columna que exista en el encabezado (acepta sinónimos)
function indiceColumna(cols, ...nombres) {
    for (const n of nombres) {
        const i = cols.indexOf(n);
        if (i !== -1) return i;
    }
    return -1;
}

function parsearCSV(texto) {
    // Quitar BOM y separar en líneas no vacías
    const lineas = texto.replace(/^﻿/, '')
        .split(/\r\n|\n|\r/)
        .filter(l => l.trim() !== '');

    if (lineas.length < 2) {
        return { error: 'El archivo no tiene filas de datos.' };
    }

    const sep  = detectarSeparador(lineas[0]);
    const cols = parsearLinea(lineas[0], sep).map(normalizarEncabezado);

    const iArchivo = indiceColumna(cols, 'id_archivo_plano', 'archivo_plano');
    const iConsec  = indiceColumna(cols, 'consecutivo', 'linea', 'secuencia');
    const iEstado  = indiceColumna(cols, 'estado', 'estado_pago');
    const iCodigo  = indiceColumna(cols, 'codigo_respuesta', 'id_codigo', 'codigo');
    const iDesc    = indiceColumna(cols, 'descripcion_respuesta', 'descripcion', 'des_motivo');
    const iFecha   = indiceColumna(cols, 'fecha_pago', 'fec_pago', 'fecha');
    const iDoc     = indiceColumna(cols, 'documento_proveedor');
    const iNombre  = indiceColumna(cols, 'nombre_proveedor');
    const iCuenta  = indiceColumna(cols, 'cuenta_destino');
    const iValor   = indiceColumna(cols, 'valor_a_pagar', 'valor');

    if (iArchivo === -1 || iConsec === -1 || iEstado === -1 || iCodigo === -1) {
        return { error: 'El archivo debe tener al menos las columnas ID Archivo Plano, Consecutivo, Estado y Código Respuesta.' };
    }

    const celda = (c, i) => (i !== -1 ? (c[i] ?? '').trim() : '');

    const filas = lineas.slice(1).map((linea, n) => {
        const c = parsearLinea(linea, sep);
        return {
            linea:               n + 2,
            id_archivo_plano:    celda(c, iArchivo),
            consecutivo:         celda(c, iConsec),
            estado:              celda(c, iEstado).toUpperCase(),
            codigo_respuesta:    celda(c, iCodigo),
            descripcion:         celda(c, iDesc),
            fecha_pago:          celda(c, iFecha),
            documento_proveedor: celda(c, iDoc),
            nombre_proveedor:    celda(c, iNombre),
            cuenta_destino:      celda(c, iCuenta),
            valor_a_pagar:       celda(c, iValor)
        };
    });

    return { filas };
}

// Validación previa para que el usuario vea qué va a pasar. El servidor
// vuelve a validar todo contra tab_det_archivo_plano y la base.
function validarFila(fila, vistas) {
    if (!/^\d+$/.test(fila.id_archivo_plano) || !/^\d+$/.test(fila.consecutivo) || Number(fila.consecutivo) < 1) {
        return 'ID Archivo Plano y Consecutivo deben ser números.';
    }
    if (!['APROBADO', 'RECHAZADO'].includes(fila.estado)) {
        return `Estado "${fila.estado || 'vacío'}": debe ser APROBADO o RECHAZADO.`;
    }
    if (fila.codigo_respuesta === '') {
        return 'Falta el código de respuesta del banco (también en los aprobados).';
    }
    if (fila.codigo_respuesta.length > 10) {
        return 'El código de respuesta supera 10 caracteres.';
    }
    if (fila.fecha_pago !== '' && !/^\d{4}-\d{2}-\d{2}$/.test(fila.fecha_pago) && !/^\d{1,2}\/\d{1,2}\/\d{4}$/.test(fila.fecha_pago)) {
        return `Fecha de pago "${fila.fecha_pago}" no válida (use AAAA-MM-DD).`;
    }
    const clave = `${Number(fila.id_archivo_plano)}-${Number(fila.consecutivo)}`;
    if (vistas.has(clave)) {
        return `La línea ${fila.consecutivo} del archivo ${fila.id_archivo_plano} está repetida en la respuesta.`;
    }
    vistas.add(clave);
    return null;
}

function renderImportacion() {
    const lista = document.getElementById('import-filas-list');
    const validas   = filasImportadas.filter(f => !f.error);
    const invalidas = filasImportadas.filter(f => f.error);

    setText('import-total',     filasImportadas.length);
    setText('import-validas',   validas.length);
    setText('import-invalidas', invalidas.length);

    if (filasImportadas.length === 0) {
        lista.innerHTML = '<p class="import-vacio">El archivo no trae filas para aplicar.</p>';
    } else {
        lista.innerHTML = filasImportadas.map(f => {
            const valor   = f.valor_a_pagar !== '' ? ' — ' + formatMoney(f.valor_a_pagar) : '';
            const detalle = f.error
                ? esc(f.error)
                : `${capEstado(f.estado)} — ${esc(f.codigo_respuesta)}${f.descripcion ? ' ' + esc(f.descripcion) : ''}${f.fecha_pago ? ' — ' + esc(formatFecha(f.fecha_pago)) : ''}`;
            return `
                <div class="import-row ${f.error ? 'invalida' : 'valida'}">
                    <span class="import-row-icon">
                        <i class="fas fa-${f.error ? 'xmark' : 'check'}"></i>
                    </span>
                    <div class="import-row-info">
                        <span class="import-row-pago">Archivo #${esc(f.id_archivo_plano) || '—'} — Línea ${esc(f.consecutivo) || '—'}${f.nombre_proveedor ? ' · ' + esc(f.nombre_proveedor) : ''}${valor}</span>
                        <span class="import-row-meta">Fila ${f.linea} del CSV · ${detalle}</span>
                    </div>
                </div>`;
        }).join('');
    }

    setVal('hid-filas-importar', JSON.stringify(validas.map(f => ({
        id_archivo_plano:    f.id_archivo_plano,
        consecutivo:         f.consecutivo,
        estado:              f.estado,
        codigo_respuesta:    f.codigo_respuesta,
        fecha_pago:          f.fecha_pago,
        documento_proveedor: f.documento_proveedor,
        cuenta_destino:      f.cuenta_destino,
        valor_a_pagar:       f.valor_a_pagar
    }))));

    const btn = document.getElementById('import-btn-apply');
    if (btn) btn.disabled = validas.length === 0;

    setText('import-subtitle', validas.length > 0
        ? `${validas.length} de ${filasImportadas.length} fila(s) se pueden aplicar`
        : 'Ninguna fila del archivo se puede aplicar');
}

function leerArchivoCSV(archivo) {
    const lector = new FileReader();

    lector.onload = e => {
        const { filas, error } = parsearCSV(String(e.target.result ?? ''));

        if (error) {
            showToast(error, 'error');
            setVal('csv-input', '');
            return;
        }

        const vistas = new Set();
        filasImportadas = filas.map(f => ({ ...f, error: validarFila(f, vistas) }));
        renderImportacion();
        show('modal-import');
    };

    lector.onerror = () => showToast('No se pudo leer el archivo.', 'error');
    lector.readAsText(archivo, 'UTF-8');
}

function closeImportModal() {
    hide('modal-import');
    filasImportadas = [];
    setVal('csv-input', '');
}

async function aplicarImportacion() {
    const form = document.getElementById('import-form');
    const formData = new FormData(form);
    const btn = document.getElementById('import-btn-apply');

    btn.disabled = true;

    try {
        const response = await fetch(window.location.href, {
            method: 'POST',
            body: formData
        });
        const text = await response.text();
        let result;
        try { result = JSON.parse(text); }
        catch (e) {
            console.error('[pagos] Respuesta del servidor que no es JSON:', text);
            result = { success: false, message: 'Respuesta inválida del servidor (revise la consola).' };
        }
        if (result.debug_salida_previa) console.warn('[pagos] Salida de PHP antes del JSON:', result.debug_salida_previa);
        if (Array.isArray(result.omitidas) && result.omitidas.length) {
            console.warn('[pagos] Filas omitidas:\n' + result.omitidas.join('\n'));
        }

        if (result.success) {
            const extra = Array.isArray(result.omitidas) && result.omitidas.length
                ? ' Omitidas: ' + result.omitidas.slice(0, 2).join(' | ') + (result.omitidas.length > 2 ? ' (ver consola)' : '')
                : '';
            showToast(result.message + extra, 'success');
            closeImportModal();
            setTimeout(() => location.reload(), result.omitidas?.length ? 4000 : 800);
        } else {
            const detalle = Array.isArray(result.omitidas) && result.omitidas.length
                ? ' — ' + result.omitidas.slice(0, 3).join(' | ')
                : '';
            showToast((result.message || 'No se pudo aplicar la importación') + detalle, 'error');
            btn.disabled = false;
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
        btn.disabled = false;
    }
}

// ============================================================
// 5. INICIALIZACIÓN GENERAL
// ============================================================
document.addEventListener('DOMContentLoaded', function() {
    initHistorialModule();
});

function initHistorialModule() {
    document.getElementById('pago-search')?.addEventListener('input', applyFilters);
    document.getElementById('fec-desde')?.addEventListener('change', applyFilters);
    document.getElementById('fec-hasta')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    document.querySelectorAll('#mod-historial .filter-toggle').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('#mod-historial .filter-toggle').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            applyFilters();
        });
    });

    // ---------- PAGINACIÓN Y ORDENAMIENTO ----------
    initPagosPagination();
    initPagosSorting();

    // El botón solo abre el selector de archivos; el modal se abre al leerlo
    const csvInput = document.getElementById('csv-input');
    document.getElementById('btn-import-historial')?.addEventListener('click', () => csvInput?.click());

    csvInput?.addEventListener('change', e => {
        const archivo = e.target.files?.[0];
        if (archivo) leerArchivoCSV(archivo);
    });

    document.getElementById('close-import-modal')?.addEventListener('click', closeImportModal);
    document.getElementById('cancel-import-modal')?.addEventListener('click', closeImportModal);
    document.getElementById('import-btn-apply')?.addEventListener('click', aplicarImportacion);

    // Los modales NO se cierran al hacer clic por fuera (en el fondo oscuro):
    // así no se pierde lo que se lleva escrito en un formulario por un clic
    // accidental. Se cierran solo con la X, "Cancelar" o "Cerrar".

    document.getElementById('close-detail-modal')?.addEventListener('click', closeDetailModal);
    document.getElementById('close-detail-btn')?.addEventListener('click', closeDetailModal);

    applyFilters();
    ajustarAlturaTablaPagos();
    window.addEventListener('resize', ajustarAlturaTablaPagos);
}
