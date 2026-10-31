<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Historial de Pagos";
$page_description = "Consulta de todos los pagos registrados sobre cuotas de facturas";
$page_icon        = "bi-receipt";
$page_extra_css   = ["../modules/tescxp/css/historial_pagos.css"];
$page_extra_js    = ["../modules/tescxp/js/historial_pagos.js"];
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// LIMPIAR MENSAJE DE ERROR DE POSTGRESQL
// ============================================================
if (!function_exists('limpiar_error_pgsql')) {
function limpiar_error_pgsql(string $msg): string {
    if (preg_match('/ERROR:\s*ERROR:\s*(.+?)(?:\s+CONTEXT:|$)/s', $msg, $m)) {
        return trim($m[1]);
    }
    if (preg_match('/ERROR:\s*(.+?)(?:\s+CONTEXT:|$)/s', $msg, $m)) {
        return trim($m[1]);
    }
    return $msg;
}
}

// ============================================================
// RESPONDER JSON
// ------------------------------------------------------------
// menu_principal.php ya imprimió el layout antes de incluir esta página:
// se descarta todo lo que haya en los buffers y se envía SOLO el JSON.
// ============================================================
if (!function_exists('responder_json')) {
    function responder_json(array $respuesta): void {
        $previo = '';
        while (ob_get_level() > 0) {
            $previo = ((string)ob_get_clean()) . $previo;
        }
        $previo = trim(strip_tags($previo));
        if ($previo !== '' && preg_match('/(fatal|error|warning|notice|deprecated|exception)/i', $previo)) {
            $respuesta['debug_salida_previa'] = substr($previo, 0, 800);
        }
        if (!headers_sent()) {
            header('Content-Type: application/json; charset=utf-8');
        }
        echo json_encode($respuesta, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
        exit;
    }
}

// ="900123456" (formato texto para Excel) -> 900123456
function limpiar_celda($valor): string {
    $v = trim((string)$valor);
    if (preg_match('/^="(.*)"$/s', $v, $m)) {
        $v = trim($m[1]);
    }
    return $v;
}

// Acepta AAAA-MM-DD o DD/MM/AAAA (si alguien guardó la respuesta desde Excel)
function fecha_iso(string $f): ?string {
    if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $f)) {
        $d = DateTime::createFromFormat('Y-m-d', $f);
        return ($d && $d->format('Y-m-d') === $f) ? $f : null;
    }
    if (preg_match('/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/', $f, $m)) {
        return checkdate((int)$m[2], (int)$m[1], (int)$m[3])
            ? sprintf('%04d-%02d-%02d', $m[3], $m[2], $m[1]) : null;
    }
    return null;
}

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    ob_start();
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- VER DETALLE DE UN PAGO ----------
        if (isset($_POST['btn_ver_pago'])) {
            $id_pago = trim($_POST['hid_id_pago'] ?? '');

            if ($id_pago === '' || !ctype_digit($id_pago)) {
                throw new Exception('Pago no válido.');
            }

            $get_pago_cxp->execute([':wid_pago' => (int)$id_pago]);
            $pago = $get_pago_cxp->fetch(PDO::FETCH_ASSOC);

            if (!$pago) {
                throw new Exception('El pago no existe.');
            }

            $respuesta['success'] = true;
            $respuesta['pago']    = $pago;
            responder_json($respuesta);
        }

        // ---------- APLICAR RESPUESTA DEL BANCO (CSV) ----------
        // El archivo plano que se envía al banco NO lleva factura ni cuota, así
        // que el banco identifica cada pago por su CONSECUTIVO: la posición de
        // la línea dentro del archivo (1, 2, 3...). Aquí se vuelve a leer el
        // detalle con $list_det_archivo_plano, que tiene el MISMO orden que la
        // descarga (nom_tercero, id_factura, id_cuota), y la línea N es la
        // fila N. Además se comparan documento, cuenta y valor, para no aplicar
        // la respuesta a otro pago si el orden no coincide.
        //
        // El valor del pago NUNCA se toma del archivo del banco: lo pone
        // fun_insert_pagos_cxp desde tab_det_archivo_plano.val_a_pagar.
        if (isset($_POST['btn_importar'])) {
            $filas = json_decode($_POST['hid_filas_importar'] ?? '', true);

            if (!is_array($filas) || count($filas) === 0) {
                throw new Exception('No se recibió ninguna fila para aplicar.');
            }

            $aplicadas = 0;
            $omitidas  = [];
            $detalles  = [];   // id_archivo_plano => líneas en el orden de la descarga

            $pdo->beginTransaction();

            foreach ($filas as $f) {
                $id_archivo = limpiar_celda($f['id_archivo_plano'] ?? '');
                $consec     = limpiar_celda($f['consecutivo'] ?? '');
                $estado_txt = strtoupper(limpiar_celda($f['estado'] ?? ''));
                $id_codigo  = limpiar_celda($f['codigo_respuesta'] ?? '');
                $fec_txt    = limpiar_celda($f['fecha_pago'] ?? '');
                $doc        = limpiar_celda($f['documento_proveedor'] ?? '');
                $cuenta     = limpiar_celda($f['cuenta_destino'] ?? '');
                $valor      = limpiar_celda($f['valor_a_pagar'] ?? '');

                $etiqueta = "Archivo {$id_archivo} / línea {$consec}";

                if (!ctype_digit($id_archivo) || !ctype_digit($consec) || (int)$consec < 1) {
                    $omitidas[] = "{$etiqueta}: ID de archivo o consecutivo no válido.";
                    continue;
                }

                // 2 = APROBADO, 3 = RECHAZADO (1 = PENDIENTE no llega en una respuesta)
                $estados = ['APROBADO' => 2, 'RECHAZADO' => 3];
                if (!isset($estados[$estado_txt])) {
                    $omitidas[] = "{$etiqueta}: el estado '{$estado_txt}' no es APROBADO ni RECHAZADO.";
                    continue;
                }
                $estado_pago = $estados[$estado_txt];

                // id_codigo VARCHAR(10), obligatorio también en los aprobados
                if ($id_codigo === '' || strlen($id_codigo) > 10) {
                    $omitidas[] = "{$etiqueta}: falta el código de respuesta del banco o supera 10 caracteres.";
                    continue;
                }

                $fec_pago = $fec_txt === '' ? date('Y-m-d') : fecha_iso($fec_txt);
                if ($fec_pago === null) {
                    $omitidas[] = "{$etiqueta}: la fecha de pago '{$fec_txt}' no es válida (use AAAA-MM-DD).";
                    continue;
                }

                // Detalle del archivo, una sola consulta por archivo
                if (!isset($detalles[$id_archivo])) {
                    $list_det_archivo_plano->execute([':wid_archivo_plano' => (int)$id_archivo]);
                    $detalles[$id_archivo] = $list_det_archivo_plano->fetchAll(PDO::FETCH_ASSOC);
                }
                $detalle = $detalles[$id_archivo];

                if (empty($detalle)) {
                    $omitidas[] = "{$etiqueta}: el archivo plano {$id_archivo} no existe o no tiene pagos.";
                    continue;
                }

                $linea = $detalle[(int)$consec - 1] ?? null;
                if (!$linea) {
                    $omitidas[] = "{$etiqueta}: el archivo plano solo tiene " . count($detalle) . " línea(s).";
                    continue;
                }

                // Control cruzado: la línea N del ERP debe ser el mismo pago que respondió el banco
                if ($doc !== '' && $doc !== trim((string)$linea['id_proveedor'])) {
                    $omitidas[] = "{$etiqueta}: el documento {$doc} no coincide con el de esa línea ({$linea['id_proveedor']}).";
                    continue;
                }
                if ($cuenta !== '' && $cuenta !== trim((string)$linea['cta_proveedor'])) {
                    $omitidas[] = "{$etiqueta}: la cuenta {$cuenta} no coincide con la de esa línea ({$linea['cta_proveedor']}).";
                    continue;
                }
                if ($valor !== '' && (!is_numeric($valor) || abs((float)$valor - (float)$linea['val_a_pagar']) > 0.5)) {
                    $omitidas[] = "{$etiqueta}: el valor {$valor} no coincide con el de esa línea (" . number_format((float)$linea['val_a_pagar'], 0, '', '') . ").";
                    continue;
                }

                // ¿Esa línea ya tiene respuesta? Si está PENDIENTE (1) se actualiza;
                // si ya está resuelta, se omite (archivo importado dos veces).
                $check_pago_de_linea->execute([
                    ':wid_archivo_plano' => (int)$id_archivo,
                    ':wid_factura'       => (int)$linea['id_factura'],
                    ':wid_cuota'         => (int)$linea['id_cuota'],
                ]);
                $previo = $check_pago_de_linea->fetch(PDO::FETCH_ASSOC);

                if ($previo && (int)$previo['estado_pago'] !== 1) {
                    $ya = (int)$previo['estado_pago'] === 2 ? 'APROBADO' : 'RECHAZADO';
                    $omitidas[] = "{$etiqueta}: ya tiene respuesta registrada ({$ya}).";
                    continue;
                }

                // Cada fila en su propio SAVEPOINT: si la base la rechaza, solo se
                // revierte esa fila y el motivo queda en "omitidas".
                $pdo->exec('SAVEPOINT sp_fila');
                try {
                    if ($previo) {
                        $upd_estado_pago_cxp->execute([
                            ':wid_pago'     => (int)$previo['id_pago'],
                            ':westado_pago' => $estado_pago,
                            ':wid_codigo'   => $id_codigo,
                        ]);
                    } else {
                        $ins_pago_cxp->execute([
                            ':wid_archivo_plano' => (int)$id_archivo,
                            ':wid_factura'       => (int)$linea['id_factura'],
                            ':wid_cuota'         => (int)$linea['id_cuota'],
                            ':wfec_pago'         => $fec_pago,
                            ':westado_pago'      => $estado_pago,
                            ':wid_codigo'        => $id_codigo,
                        ]);
                    }
                    $pdo->exec('RELEASE SAVEPOINT sp_fila');
                } catch (Throwable $e) {
                    $pdo->exec('ROLLBACK TO SAVEPOINT sp_fila');
                    $omitidas[] = "{$etiqueta} (factura {$linea['id_factura']}, cuota {$linea['id_cuota']}): "
                                . limpiar_error_pgsql($e->getMessage());
                    continue;
                }

                $aplicadas++;
            }

            $pdo->commit();

            $respuesta['success']   = $aplicadas > 0;
            $respuesta['aplicadas'] = $aplicadas;
            $respuesta['omitidas']  = $omitidas;
            $respuesta['message']   = $aplicadas > 0
                ? "Se registraron {$aplicadas} pago(s) a partir de la respuesta del banco." . (count($omitidas) ? ' ' . count($omitidas) . ' fila(s) omitida(s).' : '')
                : 'Ninguna fila se pudo aplicar.';
            responder_json($respuesta);
        }

        $respuesta['message'] = 'Acción no válida.';
        responder_json($respuesta);

    } catch (Throwable $e) {
        if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
            $pdo->rollBack();
        }
        $mensaje = limpiar_error_pgsql($e->getMessage());
        if (empty($mensaje)) {
            $mensaje = $e->getMessage();
        }
        $respuesta['message'] = $mensaje;
        responder_json($respuesta);
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
// $list_pagos_cxp trae estado_pago numérico (1, 2, 3) y nom_estado_pago
// ('PENDIENTE', 'APROBADO', 'RECHAZADO'); la vista usa el nombre.
$list_pagos_cxp->execute();
$pagos = $list_pagos_cxp->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// TOTALES POR ESTADO
// ============================================================
$total      = count($pagos);
$aprobados  = 0;
$pendientes = 0;
$rechazados = 0;
$val_aprobado = 0.0;

