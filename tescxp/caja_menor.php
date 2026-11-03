<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Caja Menor";
$page_description = "Gestión de fondos fijos y sus movimientos";
$page_icon        = "bi-cash-coin";
$page_extra_css   = ["../modules/tescxp/css/caja_menor.css"];
$page_extra_js    = ["../modules/tescxp/js/caja_menor.js"];
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
// LARGO DE UN TEXTO EN CARACTERES (no en bytes)
// strlen() cuenta "é" o "ñ" como 2; esto cuenta letras reales.
// No depende de la extensión mbstring (que puede no estar activa).
// ============================================================
function largo_texto(string $texto): int {
    $total = preg_match_all('/./us', $texto);
    return $total === false ? strlen($texto) : $total;
}

// ============================================================
// ¿LA CAJA ESTÁ ACTIVA?
// PDO_pgsql puede devolver el boolean como true/false o como 't'/'f'
// según la configuración; se aceptan todas las variantes.
// ============================================================
function es_caja_activa($valor): bool {
    return $valor === true || $valor === 't' || $valor === 'true' || $valor === 1 || $valor === '1';
}

// ============================================================
// ESTADOS DE MOVIMIENTO
// ============================================================
const ESTADOS_MOVIMIENTO = [
    1 => 'Pendiente',
    2 => 'Aprobado',
    3 => 'Reembolsado',
];

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json');
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- OBTENER MOVIMIENTOS DE UNA CAJA (para el modal de detalle) ----------
        if (isset($_POST['btn_ver_movimientos'])) {
            $id_caja_menor = (int)($_POST['hid_id_caja_menor'] ?? 0);
            if ($id_caja_menor <= 0) {
                throw new Exception('Caja no válida.');
            }

            $list_det_caja_menor->execute([':wid_caja_menor' => $id_caja_menor]);
            $movimientos = $list_det_caja_menor->fetchAll(PDO::FETCH_ASSOC);

            $respuesta['success']     = true;
            $respuesta['movimientos'] = $movimientos;
            echo json_encode($respuesta);
            exit;
        }

        // ---------- NUEVA CAJA MENOR ----------
        if (isset($_POST['btn_nuevo'])) {
            $nom_caja_menor = trim($_POST['txt_nom_caja_menor']  ?? '');
            $monto_asignado = (float)($_POST['txt_monto_asignado'] ?? 0);

            $errores = [];

            if (largo_texto($nom_caja_menor) < 3 || largo_texto($nom_caja_menor) > 50) {
                $errores['err-new-nombre'] = 'El nombre debe tener entre 3 y 50 caracteres.';
            }
            if ($monto_asignado < 0 || $monto_asignado > 99999999) {
                $errores['err-new-monto'] = 'El monto asignado debe estar entre 0 y 99.999.999.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $ins_enc_caja_menor->execute([
                ':wnom_caja_menor' => $nom_caja_menor,
                ':wmonto_asignado' => $monto_asignado,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Caja menor creada correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- EDITAR NOMBRE DE CAJA ----------
        if (isset($_POST['btn_editar'])) {
            $id_caja_menor  = (int)($_POST['hid_edit_id']           ?? 0);
            $nom_caja_menor = trim($_POST['txt_edit_nom_caja_menor'] ?? '');

            $errores = [];

            if ($id_caja_menor <= 0) {
                $errores['err-edit-nombre'] = 'Caja no válida.';
            }
            if (largo_texto($nom_caja_menor) < 3 || largo_texto($nom_caja_menor) > 50) {
                $errores['err-edit-nombre'] = 'El nombre debe tener entre 3 y 50 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $upd_enc_caja_menor->execute([
                ':wid_caja_menor'  => $id_caja_menor,
                ':wnom_caja_menor' => $nom_caja_menor,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Caja menor actualizada correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- NUEVO MOVIMIENTO ----------
        // La validación de "caja cerrada" la hace fun_insert_det_caja_menor en la BD;
        // si la caja está cerrada, la excepción llega al catch y se muestra como toast.
        if (isset($_POST['btn_nuevo_movimiento'])) {
            $id_caja_menor    = (int)($_POST['hid_mov_id_caja']      ?? 0);
            $concepto         = trim($_POST['txt_concepto']           ?? '');
            $val_movimiento   = (float)($_POST['txt_val_movimiento']  ?? 0);
            $fecha_movimiento = trim($_POST['txt_fecha_movimiento']   ?? '');

            if ($id_caja_menor <= 0) {
                throw new Exception('Caja no válida.');
            }

            $errores = [];

            if (largo_texto($concepto) < 1 || largo_texto($concepto) > 200) {
                $errores['err-mov-concepto'] = 'El concepto debe tener entre 1 y 200 caracteres.';
            }
            if ($val_movimiento <= 0 || $val_movimiento > 99999999) {
                $errores['err-mov-valor'] = 'El valor del movimiento debe ser mayor a 0 y hasta 99.999.999.';
            }
            if (empty($fecha_movimiento)) {
                $errores['err-mov-fecha'] = 'La fecha del movimiento es obligatoria.';
            } elseif (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $fecha_movimiento)) {
                $errores['err-mov-fecha'] = 'La fecha del movimiento no es válida.';
            } elseif ($fecha_movimiento < date('Y-m-d')) {
                $errores['err-mov-fecha'] = 'La fecha del movimiento no puede ser anterior al día de hoy.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $ins_det_caja_menor->execute([
                ':wid_caja_menor'    => $id_caja_menor,
                ':wconcepto'         => $concepto,
                ':wval_movimiento'   => $val_movimiento,
                ':wfecha_movimiento' => $fecha_movimiento,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Movimiento registrado correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- CAMBIAR ESTADO DE MOVIMIENTO ----------
        if (isset($_POST['btn_cambiar_estado'])) {
            $id_caja_menor = (int)($_POST['hid_estado_id_caja']  ?? 0);
            $id_movimiento = (int)($_POST['hid_estado_id_mov']   ?? 0);
            $nuevo_estado  = (int)($_POST['sel_nuevo_estado']    ?? 0);

            if ($id_caja_menor <= 0 || $id_movimiento <= 0) {
                throw new Exception('Movimiento no válido.');
            }
            if ($nuevo_estado < 1 || $nuevo_estado > 3) {
                throw new Exception('Estado no válido.');
            }

            $upd_det_caja_menor->execute([
                ':wid_caja_menor' => $id_caja_menor,
                ':wid_movimiento' => $id_movimiento,
                ':wind_estado'    => $nuevo_estado,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Estado del movimiento actualizado correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- CERRAR CAJA MENOR ----------
        if (isset($_POST['btn_cerrar_caja'])) {
            $id_caja_menor = (int)($_POST['hid_id_caja_menor'] ?? 0);

            if ($id_caja_menor <= 0) {
                throw new Exception('Caja no válida.');
            }

            $del_enc_caja_menor->execute([':wid_caja_menor' => $id_caja_menor]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Caja menor cerrada correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // Si no se reconoce ninguna acción
        $respuesta['message'] = 'Acción no válida.';
        echo json_encode($respuesta);
        exit;

    } catch (Throwable $e) { // Throwable: también atrapa errores fatales de PHP y responde JSON
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
$list_enc_caja_menor->execute();
$cajas = $list_enc_caja_menor->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
<link rel="stylesheet" href="modules/tescxp/css/caja_menor.css">
<div id="mod-caja-menor" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Caja Menor</h1>
            <p>Fondos fijos asignados y seguimiento de sus movimientos</p>
        </div>
        <button id="btn-add-caja" class="btn btn-primary">
            <i class="fas fa-plus"></i> Nueva Caja
        </button>
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <?php
        $total      = count($cajas);
        $activas    = count(array_filter($cajas, fn($c) => es_caja_activa($c['ind_estado_caja_m'])));
        $disponible_total = array_sum(array_column($cajas, 'monto_disponible'));
        $asignado_total   = array_sum(array_column($cajas, 'monto_asignado'));
        ?>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-cash-register"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total cajas</div>
                <div class="stat-value" id="stat-total"><?= $total ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-check-circle"></i></div>
            <div class="stat-info">
                <div class="stat-label">Activas</div>
                <div class="stat-value" id="stat-activas"><?= $activas ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon yellow"><i class="fas fa-coins"></i></div>
            <div class="stat-info">
                <div class="stat-label">Disponible total</div>
                <div class="stat-value" id="stat-disponible" style="font-size:16px">$<?= number_format($disponible_total, 0, ',', '.') ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-wallet"></i></div>
            <div class="stat-info">
                <div class="stat-label">Asignado total</div>
                <div class="stat-value" id="stat-asignado" style="font-size:16px">$<?= number_format($asignado_total, 0, ',', '.') ?></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="caja-search" class="search-input" placeholder="Buscar por nombre de caja...">
        </div>
        <div class="filter-toggle-group">
            <button class="filter-toggle active" data-filter="all">Todas</button>
            <button class="filter-toggle" data-filter="activa">Activas</button>
            <button class="filter-toggle" data-filter="cerrada">Cerradas</button>
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="cajas-page-size">Filas por página</label>
            <select id="cajas-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="50">50</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="cajas-count"><?= $total ?> resultado<?= $total !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="cajas-table-scroll">
        <table class="data-table">
            <!-- Anchos fijos: las columnas no se mueven al ordenar o cambiar de página -->
            <colgroup>
                <col class="col-caja">
                <col class="col-apertura">
                <col class="col-asignado">
                <col class="col-disponible">
                <col class="col-estado">
                <col class="col-acciones">
            </colgroup>
            <thead>
                <tr>
                    <th class="sortable" data-sort-key="0" data-sort-type="text">Caja <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="1" data-sort-type="text">Apertura <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-right sortable" data-sort-key="2" data-sort-type="number">Asignado <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-right sortable" data-sort-key="3" data-sort-type="number">Disponible <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Estado</th>
                    <th class="text-center">Acciones</th>
                </tr>
            </thead>
            <tbody id="cajas-tbody">
            <?php if (empty($cajas)): ?>
                <tr class="empty-row">
                    <td colspan="6">
                        <div class="empty-state">
                            <i class="fas fa-cash-register"></i>
                            <p>No hay cajas menores registradas</p>
                            <span>Haga clic en "Nueva Caja" para agregar la primera</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($cajas as $c):
                    $activa      = es_caja_activa($c['ind_estado_caja_m']);
                    $badge       = $activa
                        ? '<span class="badge badge-active">Activa</span>'
                        : '<span class="badge badge-inactive">Cerrada</span>';
                    $filtro      = $activa ? 'activa' : 'cerrada';
                    $id_caja_esc = htmlspecialchars($c['id_caja_menor']);
                    $pct_disp    = $c['monto_asignado'] > 0
                        ? round(($c['monto_disponible'] / $c['monto_asignado']) * 100)
                        : 0;
                    // Se normaliza el estado a booleano real para el JS
                    $c['ind_estado_caja_m'] = $activa;
                    $json_caja = htmlspecialchars(json_encode($c), ENT_QUOTES, 'UTF-8');
                ?>
                <tr data-estado="<?= $filtro ?>" onclick="openDetailModal(<?= $json_caja ?>)">
                    <td data-sort="<?= htmlspecialchars($c['nom_caja_menor']) ?>">
                        <strong><?= htmlspecialchars($c['nom_caja_menor']) ?></strong><br>
                        <small style="color:#94a3b8;font-size:11px">#<?= $id_caja_esc ?> — <?= $pct_disp ?>% disponible</small>
                    </td>
                    <td data-sort="<?= htmlspecialchars(date('Y-m-d', strtotime($c['fecha_apertura']))) ?>"><?= htmlspecialchars(date('d/m/Y', strtotime($c['fecha_apertura']))) ?></td>
                    <td class="text-right" data-sort="<?= (float)$c['monto_asignado'] ?>">$<?= number_format((float)$c['monto_asignado'], 0, ',', '.') ?></td>
                    <td class="text-right" data-sort="<?= (float)$c['monto_disponible'] ?>">$<?= number_format((float)$c['monto_disponible'], 0, ',', '.') ?></td>
                    <td class="text-center"><?= $badge ?></td>
                    <td class="text-center" onclick="event.stopPropagation()">
                        <button class="btn-icon-sm edit" onclick="openEditModal(<?= $json_caja ?>)" title="Editar nombre">
                            <i class="fas fa-edit"></i>
                        </button>
                        <?php if ($activa): ?>
                        <button class="btn-icon-sm close" onclick="cerrarCajaMenor(<?= $json_caja ?>)" title="Cerrar caja">
                            <i class="fas fa-lock"></i>
                        </button>
                        <?php endif; ?>
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
                <span class="pagination-range" id="cajas-range">0 de 0</span>
                <button type="button" id="cajas-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="cajas-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: NUEVA CAJA -->
<div id="modal-new-caja" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header green">
            <div>
                <h2>Nueva Caja Menor</h2>
                <p>Registre un nuevo fondo fijo</p>
            </div>
            <button class="modal-close btn-close-new-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-caja-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <div class="form-field">
                    <label class="form-label">Nombre de la Caja <span class="required">*</span></label>
                    <input type="text" id="new-nom-caja" name="txt_nom_caja_menor" class="form-input" placeholder="Ej: Caja Menor Bodega" minlength="3" maxlength="50">
                    <span class="field-error" id="err-new-nombre"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Monto Asignado <span class="required">*</span></label>
                    <input type="number" id="new-monto-asignado" name="txt_monto_asignado" class="form-input" placeholder="Ej: 500000" min="0" max="99999999" step="1">
                    <span class="field-error" id="err-new-monto"></span>
                    <p class="field-hint">El monto disponible inicial será igual al monto asignado.</p>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar Caja</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR NOMBRE DE CAJA -->
<div id="modal-edit-caja" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header blue">
            <div>
                <h2>Editar Caja Menor</h2>
                <p>Solo se puede modificar el nombre</p>
            </div>
            <button class="modal-close btn-close-edit-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-caja-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id" id="edit-caja-id" value="">
                <div class="form-field">
                    <label class="form-label">Nombre de la Caja <span class="required">*</span></label>
                    <input type="text" id="edit-nom-caja" name="txt_edit_nom_caja_menor" class="form-input" minlength="3" maxlength="50">
                    <span class="field-error" id="err-edit-nombre"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Monto Asignado</label>
                    <input type="text" id="edit-monto-display" class="form-input" disabled>
                    <p class="field-hint">El monto asignado no se puede modificar después de creada la caja.</p>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-edit-modal">Cancelar</button>
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Actualizar Nombre</button>
        </div>
    </div>
</div>

<!-- MODAL: DETALLE DE CAJA (movimientos) -->
<div id="modal-detail" class="modal-overlay hidden">
    <div class="modal-box" style="max-width:620px">
        <div class="modal-header blue">
            <div><h2 id="detail-title">Detalle de Caja</h2><p id="detail-subtitle"></p></div>
            <button class="modal-close" id="close-detail-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <div id="detail-content"></div>

            <!-- Aviso: se muestra solo cuando la caja está cerrada -->
            <div id="mov-caja-cerrada-aviso" class="caja-cerrada-aviso hidden">
                <i class="fas fa-lock"></i>
                <span>Esta caja está cerrada. No se pueden registrar ni modificar movimientos; solo consultarlos.</span>
            </div>

            <!-- Formulario de nuevo movimiento: solo para cajas activas -->
            <div id="mov-form-section">
                <h4 class="detail-subheading"><i class="fas fa-plus-circle"></i> Nuevo Movimiento</h4>
                <form id="new-mov-form" novalidate>
                    <input type="hidden" name="btn_nuevo_movimiento" value="1">
                    <input type="hidden" name="hid_mov_id_caja" id="mov-id-caja" value="">
                    <div class="form-grid">
                        <div class="form-field">
                            <label class="form-label">Concepto <span class="required">*</span></label>
                            <input type="text" id="mov-concepto" name="txt_concepto" class="form-input" placeholder="Ej: Papelería oficina" maxlength="200">
                            <span class="field-error" id="err-mov-concepto"></span>
                        </div>
                        <div class="form-field">
                            <label class="form-label">Valor <span class="required">*</span></label>
                            <input type="number" id="mov-valor" name="txt_val_movimiento" class="form-input" placeholder="Ej: 25000" min="1" max="99999999" step="1">
                            <span class="field-error" id="err-mov-valor"></span>
                        </div>
                    </div>
                    <div class="form-field">
                        <label class="form-label">Fecha del Movimiento <span class="required">*</span></label>
                        <input type="date" id="mov-fecha" name="txt_fecha_movimiento" class="form-input" min="<?= date('Y-m-d') ?>">
                        <span class="field-error" id="err-mov-fecha"></span>
                    </div>
                    <div class="config-actions">
                        <button type="button" id="mov-btn-save" class="btn btn-primary"><i class="fas fa-plus"></i> Registrar Movimiento</button>
                    </div>
                </form>
            </div>

            <h4 class="detail-subheading"><i class="fas fa-list"></i> Movimientos</h4>
            <div id="movimientos-list">
                <div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>Cargando...</p></div>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-danger hidden" id="detail-btn-cerrar-caja"><i class="fas fa-lock"></i> Cerrar Caja</button>
            <button class="btn btn-secondary" id="close-detail-btn">Cerrar</button>
        </div>
    </div>
</div>

<!-- MODAL: CONFIRMAR ACCIÓN (estilo módulo Compras) -->
<div id="modal-confirm-accion" class="modal-overlay hidden">
    <div class="modal-box confirm-box">
        <div class="confirm-icon"><i class="fas fa-exclamation-triangle"></i></div>
        <h4 id="confirm-accion-title"></h4>
        <p id="confirm-accion-body"></p>
        <div class="confirm-buttons">
            <button type="button" class="btn-cancelar" id="confirm-accion-cancel-btn">Cancelar</button>
            <button type="button" class="btn-confirmar-accion" id="confirm-accion-ok-btn">Confirmar</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>

<!-- SCRIPTS JS -->
<script src="modules/tescxp/js/caja_menor.js"></script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
