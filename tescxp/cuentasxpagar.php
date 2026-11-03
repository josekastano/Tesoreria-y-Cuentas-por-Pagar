<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Cuentas por Pagar";
$page_description = "Registro y seguimiento de facturas de proveedores";
$page_icon        = "bi-receipt";
$page_extra_css   = ["../modules/tescxp/css/cuentasxpagar.css"];
$page_extra_js    = ["../modules/tescxp/js/cuentasxpagar.js"];
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');
require_once __DIR__ . '/../compro/src/prepare_compro.php';
// ============================================================
// LIMPIAR MENSAJE DE ERROR DE POSTGRESQL
// ============================================================
function limpiar_error_pgsql(string $msg): string {
    if (preg_match('/ERROR:\s*ERROR:\s*(.+?)(?:\s+CONTEXT:|$)/s', $msg, $m)) {
        return trim($m[1]);
    }
    if (preg_match('/ERROR:\s*(.+?)(?:\s+CONTEXT:|$)/s', $msg, $m)) {
        return trim($m[1]);
    }
    return $msg;
}

// ============================================================
// CARGAR SELECTS (siempre se cargan para la vista inicial)
// ============================================================
$list_proveedores_dias_pago->execute();
$proveedores_dp = $list_proveedores_dias_pago->fetchAll(PDO::FETCH_ASSOC);

// PDO_PGSQL puede devolver los BOOLEAN como true/false o como 't'/'f'
function es_verdadero($v): bool {
    return $v === true || $v === 't' || $v === 'true' || $v === '1' || $v === 1;
}

// Indexado por id_proveedor para resolver los días de pago en PHP al validar
$proveedores_dp_idx   = [];
// Condiciones de crédito pactadas con cada proveedor (módulo Proveedores):
//   credito    → si el proveedor acepta pagos a crédito
//   max_cuotas → máximo de cuotas acordado (1 si no acepta crédito)
$proveedores_cond_idx = [];
foreach ($proveedores_dp as $p) {
    $proveedores_dp_idx[$p['id_proveedor']] = (int)$p['ind_dias_pago'];
    $credito = es_verdadero($p['ind_credito'] ?? false);
    $proveedores_cond_idx[$p['id_proveedor']] = [
        'credito'    => $credito,
        'max_cuotas' => $credito ? max(1, (int)($p['ind_num_cuotas'] ?? 1)) : 1,
    ];
}

// Condiciones de pago efectivas de una factura:
//   - Con orden de compra: manda el método de pago de la orden (met_pago).
//     Si la orden es de contado → 1 cuota. Si es a crédito → hasta el
//     máximo de cuotas pactado con el proveedor.
//   - Compra directa (sin orden): manda lo pactado con el proveedor.
// Devuelve ['credito' => bool, 'max_cuotas' => int].
function condiciones_pago(array $cond_prov, ?bool $oc_credito): array {
    $credito = $oc_credito ?? $cond_prov['credito'];
    return [
        'credito'    => $credito,
        'max_cuotas' => $credito ? max(1, $cond_prov['max_cuotas']) : 1,
    ];
}

// ============================================================
// ÓRDENES DE COMPRA DISPONIBLES
// ============================================================
// tab_enc_ordcomp con ind_estado = 1 (Aprobado) y sin factura asociada:
// son las únicas que se pueden vincular a una factura nueva.
// NOTA: se carga ANTES del bloque POST porque la validación de "nueva
// factura" (más abajo) depende de $ordenes_idx para comprobar que la OC
// existe y a qué proveedor pertenece.

// Total ya facturado contra cada orden, para calcular el saldo disponible
// con la misma lógica que valida fun_insert_cuentasxpagar (val_total -
// suma de facturas ya registradas contra esa orden).
$list_facturado_x_oc = $pdo->prepare(
    "SELECT id_ordencompra, COALESCE(SUM(val_factura), 0) AS val_facturado
       FROM tab_cuentasxpagar
      WHERE id_ordencompra IS NOT NULL
      GROUP BY id_ordencompra"
);
$list_facturado_x_oc->execute();
$facturado_x_oc = [];
foreach ($list_facturado_x_oc->fetchAll(PDO::FETCH_ASSOC) as $f) {
    $facturado_x_oc[(string)$f['id_ordencompra']] = (float)$f['val_facturado'];
}

$list_ordencompra->execute();
$ordenes_todas = $list_ordencompra->fetchAll(PDO::FETCH_ASSOC);