foreach ($pagos as $p) {
    switch ($p['nom_estado_pago']) {
        case 'APROBADO':
            $aprobados++;
            $val_aprobado += (float)$p['val_pago'];
            break;
        case 'PENDIENTE':
            $pendientes++;
            break;
        case 'RECHAZADO':
            $rechazados++;
            break;
    }
}

// dd/mm/aaaa para mostrar
function fecha_larga(?string $iso): string {
    if (empty($iso)) return '—';
    $d = date_create($iso);
    return $d ? $d->format('d/m/Y') : htmlspecialchars($iso);
}

function estado_badge(string $estado): string {
    $clase = 'badge-' . strtolower($estado);
    $texto = ucfirst(strtolower($estado));
    return '<span class="badge ' . $clase . '">' . $texto . '</span>';
}

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
<link rel="stylesheet" href="modules/tescxp/css/pagos_tescxp.css">
<div id="mod-historial" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Historial de Pagos</h1>
            <p>Consulta de todos los pagos registrados sobre cuotas de facturas</p>
        </div>
        <button id="btn-import-historial" class="btn btn-primary">
            <i class="fas fa-upload"></i> Importar respuesta del banco
        </button>
        <input type="file" id="csv-input" accept=".csv,text/csv" style="display:none">
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-receipt"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total pagos</div>
                <div class="stat-value" id="stat-total"><?= $total ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-circle-check"></i></div>
            <div class="stat-info">
                <div class="stat-label">Aprobados</div>
                <div class="stat-value" id="stat-aprobados"><?= $aprobados ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon yellow"><i class="fas fa-clock"></i></div>
            <div class="stat-info">
                <div class="stat-label">Pendientes</div>
                <div class="stat-value" id="stat-pendientes"><?= $pendientes ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon red"><i class="fas fa-circle-xmark"></i></div>
            <div class="stat-info">
                <div class="stat-label">Rechazados</div>
                <div class="stat-value" id="stat-rechazados"><?= $rechazados ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-coins"></i></div>
            <div class="stat-info">
                <div class="stat-label">Valor aprobado</div>
                <div class="stat-value" id="stat-valor" style="font-size:16px">$<?= number_format($val_aprobado, 0, ',', '.') ?></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="pago-search" class="search-input" placeholder="Buscar por pago, factura, proveedor o código del banco...">
        </div>
        <div class="filter-toggle-group">
            <button class="filter-toggle active" data-filter="all">Todos</button>
            <button class="filter-toggle" data-filter="APROBADO">Aprobados</button>
            <button class="filter-toggle" data-filter="PENDIENTE">Pendientes</button>
            <button class="filter-toggle" data-filter="RECHAZADO">Rechazados</button>
        </div>
        <div class="filter-dates">
            <label for="fec-desde">Desde</label>
            <input type="date" id="fec-desde" class="filter-date-input">
            <label for="fec-hasta">Hasta</label>
            <input type="date" id="fec-hasta" class="filter-date-input">
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="pagos-page-size">Filas por página</label>
            <select id="pagos-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="50">50</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="pagos-count"><?= $total ?> resultado<?= $total !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="pagos-table-scroll">
        <table class="data-table">
            <!-- Anchos fijos: las columnas no se mueven al ordenar o cambiar de página -->
            <colgroup>
                <col class="col-pago">
                <col class="col-factura">
                <col class="col-origen">
                <col class="col-fecha">
                <col class="col-valor">
                <col class="col-referencia">
                <col class="col-estado">
                <col class="col-acciones">
            </colgroup>
            <thead>
                <tr>
                    <th class="sortable" data-sort-key="0" data-sort-type="number">Pago <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="1" data-sort-type="number">Factura / Cuota <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="2" data-sort-type="number">Archivo Plano <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="3" data-sort-type="text">Fecha de Pago <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-right sortable" data-sort-key="4" data-sort-type="number">Valor <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="5" data-sort-type="text">Respuesta del Banco <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Estado</th>
                    <th class="text-center">Acciones</th>
                </tr>
            </thead>
            <tbody id="pagos-tbody">
            <?php if (empty($pagos)): ?>
                <tr class="empty-row">
                    <td colspan="8">
                        <div class="empty-state">
                            <i class="fas fa-receipt"></i>
                            <p>No hay pagos registrados</p>
                            <span>Los pagos aparecen aquí al importar la respuesta del banco a un archivo plano</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($pagos as $p):
                    $estado    = (string)$p['nom_estado_pago'];
                    $rechazado = $estado === 'RECHAZADO';
                    $codigo    = trim((string)($p['id_codigo'] ?? ''));
                    $motivo    = trim((string)($p['des_motivo'] ?? ''));
                ?>
                <tr data-id-pago="<?= (int)$p['id_pago'] ?>"
                    data-estado="<?= htmlspecialchars($estado) ?>"
                    data-fecha="<?= htmlspecialchars((string)$p['fec_pago']) ?>"
                    class="<?= $rechazado ? 'rechazado' : '' ?>">
                    <td data-sort="<?= (int)$p['id_pago'] ?>"><strong>#<?= (int)$p['id_pago'] ?></strong></td>
                    <td data-sort="<?= (int)$p['id_factura'] * 1000 + (int)$p['id_cuota'] ?>">
                        Fact. #<?= (int)$p['id_factura'] ?> — Cuota <?= (int)$p['id_cuota'] ?><br>
                        <small style="color:#94a3b8;font-size:11px"><?= htmlspecialchars($p['nom_tercero'] ?? '') ?></small>
                    </td>
                    <td data-sort="<?= (int)$p['id_archivo_plano'] ?>">Archivo #<?= (int)$p['id_archivo_plano'] ?></td>
                    <td data-sort="<?= htmlspecialchars((string)($p['fec_pago'] ?? '')) ?>"><?= fecha_larga($p['fec_pago']) ?></td>
                    <td class="text-right" data-sort="<?= (float)$p['val_pago'] ?>">$<?= number_format((float)$p['val_pago'], 0, ',', '.') ?></td>
                    <td class="ref-bancaria" data-sort="<?= htmlspecialchars($codigo) ?>">
                        <strong><?= htmlspecialchars($codigo) ?></strong>
                        <?php if ($motivo !== ''): ?><br><small style="color:#94a3b8;font-size:11px"><?= htmlspecialchars($motivo) ?></small><?php endif; ?>
                    </td>
                    <td class="text-center"><?= estado_badge($estado) ?></td>
                    <td class="text-center">
                        <button class="btn-icon-sm view" title="Ver detalle"
                                onclick='openDetailModal(<?= json_encode($p, JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_TAG | JSON_HEX_AMP) ?>)'>
                            <i class="fas fa-eye"></i>
                        </button>
                    </td>
                </tr>
                <?php endforeach; ?>
            <?php endif; ?>
            </tbody>
        </table>
      </div>

        <!-- PAGINACIÓN -->
        <div class="table-footer">
            <div class="pagination-nav">
                <span class="pagination-range" id="pagos-range">0 de 0</span>
                <button type="button" id="pagos-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="pagos-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: IMPORTAR RESPUESTA DEL BANCO -->
