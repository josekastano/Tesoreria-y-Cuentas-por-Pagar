<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Caja Menor";
$page_description = "Gestión de fondos fijos y sus movimientos";
$page_icon        = "bi-cash-coin";
$page_extra_css   = ['modules/tescxp/css/tcx_pantalla.css', 'modules/tescxp/css/tcx_modales.css', 'modules/tescxp/css/caja_menor.css'];
$page_extra_js    = ['modules/tescxp/js/caja_menor.js'];
$page_erp_ui      = ['modales', 'indicadores', 'filtros', 'paginador', 'lista_fija', 'movil', 'botones', 'orden'];   // GUIA_PANTALLAS_ERP §2
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');


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
    erp_validar_csrf();   // SEC-08: token de la sesión + origen
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
<div id="mod-caja-menor" class="app-view active tcx-pantalla" data-lista-fija>

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Caja menor</h1>
            <p>Fondos fijos asignados y seguimiento de sus movimientos. Haga clic en una caja para ver sus movimientos.</p>
        </div>
        <div class="module-header-acciones">
            <button type="button" id="btn-add-caja" class="btn btn-primary"><i class="fas fa-plus"></i> Nueva caja</button>
        </div>
    </div>

    <!-- Indicadores: los calcula caja_menor.js sobre todas las cajas -->
    <div class="stats-grid">
        <div class="stat-card" style="--i:0">
            <div class="stat-icon blue"><i class="fas fa-cash-register"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total cajas</div>
                <div class="stat-value" id="stat-total">0</div>
                <div class="stat-hint">Abiertas y cerradas</div>
            </div>
        </div>
        <div class="stat-card" style="--i:1">
            <div class="stat-icon green"><i class="fas fa-check-circle"></i></div>
            <div class="stat-info">
                <div class="stat-label">Activas</div>
                <div class="stat-value" id="stat-activas">0</div>
                <div class="stat-hint">Admiten movimientos</div>
            </div>
        </div>
        <div class="stat-card" style="--i:2">
            <div class="stat-icon amber"><i class="fas fa-coins"></i></div>
            <div class="stat-info">
                <div class="stat-label">Disponible total</div>
                <div class="stat-value" id="stat-disponible">$0</div>
                <div class="stat-hint" id="stat-disponible-hint">De las cajas activas</div>
            </div>
        </div>
        <div class="stat-card" style="--i:3">
            <div class="stat-icon rose"><i class="fas fa-wallet"></i></div>
            <div class="stat-info">
                <div class="stat-label">Asignado total</div>
                <div class="stat-value" id="stat-asignado">$0</div>
                <div class="stat-hint">De las cajas activas</div>
            </div>
        </div>
    </div>

    <!-- Filtros (componente "filtros": píldoras con conteo) -->
    <div class="filter-bar">
        <div class="filter-row">
            <div class="search-wrapper">
                <span class="search-icon"><i class="fas fa-search"></i></span>
                <input type="search" id="caja-search" class="search-input" maxlength="60" autocomplete="off" placeholder="Buscar por nombre o número de caja...">
            </div>
            <div class="filter-toggle-group" role="group" aria-label="Estado" data-para="caja-filtro-estado">
                <button type="button" class="filter-toggle active" data-valor="all" aria-pressed="true">Todas <span class="count" id="caja-cnt-all"></span></button>
                <button type="button" class="filter-toggle" data-valor="activa" aria-pressed="false">Activas <span class="count" id="caja-cnt-activa"></span></button>
                <button type="button" class="filter-toggle" data-valor="cerrada" aria-pressed="false">Cerradas <span class="count" id="caja-cnt-cerrada"></span></button>
            </div>
            <input type="hidden" id="caja-filtro-estado" value="all">
            <button type="button" id="btn-clear-filters" class="btn-clear-filter" hidden><i class="fas fa-eraser"></i> Limpiar</button>
        </div>
        <div class="filter-info" id="cajas-count" aria-live="polite">0 resultados</div>
    </div>

    <!-- Lista: la pinta caja_menor.js; clic en la fila abre los movimientos; el paginador agrega su pie -->
    <div class="table-container" data-lista>
        <div data-lista-scroll>
            <table id="cajas-table" class="data-table" data-erp-movil data-erp-movil-titulo="1">
                <thead>
                    <tr>
                        <th>Caja</th>
                        <th>Apertura</th>
                        <th class="text-right">Asignado</th>
                        <th class="text-right">Disponible</th>
                        <th>Estado</th>
                        <th class="col-acciones">Acciones</th>
                    </tr>
                </thead>
                <tbody id="cajas-tbody"></tbody>
            </table>
        </div>
    </div>
</div>

<!-- MODAL: NUEVA CAJA -->
<div id="modal-new-caja" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div>
                <h3>Nueva Caja Menor</h3>
                <p>Registre un nuevo fondo fijo</p>
            </div>
            <button type="button" class="modal-close btn-close-new-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
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
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR NOMBRE DE CAJA -->
<div id="modal-edit-caja" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div>
                <h3>Editar Caja Menor</h3>
                <p>Solo se puede modificar el nombre</p>
            </div>
            <button type="button" class="modal-close btn-close-edit-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
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
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar</button>
        </div>
    </div>
</div>

<!-- MODAL: DETALLE DE CAJA (movimientos) -->
<div id="modal-detail" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div><h3 id="detail-title">Detalle de caja</h3><p id="detail-subtitle">Saldo y movimientos de la caja</p></div>
            <button type="button" class="modal-close" id="close-detail-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
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
            <button type="button" class="btn btn-danger hidden" id="detail-btn-cerrar-caja"><i class="fas fa-lock"></i> Cerrar Caja</button>
            <button type="button" class="btn btn-secondary" id="close-detail-btn">Cerrar</button>
        </div>
    </div>
</div>

<!-- MODAL: CONFIRMAR ACCIÓN (después del detalle: queda encima) -->
<div id="modal-confirm-accion" class="modal-overlay hidden">
    <div class="modal-box confirm-box">
        <div class="confirm-icon"><i class="fas fa-exclamation-triangle"></i></div>
        <h4 id="confirm-accion-title"></h4>
        <p id="confirm-accion-body"></p>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary" id="confirm-accion-cancel-btn">Cancelar</button>
            <button type="button" class="btn btn-primary" id="confirm-accion-ok-btn">Confirmar</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="tcx-toast hidden" role="status" aria-live="polite"><span id="toast-message"></span></div>

<!-- DATOS PARA EL JS (el estado se normaliza a booleano) -->
<script>
const cajasData = <?= json_encode(array_map(function ($c) {
    $c['ind_estado_caja_m'] = es_caja_activa($c['ind_estado_caja_m']);
    return $c;
}, $cajas), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP) ?>;
</script>



<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