// Se excluyen las órdenes que no están Aprobadas (Pendientes o Anuladas no
// pasan la validación de fun_insert_cuentasxpagar) y las que ya no tienen
// saldo disponible (ya facturadas por el valor total de la orden): ninguna
// de las dos se puede usar en una factura nueva, así que no tiene sentido
// mostrarlas como opción.
$ordenes = [];
foreach ($ordenes_todas as $o) {
    if ((int)$o['ind_estado'] !== 1) {
        continue;
    }

    $facturado = $facturado_x_oc[(string)$o['id_ordencompra']] ?? 0.0;
    $saldo     = (float)$o['val_total'] - $facturado;
    if ($saldo <= 0) {
        continue;
    }
    $o['val_facturado']        = $facturado;
    $o['val_saldo_disponible'] = $saldo;
    $ordenes[] = $o;
}

// Índice id_ordencompra => id_proveedor, para validar la pareja en el POST
// e índice id_ordencompra => ¿es a crédito? (met_pago de la orden)
// e índice id_ordencompra => saldo por facturar (el valor que debe llevar la factura)
$ordenes_idx         = [];
$ordenes_credito_idx = [];
$ordenes_saldo_idx   = [];
foreach ($ordenes as $o) {
    $ordenes_idx[(string)$o['id_ordencompra']]         = $o['id_proveedor'];
    $ordenes_credito_idx[(string)$o['id_ordencompra']] = es_verdadero($o['met_pago'] ?? false);
    $ordenes_saldo_idx[(string)$o['id_ordencompra']]   = (float)$o['val_saldo_disponible'];
}

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json');
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- OBTENER CUOTAS DE UNA FACTURA (para el modal de detalle) ----------
        if (isset($_POST['btn_ver_cuotas'])) {
            $id_factura = (int)($_POST['hid_id_factura'] ?? 0);
            if ($id_factura <= 0) {
                throw new Exception('Factura no válida.');
            }

            // El placeholder de $list_cuotasxfactura (prepare_tescxp.php) es :wid_factura
            $list_cuotasxfactura->execute([':wid_factura' => $id_factura]);
            $cuotas = $list_cuotasxfactura->fetchAll(PDO::FETCH_ASSOC);

            $respuesta['success'] = true;
            $respuesta['cuotas']  = $cuotas;
            echo json_encode($respuesta);
            exit;
        }

        // ---------- NUEVA FACTURA ----------
        if (isset($_POST['btn_nuevo'])) {
            $id_factura   = (int)($_POST['txt_id_factura']    ?? 0);
            $id_proveedor = trim($_POST['sel_id_proveedor']   ?? '');
            $fec_emision  = trim($_POST['txt_fec_emision']    ?? '');
            $val_factura  = (float)($_POST['txt_val_factura'] ?? 0);
            $num_cuotas   = (int)($_POST['txt_num_cuotas']    ?? 0);
            $tiene_oc     = ($_POST['rad_tiene_oc'] ?? 'no') === 'si';
            $id_ordencompra = trim($_POST['hid_id_ordencompra'] ?? '');

            $errores = [];

            if ($id_factura < 1 || $id_factura > 99999999) {
                $errores['err-new-id-factura'] = 'El número de factura debe estar entre 1 y 99.999.999.';
            }
            if (empty($id_proveedor) || !isset($proveedores_dp_idx[$id_proveedor])) {
                $errores['err-new-proveedor'] = 'Seleccione un proveedor válido.';
            }
            if (empty($fec_emision)) {
                $errores['err-new-emision'] = 'La fecha de emisión es obligatoria.';
            }
            if ($val_factura < 0 || $val_factura > 9999999999) {
                $errores['err-new-valor'] = 'El valor de la factura debe estar entre 0 y 9.999.999.999.';
            }
            if ($num_cuotas < 1 || $num_cuotas > 99) {
                $errores['err-new-cuotas'] = 'El número de cuotas debe estar entre 1 y 99.';
            }

            // id_ordencompra DECIMAL(6,0) CHECK(> 0); NULL cuando la factura no
            // viene de una orden (compra directa digitada en ventanilla)
            if ($tiene_oc) {
                if ($id_ordencompra === '' || !ctype_digit($id_ordencompra) || (int)$id_ordencompra < 1) {
                    $errores['err-new-oc'] = 'Seleccione la orden de compra de la factura.';
                } elseif (!isset($ordenes_idx[$id_ordencompra])) {
                    $errores['err-new-oc'] = 'La orden de compra no está disponible.';
                } elseif ($ordenes_idx[$id_ordencompra] !== $id_proveedor) {
                    $errores['err-new-oc'] = 'La orden de compra pertenece a otro proveedor.';
                } else {
                    // Con orden de compra el valor no se digita: es el saldo
                    // por facturar de la orden. Se toma del servidor, no del
                    // formulario, para que no se pueda alterar.
                    $val_factura = $ordenes_saldo_idx[$id_ordencompra];
                }
            }

            // Número de cuotas según la modalidad de pago (contado / crédito).
            // Solo se valida si el proveedor y la orden ya son válidos, porque
            // la modalidad depende de ellos.
            if (!isset($errores['err-new-proveedor']) && !isset($errores['err-new-oc'])
                && !isset($errores['err-new-cuotas'])) {
                $oc_credito = $tiene_oc ? $ordenes_credito_idx[$id_ordencompra] : null;
                $cond       = condiciones_pago($proveedores_cond_idx[$id_proveedor], $oc_credito);

                if (!$cond['credito'] && $num_cuotas !== 1) {
                    $errores['err-new-cuotas'] = $tiene_oc
                        ? 'La orden de compra es de contado: la factura debe registrarse en 1 sola cuota.'
                        : 'El proveedor no acepta crédito: la factura debe registrarse en 1 sola cuota.';
                } elseif ($num_cuotas > $cond['max_cuotas']) {
                    $errores['err-new-cuotas'] = "El máximo de cuotas pactado con el proveedor es {$cond['max_cuotas']}.";
                }
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            // Fecha de vencimiento = fecha de emisión + días de pago del proveedor
            $dias_pago       = $proveedores_dp_idx[$id_proveedor];
            $fec_vencimiento = date('Y-m-d', strtotime($fec_emision . " +{$dias_pago} days"));

            $ins_cuentasxpagar->execute([
                ':wid_factura'      => $id_factura,
                ':wid_proveedor'    => $id_proveedor,
                ':wfec_emision'     => $fec_emision,
                ':wfec_vencimiento' => $fec_vencimiento,
                ':wval_factura'     => $val_factura,
                ':wnum_cuotas'      => $num_cuotas,
                ':wid_ordencompra'  => $tiene_oc ? (int)$id_ordencompra : null,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Factura registrada correctamente. Las cuotas se generaron automáticamente.';
            echo json_encode($respuesta);
            exit;
        }

        // Si no se reconoce ninguna acción
        $respuesta['message'] = 'Acción no válida.';
        echo json_encode($respuesta);
        exit;

    } catch (Exception $e) {
        $mensaje = limpiar_error_pgsql($e->getMessage());
        if (empty($mensaje)) {
            $mensaje = $e->getMessage();
        }
        $respuesta['message'] = $mensaje;
        echo json_encode($respuesta);
        exit;
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
$list_cuentasxpagar->execute();
$facturas = $list_cuentasxpagar->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
<link rel="stylesheet" href="modules/tescxp/css/cuentasxpagar.css">
<div id="mod-cuentasxpagar" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Cuentas por Pagar</h1>
            <p>Registro de facturas de proveedores y seguimiento de saldos</p>
        </div>
        <button id="btn-add-factura" class="btn btn-primary">
            <i class="fas fa-plus"></i> Nueva Factura
        </button>
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <?php
        $total       = count($facturas);
        $pendientes  = count(array_filter($facturas, fn($f) => !($f['ind_estado'] === 't' || $f['ind_estado'] === true)));
        $pagadas     = $total - $pendientes;
        $hoy         = date('Y-m-d');
        $vencidas    = count(array_filter($facturas, fn($f) =>
            !($f['ind_estado'] === 't' || $f['ind_estado'] === true) && $f['fec_vencimiento'] < $hoy
        ));
        $saldo_total = array_sum(array_column($facturas, 'val_saldo'));
        ?>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-file-invoice-dollar"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total facturas</div>
                <div class="stat-value" id="stat-total"><?= $total ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon yellow"><i class="fas fa-clock"></i></div>
            <div class="stat-info">
                <div class="stat-label">En deuda</div>
                <div class="stat-value" id="stat-pendientes"><?= $pendientes ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon red"><i class="fas fa-exclamation-triangle"></i></div>
            <div class="stat-info">
                <div class="stat-label">Vencidas</div>
                <div class="stat-value" id="stat-vencidas"><?= $vencidas ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-coins"></i></div>
            <div class="stat-info">
                <div class="stat-label">Saldo total por pagar</div>
                <div class="stat-value" id="stat-saldo" style="font-size:16px">$<?= number_format($saldo_total, 0, ',', '.') ?></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="factura-search" class="search-input" placeholder="Buscar por proveedor o número de factura...">
        </div>
        <div class="filter-toggle-group">
            <button class="filter-toggle active" data-filter="all">Todas</button>
            <button class="filter-toggle" data-filter="pendiente">En deuda</button>
            <button class="filter-toggle" data-filter="vencida">Vencidas</button>
            <button class="filter-toggle" data-filter="pagada">Pagadas</button>
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="facturas-page-size">Filas por página</label>
            <select id="facturas-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="50">50</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="facturas-count"><?= $total ?> resultado<?= $total !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="facturas-table-scroll">
        <table class="data-table">
            <!-- Anchos fijos: las columnas no se mueven al ordenar o cambiar de página -->
            <colgroup>
                <col class="col-factura">
                <col class="col-oc">
                <col class="col-proveedor">
                <col class="col-emision">
                <col class="col-vencimiento">
                <col class="col-valor">
                <col class="col-saldo">
                <col class="col-cuotas">
                <col class="col-estado">
            </colgroup>
            <thead>
                <tr>
                    <th class="sortable" data-sort-key="0" data-sort-type="number">Factura <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="1" data-sort-type="number">Orden de Compra <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="2" data-sort-type="text">Proveedor <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="3" data-sort-type="text">Emisión <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="4" data-sort-type="text">Vencimiento <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-right sortable" data-sort-key="5" data-sort-type="number">Valor <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-right sortable" data-sort-key="6" data-sort-type="number">Saldo <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center sortable" data-sort-key="7" data-sort-type="number">Cuotas <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Estado</th>
                </tr>
            </thead>
            <tbody id="facturas-tbody">
            <?php if (empty($facturas)): ?>
                <tr class="empty-row">
                    <td colspan="9">
                        <div class="empty-state">
                            <i class="fas fa-file-invoice"></i>
                            <p>No hay facturas registradas</p>
                            <span>Haga clic en "Nueva Factura" para agregar la primera</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($facturas as $f):
                    $pagada      = ($f['ind_estado'] === 't' || $f['ind_estado'] === true);
                    $esta_vencida = !$pagada && $f['fec_vencimiento'] < $hoy;

                    if ($pagada) {
                        $badge = '<span class="badge badge-active">Pagada</span>';
                        $filtro_estado = 'pagada';
                    } elseif ($esta_vencida) {
                        $badge = '<span class="badge badge-inactive">Vencida</span>';
                        $filtro_estado = 'vencida';
                    } else {
                        $badge = '<span class="badge badge-inactive" style="background:#fffbeb;color:#f59e0b">En deuda</span>';
                        $filtro_estado = 'pendiente';
                    }

                    $id_fact_esc = htmlspecialchars($f['id_factura']);
                ?>
                <tr data-estado="<?= $filtro_estado ?>" onclick="openDetailModal(<?= $id_fact_esc ?>)">
                    <td data-sort="<?= (int)$f['id_factura'] ?>"><strong>#<?= $id_fact_esc ?></strong></td>
                    <td data-sort="<?= !empty($f['id_ordencompra']) ? (int)$f['id_ordencompra'] : 0 ?>">
                        <?php if (!empty($f['id_ordencompra'])): ?>
                            <span class="oc-tag">OC #<?= (int)$f['id_ordencompra'] ?></span>
                        <?php else: ?>
                            <span class="oc-directa">Compra directa</span>
                        <?php endif; ?>
                    </td>
                    <td data-sort="<?= htmlspecialchars($f['nom_tercero']) ?>">
                        <?= htmlspecialchars($f['nom_tercero']) ?><br>
                        <small style="color:#94a3b8;font-size:11px"><?= htmlspecialchars($f['id_proveedor']) ?></small>
                    </td>
                    <td data-sort="<?= htmlspecialchars(date('Y-m-d', strtotime($f['fec_emision']))) ?>"><?= htmlspecialchars(date('d/m/Y', strtotime($f['fec_emision']))) ?></td>
                    <td data-sort="<?= htmlspecialchars(date('Y-m-d', strtotime($f['fec_vencimiento']))) ?>"><?= htmlspecialchars(date('d/m/Y', strtotime($f['fec_vencimiento']))) ?></td>
                    <td class="text-right" data-sort="<?= (float)$f['val_factura'] ?>">$<?= number_format((float)$f['val_factura'], 0, ',', '.') ?></td>
                    <td class="text-right" data-sort="<?= (float)$f['val_saldo'] ?>">$<?= number_format((float)$f['val_saldo'], 0, ',', '.') ?></td>
                    <td class="text-center" data-sort="<?= (int)$f['num_cuotas'] ?>"><?= htmlspecialchars($f['num_cuotas']) ?></td>
                    <td class="text-center"><?= $badge ?></td>
                </tr>
                <?php endforeach; ?>
            <?php endif; ?>
            </tbody>
        </table>
      </div>

        <!-- PAGINACIÓN -->
        <div class="table-footer">
            <div class="pagination-nav">
                <span class="pagination-range" id="facturas-range">0 de 0</span>
                <button type="button" id="facturas-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="facturas-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: NUEVA FACTURA -->
<div id="modal-new-factura" class="modal-overlay hidden">
    <div class="modal-box modal-box-factura">
        <div class="modal-header green">
            <div>
                <h2>Nueva Factura</h2>
                <p>Registre una factura de proveedor</p>
            </div>
            <button class="modal-close btn-close-new-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-factura-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <!-- Número y proveedor comparten fila (el modal es más ancho) -->
                <div class="form-grid form-grid-factura">
                <div class="form-field">
                    <label class="form-label">Número de Factura <span class="required">*</span></label>
                    <input type="number" id="new-id-factura" name="txt_id_factura" class="form-input" placeholder="Ej: 1024" min="1" max="99999999">
                    <span class="field-error" id="err-new-id-factura"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Proveedor <span class="required">*</span></label>
                    <select id="new-id-proveedor" name="sel_id_proveedor" class="form-select">
                        <option value="">Seleccione...</option>
                        <?php foreach ($proveedores_dp as $p):
                            $cond_p = $proveedores_cond_idx[$p['id_proveedor']];
                        ?>
                            <option value="<?= htmlspecialchars($p['id_proveedor']) ?>"
                                    data-dias="<?= (int)$p['ind_dias_pago'] ?>"
                                    data-credito="<?= $cond_p['credito'] ? '1' : '0' ?>"
                                    data-max-cuotas="<?= (int)$cond_p['max_cuotas'] ?>">
                                <?= htmlspecialchars($p['nom_tercero']) ?> — <?= (int)$p['ind_dias_pago'] ?> días de pago
                            </option>
                        <?php endforeach; ?>
                    </select>
                    <span class="field-error" id="err-new-proveedor"></span>
                </div>
                </div>
                <div class="form-grid">
                    <div class="form-field">
                        <label class="form-label">Fecha de Emisión <span class="required">*</span></label>
                        <input type="hidden" id="new-fec-emision" name="txt_fec_emision" value="">
                        <button type="button" class="form-input dp-trigger" id="new-fec-emision-btn" data-target="new-fec-emision" data-max="<?= date('Y-m-d') ?>">
                            <span class="dp-trigger-texto vacio">Seleccione una fecha</span>
                            <i class="fas fa-calendar-alt"></i>
                        </button>
                        <span class="field-error" id="err-new-emision"></span>
                    </div>
                    <div class="form-field">
                        <label class="form-label">Fecha de Vencimiento</label>
                        <input type="text" id="new-fec-vencimiento" class="form-input" disabled placeholder="Seleccione un proveedor">
                        <p class="field-hint">Calculada automáticamente: emisión + días de pago del proveedor.</p>
                    </div>
                </div>
                <!-- Pregunta de orden de compra y selector de la orden en la misma fila -->
                <div class="form-grid form-grid-oc">
                <div class="form-field">
                    <label class="form-label">¿La factura tiene orden de compra? <span class="required">*</span></label>
                    <div class="oc-choice">
                        <label class="oc-choice-opt">
                            <input type="radio" name="rad_tiene_oc" value="no" checked="checked">
                            <span>No, compra directa</span>
                        </label>
                        <label class="oc-choice-opt">
                            <input type="radio" name="rad_tiene_oc" value="si">
                            <span>Sí, viene de una orden</span>
                        </label>
                    </div>
                </div>

                <div id="oc-picker" class="form-field" style="display:none">
                    <input type="hidden" name="hid_id_ordencompra" id="new-id-ordencompra" value="">
                    <label class="form-label">Orden de Compra <span class="required">*</span></label>

                    <!-- Resumen de lo elegido; el detalle se busca en su propio modal -->
                    <div class="oc-selected" id="oc-selected">
                        <div class="oc-selected-info">
                            <span class="oc-selected-num" id="oc-selected-num">Ninguna orden seleccionada</span>
                            <span class="oc-selected-meta" id="oc-selected-meta">Busque la orden que corresponde a esta factura.</span>
                        </div>
                        <button type="button" class="btn btn-secondary" id="btn-open-oc-modal">
                            <i class="fas fa-magnifying-glass"></i> Buscar orden
                        </button>
                    </div>
                    <span class="field-error" id="err-new-oc"></span>
                </div>
                </div>

                <!-- CONDICIONES DE PAGO
                     La modalidad (contado / crédito) la define la orden de compra;
                     en compra directa, lo pactado con el proveedor. La arma
                     actualizarModalidadPago() en cuentasxpagar.js. -->
                <div class="pago-modalidad" id="pago-modalidad" data-estado="pendiente">
                    <span class="pago-modalidad-icono"><i class="fas fa-hand-holding-dollar" id="pago-modalidad-icono"></i></span>
                    <div class="pago-modalidad-info">
                        <span class="pago-modalidad-titulo" id="pago-modalidad-titulo">Modalidad de pago</span>
                        <span class="pago-modalidad-detalle" id="pago-modalidad-detalle">Seleccione un proveedor para conocer la modalidad de pago.</span>
                    </div>
                    <span class="pago-modalidad-badge" id="pago-modalidad-badge" style="display:none"></span>
                </div>

                <div class="form-grid">
                    <div class="form-field">
                        <label class="form-label">Valor de la Factura <span class="required">*</span></label>
                        <!-- Con orden de compra queda bloqueado (readonly) con el saldo por facturar de la orden -->
                        <div class="valor-wrap">
                            <input type="number" id="new-val-factura" name="txt_val_factura" class="form-input" placeholder="Ej: 1500000" min="0" max="9999999999" step="1">
                            <i class="fas fa-lock valor-lock" id="valor-lock" style="display:none"></i>
                        </div>
                        <p class="field-hint" id="valor-hint"></p>
                        <span class="field-error" id="err-new-valor"></span>
                    </div>
                    <div class="form-field">
                        <label class="form-label">Número de Cuotas <span class="required">*</span></label>
                        <!-- A crédito: se elige entre 1 y el máximo pactado -->
                        <input type="number" id="new-num-cuotas" name="txt_num_cuotas" class="form-input" placeholder="Ej: 1" min="1" max="1" value="1" style="display:none">
                        <!-- De contado o sin datos todavía: valor fijo, no editable -->
                        <div class="cuotas-fijas" id="cuotas-fijas">
                            <span id="cuotas-fijas-texto">1 cuota</span>
                            <i class="fas fa-lock"></i>
                        </div>
                        <p class="field-hint" id="cuotas-hint"></p>
                        <span class="field-error" id="err-new-cuotas"></span>
                    </div>
                </div>
                <p class="config-hint" id="new-cuota-preview" style="display:none"></p>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar Factura</button>
        </div>
    </div>
</div>

<!-- MODAL: SELECCIONAR ORDEN DE COMPRA -->
<div id="modal-oc" class="modal-overlay hidden">
    <div class="modal-box" style="max-width:820px">
        <div class="modal-header blue">
            <div>
                <h2>Seleccionar Orden de Compra</h2>
                <p>Órdenes aprobadas que aún no tienen factura asociada</p>
            </div>
            <button class="modal-close" id="close-oc-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">

            <!-- Filtros del selector -->
            <div class="oc-filter-bar">
                <div class="search-wrapper">
                    <span class="search-icon"><i class="fas fa-search"></i></span>
                    <input type="text" id="oc-search" class="search-input" placeholder="Buscar por número de orden o proveedor...">
                </div>
                <select id="oc-filtro-proveedor" class="form-select">
                    <option value="">Todos los proveedores</option>
                    <?php foreach ($proveedores_dp as $p): ?>
                        <option value="<?= htmlspecialchars($p['id_proveedor']) ?>">
                            <?= htmlspecialchars($p['nom_tercero']) ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </div>
            <p class="field-hint" id="oc-prov-lock-hint" style="display:none"></p>

            <div class="oc-filter-bar oc-filter-bar-sec">
                <div class="oc-filter-field">
                    <label for="oc-fec-desde-btn">Emitidas desde</label>
                    <input type="hidden" id="oc-fec-desde" value="">
                    <button type="button" class="form-input dp-trigger" id="oc-fec-desde-btn" data-target="oc-fec-desde" data-formato="corto" data-placeholder="Cualquier fecha">
                        <span class="dp-trigger-texto vacio">Cualquier fecha</span>
                        <i class="fas fa-calendar-alt"></i>
                    </button>
                </div>
                <div class="oc-filter-field">
                    <label for="oc-fec-hasta-btn">Hasta</label>
                    <input type="hidden" id="oc-fec-hasta" value="">
                    <button type="button" class="form-input dp-trigger" id="oc-fec-hasta-btn" data-target="oc-fec-hasta" data-formato="corto" data-placeholder="Cualquier fecha">
                        <span class="dp-trigger-texto vacio">Cualquier fecha</span>
                        <i class="fas fa-calendar-alt"></i>
                    </button>
                </div>
                <div class="filter-toggle-group">
                    <button type="button" class="oc-toggle active" data-met="all">Todas</button>
                    <button type="button" class="oc-toggle" data-met="credito">Crédito</button>
                    <button type="button" class="oc-toggle" data-met="contado">Contado</button>
                </div>
                <button type="button" id="btn-oc-clear" class="btn-clear-filter" style="display:none">
                    <i class="fas fa-times"></i> Limpiar
                </button>
                <span class="filter-info" id="oc-count"></span>
            </div>

            <div id="oc-list" class="oc-list"></div>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary" id="cancel-oc-modal">Cancelar</button>
            <button type="button" id="btn-confirm-oc" class="btn btn-primary" disabled="disabled">
                <i class="fas fa-check"></i> Usar esta orden
            </button>
        </div>
    </div>
</div>

<!-- MODAL: DETALLE DE FACTURA (con cuotas) -->
<div id="modal-detail" class="modal-overlay hidden">
    <div class="modal-box" style="max-width:560px">
        <div class="modal-header blue">
            <div><h2 id="detail-title">Detalle de Factura</h2><p id="detail-subtitle"></p></div>
            <button class="modal-close" id="close-detail-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <div id="detail-content">
                <div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>Cargando...</p></div>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" id="close-detail-btn">Cerrar</button>
        </div>
    </div>
</div>

<!-- CALENDARIO FLOTANTE PARA ELEGIR FECHAS (mismo estilo que Cronograma de Pagos;
     aquí se puede elegir cualquier fecha — lo arma cuentasxpagar.js) -->
<div id="dp-pop" class="dp-pop hidden" role="dialog" aria-label="Seleccionar fecha">
    <div class="dp-head">
        <div class="dp-nav-grupo">
            <button type="button" class="dp-nav" id="dp-prev-anio" aria-label="Año anterior" title="Año anterior"><i class="fas fa-angles-left"></i></button>
            <button type="button" class="dp-nav" id="dp-prev" aria-label="Mes anterior" title="Mes anterior"><i class="fas fa-chevron-left"></i></button>
        </div>
        <strong id="dp-titulo"></strong>
        <div class="dp-nav-grupo">
            <button type="button" class="dp-nav" id="dp-next" aria-label="Mes siguiente" title="Mes siguiente"><i class="fas fa-chevron-right"></i></button>
            <button type="button" class="dp-nav" id="dp-next-anio" aria-label="Año siguiente" title="Año siguiente"><i class="fas fa-angles-right"></i></button>
        </div>
    </div>
    <div class="dp-semana">
        <span>Dom</span><span>Lun</span><span>Mar</span><span>Mié</span><span>Jue</span><span>Vie</span><span>Sáb</span>
    </div>
    <div class="dp-grid" id="dp-grid"></div>
    <div class="dp-acciones">
        <button type="button" class="dp-accion" id="dp-hoy">Hoy</button>
        <button type="button" class="dp-accion secundaria" id="dp-borrar">Borrar</button>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>

<!-- DATOS PARA EL JS -->
<script>
const ordenesData = <?= json_encode($ordenes) ?>;
const facturasData = <?= json_encode(array_values($facturas), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP) ?>;
</script>

<script src="modules/tescxp/js/cuentasxpagar.js"></script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
