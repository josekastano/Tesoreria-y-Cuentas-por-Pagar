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
    toast.classList.toggle('toast-error', type === 'error');
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
// 2. LISTA: SECCIONES, INDICADORES, FILTROS, ORDEN Y PAGINADOR
// ------------------------------------------------------------
// Las tablas las pinta este archivo desde pagosData (PHP). Tres secciones
// (Proveedores / Nómina / Inversiones), cada una con su tabla y su orden;
// el paginador es uno solo (componentes compartidos de erp_ui.js).
// Indicadores y conteos: sobre TODOS los pagos de la sección activa.
// Sin botón de "ver": clic (o Enter/espacio) en la fila abre el detalle.
// La sección activa se recuerda en sessionStorage.
// ============================================================
const SECCIONES_PAGO = ['proveedores', 'nomina', 'inversiones'];
const CLAVE_SECCION  = 'historial_pagos_seccion';
const PREFIJO_SECCION = { CXP: 'proveedores', NOM: 'nomina', INV: 'inversiones' };
const CLASE_ESTADO = { APROBADO: 'ok', PENDIENTE: 'warn', RECHAZADO: 'bad' };
let seccion = 'proveedores';
let pag = null;
const ordenes = {};
const normPago = t => (window.erpNormalizar ? erpNormalizar(t) : String(t ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim());
const todosPagos = () => (typeof pagosData !== 'undefined' && Array.isArray(pagosData) ? pagosData : []);
const seccionDe = p => PREFIJO_SECCION[String(p.clave || '').split('-')[0]] || 'proveedores';
const pagosSeccion = () => todosPagos().filter(p => seccionDe(p) === seccion);
const fechaPago = p => String(p.fec_pago || '').slice(0, 10);
const periodoNomina = p => `${p.ano_nomina}-${String(Number(p.mes_nomina)).padStart(2, '0')}`;

function guardarSeccion(valor) {
    try { sessionStorage.setItem(CLAVE_SECCION, valor); } catch (e) { /* sin almacenamiento */ }
}

function seccionGuardada() {
    const delHash = location.hash.slice(1);
    if (SECCIONES_PAGO.includes(delHash)) return delHash;
    try { return sessionStorage.getItem(CLAVE_SECCION) || 'proveedores'; } catch (e) { return 'proveedores'; }
}

// Columnas que se ordenan en cada tabla (por el texto del encabezado)
function columnasOrden(sec) {
    const comunes = {
        'Pago':                { valor: p => Number(p.id_pago), tipo: 'numero' },
        'Archivo plano':       { valor: p => Number(p.id_archivo_plano), tipo: 'numero' },
        'Fecha de pago':       { valor: fechaPago, tipo: 'fecha' },
        'Valor':               { valor: p => Number(p.val_pago) || 0, tipo: 'numero' },
        'Respuesta del banco': { valor: p => p.id_codigo || '' },
        'Estado':              { valor: p => p.nom_estado_pago || '' },
    };
    if (sec === 'nomina') return { ...comunes,
        'Empleado': { valor: p => p.nom_tercero || '' },
        'Periodo':  { valor: p => `${periodoNomina(p)}-${p.val_periodo}` } };
    if (sec === 'inversiones') return { ...comunes,
        'Inversor':         { valor: p => p.nom_tercero || '' },
        'Proyecto / cuota': { valor: p => `${p.id_proyecto}-${String(Number(p.id_cuota)).padStart(3, '0')}` } };
    return { ...comunes, 'Factura / cuota': { valor: p => Number(p.id_factura) * 1000 + Number(p.id_cuota), tipo: 'numero' } };
}

function prepararLista() {
    if (!pag && window.ErpPaginador) {
        pag = ErpPaginador.crear({ lista: document.getElementById('tbody-proveedores'), onCambio: renderPagos, tam: 25 });
    }
    if (window.ErpOrden) {
        SECCIONES_PAGO.forEach(sec => {
            if (ordenes[sec]) return;
            ordenes[sec] = ErpOrden.crear({
                tabla: document.getElementById(`tabla-${sec}`),
                columnas: columnasOrden(sec),
                onCambio: () => { if (pag) pag.inicio(); renderPagos(); },
            });
        });
    }
}

function cambiarSeccion(nueva, guardar = true) {
    if (!SECCIONES_PAGO.includes(nueva)) nueva = 'proveedores';
    seccion = nueva;

    document.querySelectorAll('#mod-historial .ap-tab').forEach(tab => {
        const activa = tab.dataset.tab === nueva;
        tab.classList.toggle('active', activa);
        tab.setAttribute('aria-selected', activa ? 'true' : 'false');
    });
    SECCIONES_PAGO.forEach(sec => {
        const t = document.getElementById(`tabla-${sec}`);
        if (t) t.hidden = sec !== nueva;
    });

    const buscador = document.getElementById('pago-search');
    if (buscador) {
        buscador.placeholder = {
            nomina:      'Buscar por pago, empleado, documento, periodo o código del banco...',
            inversiones: 'Buscar por pago, inversor, documento, proyecto o código del banco...',
        }[nueva] || 'Buscar por pago, factura, proveedor o código del banco...';
    }
    const rotulo = { nomina: ['Pagos de nómina', 'fa-users'], inversiones: ['Pagos de inversiones', 'fa-hand-holding-dollar'] }[nueva] || ['Total pagos', 'fa-receipt'];
    setText('stat-total-label', rotulo[0]);
    const ico = document.getElementById('stat-total-icono');
    if (ico) ico.className = `fas ${rotulo[1]}`;

    if (guardar) guardarSeccion(nueva);
    updateStats();
    clearFilters();
    if (window.ErpListaFija) ErpListaFija.ajustar();
}

function updateStats() {
    const data = pagosSeccion();
    const cuenta = { APROBADO: 0, PENDIENTE: 0, RECHAZADO: 0 };
    let valor = 0;
    data.forEach(p => {
        const e = String(p.nom_estado_pago || '');
        if (e in cuenta) cuenta[e]++;
        if (e === 'APROBADO') valor += Number(p.val_pago) || 0;
    });
    setText('stat-total', data.length);
    setText('stat-total-hint', cuenta.PENDIENTE ? `${cuenta.PENDIENTE} pendiente${cuenta.PENDIENTE === 1 ? '' : 's'} de respuesta` : 'Con respuesta registrada');
    setText('stat-aprobados', cuenta.APROBADO);
    setText('stat-aprobados-hint', data.length ? `${Math.round(cuenta.APROBADO / data.length * 100)}% de los pagos` : 'Descontaron saldo');
    setText('stat-rechazados', cuenta.RECHAZADO);
    setText('stat-valor', formatMoney(valor));
    setText('pag-cnt-all', data.length);
    Object.keys(cuenta).forEach(k => setText(`pag-cnt-${k}`, cuenta[k]));
}

function textoBusqueda(p) {
    const base = `${p.id_pago} ${p.id_archivo_plano} ${p.nom_tercero || ''} ${p.id_codigo || ''} ${p.des_motivo || ''} ${formatFecha(fechaPago(p))}`;
    if (seccion === 'nomina') return `${base} ${p.id_tipo || ''} ${p.id_empleado || ''} ${periodoNomina(p)}`;
    if (seccion === 'inversiones') return `${base} ${p.id_tipo || ''} ${p.id_inversor || ''} ${p.id_proyecto || ''}`;
    return `${base} factura ${p.id_factura} cuota ${p.id_cuota}`;
}

function hayFiltros() {
    return val('pago-search').trim() !== '' || (val('pago-filtro-estado') || 'all') !== 'all' || val('fec-desde') !== '' || val('fec-hasta') !== '';
}

function getFilteredPagos() {
    const q = normPago(val('pago-search'));
    const estado = val('pago-filtro-estado') || 'all';
    const desde = val('fec-desde');
    const hasta = val('fec-hasta');
    return pagosSeccion().filter(p => {
        const fecha = fechaPago(p);
        if (estado !== 'all' && p.nom_estado_pago !== estado) return false;
        if (desde && fecha < desde) return false;
        if (hasta && fecha > hasta) return false;
        if (q && !normPago(textoBusqueda(p)).includes(q)) return false;
        return true;
    });
}

function applyFilters() {
    ['fec-desde', 'fec-hasta'].forEach(id => document.getElementById(id)?.classList.toggle('is-set', val(id) !== ''));
    if (pag) pag.inicio();
    renderPagos();
}

function clearFilters() {
    setVal('pago-search', '');
    setVal('pago-filtro-estado', 'all');
    setVal('fec-desde', '');
    setVal('fec-hasta', '');
    if (window.ErpFiltros) ErpFiltros.sincronizar();
    applyFilters();
}

function celdaRespuesta(p) {
    const codigo = String(p.id_codigo || '').trim();
    const motivo = String(p.des_motivo || '').trim();
    return `<td class="ref-bancaria"><span class="tcx-fuerte">${esc(codigo) || '<span class="tcx-muted">—</span>'}</span>${motivo ? `<span class="tcx-sub">${esc(motivo)}</span>` : ''}</td>`;
}

function filaPago(p) {
    const estado = String(p.nom_estado_pago || '');
    const comunesIni = `<td class="tcx-num"><span class="tcx-fuerte">#${esc(p.id_pago)}</span></td>`;
    const archivo = `<td class="tcx-num">Archivo #${esc(p.id_archivo_plano)}</td>`;
    const fecha = `<td class="tcx-num">${esc(formatFecha(fechaPago(p)))}</td>`;
    const valor = `<td class="text-right tcx-num">${formatMoney(p.val_pago)}</td>`;
    const badge = `<td><span class="badge ${CLASE_ESTADO[estado] || 'mute'}">${esc(capEstado(estado))}</span></td>`;
    let medio;
    if (seccion === 'nomina') {
        medio = `<td><span class="tcx-fuerte">${esc(p.nom_tercero)}</span><span class="tcx-sub">${esc((p.id_tipo || '') + ' ' + (p.id_empleado || ''))}</span></td>
                 <td class="tcx-num">${esc(periodoNomina(p))}<span class="tcx-sub">Periodo ${esc(Number(p.val_periodo))}</span></td>${archivo}`;
    } else if (seccion === 'inversiones') {
        medio = `<td><span class="tcx-fuerte">${esc(p.nom_tercero)}</span><span class="tcx-sub">${esc((p.id_tipo || '') + ' ' + (p.id_inversor || ''))}</span></td>
                 <td>${esc(p.id_proyecto)}<span class="tcx-sub">Cuota ${esc(Number(p.id_cuota))}</span></td>${archivo}`;
    } else {
        medio = `<td>Fact. #${esc(p.id_factura)} — Cuota ${esc(p.id_cuota)}<span class="tcx-sub">${esc(p.nom_tercero || '')}</span></td>${archivo}`;
    }
    return `<tr data-fila-abre data-clave="${esc(p.clave)}" tabindex="0" aria-label="Ver el pago ${esc(p.id_pago)}" class="${estado === 'RECHAZADO' ? 'rechazado' : ''}">
        ${comunesIni}${medio}${fecha}${valor}${celdaRespuesta(p)}${badge}
    </tr>`;
}

// Lista: filtrar → contar → ordenar → paginar → pintar (sección activa)
function renderPagos() {
    prepararLista();
    let filas = getFilteredPagos();
    setText('pagos-count', `${filas.length} resultado${filas.length !== 1 ? 's' : ''}`);
    const btnClear = document.getElementById('btn-clear-filters');
    if (btnClear) btnClear.hidden = !hayFiltros();

    const tbody = document.getElementById(`tbody-${seccion}`);
    if (!tbody) return;
    const columnas = seccion === 'proveedores' ? 7 : 8;
    if (filas.length === 0) {
        const hayDatos = pagosSeccion().length > 0;
        const vacio = {
            proveedores: ['fa-receipt', 'No hay pagos de proveedores para mostrar', 'Aparecen aquí al importar la respuesta del banco a un archivo plano de proveedores'],
            nomina:      ['fa-users', 'No hay pagos de nómina para mostrar', 'Aparecen aquí al importar la respuesta del banco a un archivo plano de nómina'],
            inversiones: ['fa-hand-holding-dollar', 'No hay pagos de inversiones para mostrar', 'Aparecen aquí al importar la respuesta del banco a un archivo plano de inversiones'],
        }[seccion];
        tbody.innerHTML = `<tr><td colspan="${columnas}"><div class="empty-state">
            <i class="fas ${hayDatos ? 'fa-search' : vacio[0]}"></i>
            <p>${hayDatos ? 'Ningún pago coincide con los filtros' : vacio[1]}</p>
            <span>${hayDatos ? 'Cambie la búsqueda o use «Limpiar»' : vacio[2]}</span>
        </div></td></tr>`;
        if (pag) pag.paginar([]);
        return;
    }
    const orden = ordenes[seccion];
    if (orden) filas = orden.ordenar(filas);
    const pagina = pag ? pag.paginar(filas) : filas;
    tbody.innerHTML = pagina.map(filaPago).join('');
}

// ============================================================
// 3. MODAL: DETALLE DEL PAGO
// ============================================================
function openDetailModal(pago) {
    // estado_pago es numérico (1, 2, 3); nom_estado_pago trae el nombre
    const estado = String(pago.nom_estado_pago || '');
    const titulos = { NOMINA: 'Pago de nómina', INVERSION: 'Pago de inversión' };
    setText('detail-title', `${titulos[pago.tipo_pago] || 'Pago'} #${pago.id_pago}`);
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

    // Nómina: el beneficiario es un empleado; inversiones: un inversor. Ninguno
    // de los dos tiene factura ni cronograma.
    const esNomina    = pago.tipo_pago === 'NOMINA';
    const esInversion = pago.tipo_pago === 'INVERSION';
    const periodo  = esNomina
        ? `${pago.ano_nomina}-${String(Number(pago.mes_nomina)).padStart(2, '0')}, periodo ${Number(pago.val_periodo)}`
        : '';
    const origen = esNomina
        ? `Archivo plano #${esc(pago.id_archivo_plano)} — Nómina ${esc(periodo)}`
        : esInversion
            ? `Archivo plano #${esc(pago.id_archivo_plano)} — Inversiones (módulo Financiero)`
            : `Archivo plano #${esc(pago.id_archivo_plano)} — Cronograma #${esc(pago.id_cronograma)}`;
    const etiquetaBenef = esNomina ? 'Empleado' : esInversion ? 'Inversor' : 'Proveedor';
    const docBenef      = esNomina ? pago.id_empleado : esInversion ? pago.id_inversor : null;

    document.getElementById('detail-content').innerHTML = `
        ${bloqueMotivo}
        <div class="detail-grid">
            <div class="detail-item">
                <span class="detail-label">${etiquetaBenef}</span>
                <span class="detail-value">${esc(pago.nom_tercero) || '—'}${docBenef ? '<br><small>' + esc(pago.id_tipo) + ' ' + esc(docBenef) + '</small>' : ''}</span>
            </div>
            <div class="detail-item">
                <span class="detail-label">${esNomina ? 'Nómina' : esInversion ? 'Proyecto / Cuota' : 'Factura / Cuota'}</span>
                <span class="detail-value">${esNomina
                    ? esc(periodo)
                    : esInversion
                        ? `${esc(pago.id_proyecto)} — Cuota ${esc(pago.id_cuota)}`
                        : `#${esc(pago.id_factura)} — Cuota ${esc(pago.id_cuota)}`}</span>
            </div>
            <div class="detail-item">
                <span class="detail-label">Valor del Pago</span>
                <span class="detail-value">${formatMoney(pago.val_pago)}</span>
            </div>
            <div class="detail-item">
                <span class="detail-label">Estado</span>
                <span class="detail-value">
                    <span class="badge ${CLASE_ESTADO[estado] || 'mute'}">${capEstado(estado)}</span>
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
            <div class="detail-item detail-item-ancho">
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
// También =900123456 o =00 (cuando las comillas ya se perdieron al leer el CSV
// o alguien editó la celda a mano en Excel).
function limpiarCelda(v) {
    v = String(v ?? '').trim();
    const m = v.match(/^="(.*)"$/) || v.match(/^=([0-9A-Za-z]+)$/);
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
    // "c_digo_respuesta": la tilde de Código se dañó en un archivo con otra codificación
    const iCodigo  = indiceColumna(cols, 'codigo_respuesta', 'id_codigo', 'codigo', 'c_digo_respuesta', 'c_digo');
    const iDesc    = indiceColumna(cols, 'descripcion_respuesta', 'descripcion', 'des_motivo');
    const iFecha   = indiceColumna(cols, 'fecha_pago', 'fec_pago', 'fecha');
    // La respuesta de un archivo de nómina trae "Documento Empleado" / "Nombre Empleado"
    // y la de inversiones "Documento Inversor" / "Nombre Inversor"
    const iDoc     = indiceColumna(cols, 'documento_proveedor', 'documento_empleado', 'documento_inversor', 'documento_beneficiario');
    const iNombre  = indiceColumna(cols, 'nombre_proveedor', 'nombre_empleado', 'nombre_inversor', 'nombre_beneficiario');
    const iCuenta  = indiceColumna(cols, 'cuenta_destino');
    const iValor   = indiceColumna(cols, 'valor_a_pagar', 'valor');

    if (iArchivo === -1 || iConsec === -1 || iEstado === -1 || iCodigo === -1) {
        // ¿Cargaron el archivo plano que se ENVÍA al banco en lugar de la respuesta?
        if (iConsec === -1 && iEstado === -1 && cols.includes('valor_a_pagar') && cols.includes('cuenta_destino')) {
            return { error: 'Este es el archivo plano que se envía al banco, no la respuesta del banco. Genere la respuesta con el simulador (o la que devuelva el banco) y cargue ese archivo.' };
        }
        const faltan = [
            [iArchivo, 'ID Archivo Plano'], [iConsec, 'Consecutivo'],
            [iEstado, 'Estado'], [iCodigo, 'Código Respuesta']
        ].filter(([i]) => i === -1).map(([, n]) => n);
        return { error: `A la respuesta del banco le falta(n) la(s) columna(s): ${faltan.join(', ')}. `
                      + `Encabezado leído: ${cols.filter(Boolean).slice(0, 8).join(', ')}${cols.length > 8 ? '…' : ''}.` };
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

// El simulador guarda la respuesta en UTF-8, pero si alguien la abre en
// Excel y la vuelve a guardar como "CSV (delimitado por comas)" queda en
// Windows-1252 y las tildes ("Código", "Descripción", nombres) se dañan.
// Se lee como bytes: si no es UTF-8 válido, se decodifica como Windows-1252.
function decodificarCSV(buffer) {
    try {
        return new TextDecoder('utf-8', { fatal: true }).decode(buffer);
    } catch (e) {
        return new TextDecoder('windows-1252').decode(buffer);
    }
}

function leerArchivoCSV(archivo) {
    const lector = new FileReader();

    lector.onload = e => {
        const { filas, error } = parsearCSV(decodificarCSV(e.target.result));

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
    lector.readAsArrayBuffer(archivo);
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
            // Al recargar se abre la pestaña de lo que se importó (si fue de un solo tipo)
            const t = result.aplicadas_tipo || {};
            const conPagos = SECCIONES_PAGO.filter(s => (t[s] || 0) > 0);
            if (conPagos.length === 1) guardarSeccion(conPagos[0]);
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
    // Los modales los mueve a <body> el componente "modales" (erp_ui.js); el aviso se mueve aquí
    const toastEl = document.getElementById('toast');
    if (toastEl && toastEl.parentElement !== document.body) document.body.appendChild(toastEl);

    document.getElementById('pago-search')?.addEventListener('input', applyFilters);
    document.getElementById('pago-filtro-estado')?.addEventListener('change', applyFilters);
    document.getElementById('fec-desde')?.addEventListener('change', applyFilters);
    document.getElementById('fec-hasta')?.addEventListener('change', applyFilters);
    document.getElementById('btn-clear-filters')?.addEventListener('click', clearFilters);

    // Clic (o Enter/espacio) en la fila abre el detalle
    const abrirFila = tr => {
        const pago = todosPagos().find(x => String(x.clave) === tr.dataset.clave);
        if (pago) openDetailModal(pago);
    };
    SECCIONES_PAGO.forEach(sec => {
        const tbody = document.getElementById(`tbody-${sec}`);
        tbody?.addEventListener('click', e => {
            const tr = e.target.closest('tr[data-fila-abre]');
            if (!tr || e.target.closest('button, a, input, select, textarea')) return;
            abrirFila(tr);
        });
        tbody?.addEventListener('keydown', e => {
            if (e.key !== 'Enter' && e.key !== ' ') return;
            const tr = e.target.closest('tr[data-fila-abre]');
            if (!tr || e.target !== tr) return;
            e.preventDefault();
            abrirFila(tr);
        });
    });

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

    // ---------- SECCIONES (pestañas Proveedores / Nómina / Inversiones) ----------
    document.querySelectorAll('#mod-historial .ap-tab').forEach(tab => {
        tab.addEventListener('click', () => cambiarSeccion(tab.dataset.tab));
    });
    cambiarSeccion(seccionGuardada(), false);   // también calcula los indicadores y pinta la lista
    const mod = document.getElementById('mod-historial');
    requestAnimationFrame(() => requestAnimationFrame(() => mod?.classList.add('is-listo')));

    // El detalle es de solo lectura: Esc lo cierra. La importación no (se perdería lo leído).
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        const m = document.getElementById('modal-detail');
        if (m && !m.classList.contains('hidden')) closeDetailModal();
    });
}