<div id="modal-import" class="modal-overlay hidden">
    <div class="modal-box" style="max-width:700px">
        <div class="modal-header green">
            <div>
                <h2>Importar respuesta del banco</h2>
                <p id="import-subtitle">Revise las filas antes de aplicarlas</p>
            </div>
            <button class="modal-close" id="close-import-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="import-form" novalidate>
                <input type="hidden" name="btn_importar" value="1">
                <input type="hidden" name="hid_filas_importar" id="hid-filas-importar" value="">

                <p class="config-hint">
                    <i class="fas fa-info-circle"></i>
                    <span>El archivo debe traer <strong>ID Archivo Plano</strong>, <strong>Consecutivo</strong> (número de línea
                    del pago en el archivo plano), <strong>Estado</strong> (APROBADO o RECHAZADO), <strong>Código Respuesta</strong>
                    y <strong>Fecha Pago</strong>. Se verifica que documento, cuenta y valor coincidan con la línea del archivo plano.
                    Si esa línea ya tiene respuesta, se omite.</span>
                </p>

                <div class="import-resumen" id="import-resumen">
                    <div class="import-resumen-item ok">
                        <span class="import-resumen-label">Por aplicar</span>
                        <span class="import-resumen-valor" id="import-validas">0</span>
                    </div>
                    <div class="import-resumen-item bad">
                        <span class="import-resumen-label">Con errores</span>
                        <span class="import-resumen-valor" id="import-invalidas">0</span>
                    </div>
                    <div class="import-resumen-item">
                        <span class="import-resumen-label">Filas leídas</span>
                        <span class="import-resumen-valor" id="import-total">0</span>
                    </div>
                </div>

                <h4 class="detail-subheading"><i class="fas fa-list-check"></i> Filas del archivo</h4>
                <div id="import-filas-list" class="import-list"></div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary" id="cancel-import-modal">Cancelar</button>
            <button type="button" id="import-btn-apply" class="btn btn-primary" disabled>
                <i class="fas fa-check"></i> Aplicar pagos
            </button>
        </div>
    </div>
</div>

<!-- MODAL: DETALLE DEL PAGO -->
<div id="modal-detail" class="modal-overlay hidden">
    <div class="modal-box" style="max-width:560px">
        <div class="modal-header blue">
            <div>
                <h2 id="detail-title">Detalle del Pago</h2>
                <p id="detail-subtitle"></p>
            </div>
            <button class="modal-close" id="close-detail-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <div id="detail-content"></div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" id="close-detail-btn">Cerrar</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>

<script>
// Datos completos para el detalle y los totales filtrados
const pagosData = <?= json_encode($pagos, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG) ?>;
</script>

<script src="modules/tescxp/js/pagos_tescxp.js"></script>


<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
