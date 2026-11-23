<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp'; // Ajustar si "Bancos" vive bajo otro módulo del menú
$page_title       = "ADSOERP | Bancos";
$page_description = "Catálogo de bancos disponibles en el sistema";
$page_icon        = "bi-bank2";
$page_extra_css   = ['modules/tescxp/css/cmp_pantalla.css', 'modules/tescxp/css/bancos.css', 'modules/bancos/css/cmp_modales.css'];
$page_extra_js    = ['modules/tescxp/js/bancos.js'];
$page_erp_ui      = ['modales', 'indicadores', 'filtros', 'paginador', 'lista_fija', 'movil', 'botones', 'orden'];   // GUIA_PANTALLAS_ERP §2
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    erp_validar_csrf();   // SEC-08: token de la sesión + origen
    header('Content-Type: application/json');
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- NUEVO BANCO ----------
        if (isset($_POST['btn_nuevo'])) {
            $id_banco   = trim($_POST['txt_id_banco']  ?? '');
            $nom_banco  = trim($_POST['txt_nom_banco'] ?? '');
            $ind_estado = ($_POST['sel_estado'] ?? 'true') === 'true';

            $errores = [];

            if (strlen($id_banco) < 6 || strlen($id_banco) > 10) {
                $errores['err-new-id'] = 'El código debe tener entre 6 y 10 caracteres.';
            }
            if (strlen($nom_banco) < 4 || strlen($nom_banco) > 50) {
                $errores['err-new-nombre'] = 'El nombre debe tener entre 4 y 50 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $ins_banco->execute([
                ':wid_banco'   => $id_banco,
                ':wnom_banco'  => $nom_banco,
                ':wind_estado' => $ind_estado ? 'true' : 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Banco registrado correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- EDITAR BANCO ----------
        if (isset($_POST['btn_editar'])) {
            $id_banco   = trim($_POST['hid_edit_id_banco']  ?? '');
            $nom_banco  = trim($_POST['txt_edit_nom_banco'] ?? '');
            $ind_estado = ($_POST['sel_edit_estado'] ?? 'true') === 'true';

            $errores = [];

            if (empty($id_banco)) {
                $errores['err-edit-nombre'] = 'Banco no válido.';
            }
            if (strlen($nom_banco) < 4 || strlen($nom_banco) > 50) {
                $errores['err-edit-nombre'] = 'El nombre debe tener entre 4 y 50 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $upd_banco->execute([
                ':wid_banco'   => $id_banco,
                ':wnom_banco'  => $nom_banco,
                ':wind_estado' => $ind_estado ? 'true' : 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Banco actualizado correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- ACTIVAR / DESACTIVAR RÁPIDO ----------
        if (isset($_POST['btn_toggle_estado'])) {
            $id_banco   = trim($_POST['hid_toggle_id_banco'] ?? '');
            $ind_estado = ($_POST['hid_toggle_estado'] ?? 'true') === 'true';

            if (empty($id_banco)) {
                throw new Exception('Banco no válido.');
            }

            // fun_update_bancos exige también el nombre, así que se recupera
            // el nombre actual antes de togglear el estado (no existe una
            // función SQL dedicada solo a cambiar el estado).
            $get_banco->execute([':wid_banco' => $id_banco]);
            $banco_actual = $get_banco->fetch(PDO::FETCH_ASSOC);

            if (!$banco_actual) {
                throw new Exception('El banco no existe o se encuentra borrado.');
            }

            $upd_banco->execute([
                ':wid_banco'   => $id_banco,
                ':wnom_banco'  => $banco_actual['nom_banco'],
                ':wind_estado' => $ind_estado ? 'true' : 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = $ind_estado ? 'Banco activado correctamente.' : 'Banco desactivado correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- ELIMINAR BANCO (borrado lógico) ----------
        if (isset($_POST['btn_eliminar'])) {
            $id_banco = trim($_POST['hid_del_id_banco'] ?? '');

            if (empty($id_banco)) {
                throw new Exception('Banco no válido.');
            }

            $del_banco->execute([
                ':wid_banco' => $id_banco,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Banco eliminado correctamente.';
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
        // Llave primaria duplicada -> código de banco repetido
        if (stripos($mensaje, 'duplicate key') !== false || stripos($mensaje, 'llave duplicada') !== false) {
            $mensaje = 'Ya existe un banco registrado con ese código.';
        }
        $respuesta['message'] = $mensaje;
        echo json_encode($respuesta);
        exit;
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
$list_bancos_full->execute();
$bancos = $list_bancos_full->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<div id="mod-bancos" class="app-view active">

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Bancos</h1>
            <p>Catálogo de bancos disponibles en el sistema</p>
        </div>
        <button id="btn-add-banco" class="btn btn-primary">
            <i class="fas fa-plus"></i> Nuevo Banco
        </button>
    </div>

    <!-- STATS -->
    <div class="stats-grid">
        <?php
        $total     = count($bancos);
        $activos   = count(array_filter($bancos, fn($b) => $b['ind_estado'] === 't' || $b['ind_estado'] === true));
        $inactivos = $total - $activos;
        ?>
        <div class="stat-card">
            <div class="stat-icon blue"><i class="fas fa-university"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total bancos</div>
                <div class="stat-value" id="stat-total"><?= $total ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon green"><i class="fas fa-check-circle"></i></div>
            <div class="stat-info">
                <div class="stat-label">Activos</div>
                <div class="stat-value" id="stat-activos"><?= $activos ?></div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-icon yellow"><i class="fas fa-ban"></i></div>
            <div class="stat-info">
                <div class="stat-label">Inactivos</div>
                <div class="stat-value" id="stat-inactivos"><?= $inactivos ?></div>
            </div>
        </div>
    </div>

    <!-- FILTROS -->
    <div class="filter-bar">
        <div class="search-wrapper">
            <span class="search-icon"><i class="fas fa-search"></i></span>
            <input type="text" id="banco-search" class="search-input" placeholder="Buscar por código o nombre...">
        </div>
        <div class="filter-toggle-group">
            <button class="filter-toggle active" data-filter="all">Todos</button>
            <button class="filter-toggle" data-filter="activo">Activos</button>
            <button class="filter-toggle" data-filter="inactivo">Inactivos</button>
        </div>
        <button id="btn-clear-filters" class="btn-clear-filter" style="display:none">
            <i class="fas fa-times"></i> Limpiar
        </button>
        <div class="pagination-size">
            <label for="bancos-page-size">Filas por página</label>
            <select id="bancos-page-size">
                <option value="10">10</option>
                <option value="25" selected>25</option>
                <option value="50">50</option>
                <option value="all">Todos</option>
            </select>
        </div>
        <span class="filter-info" id="bancos-count"><?= $total ?> resultado<?= $total !== 1 ? 's' : '' ?></span>
    </div>

    <!-- TABLA -->
    <div class="table-container">
      <div class="table-scroll" id="bancos-table-scroll">
        <table class="data-table">
            <!-- Anchos fijos: las columnas no se mueven al ordenar o cambiar de página -->
            <colgroup>
                <col class="col-codigo">
                <col class="col-nombre">
                <col class="col-estado">
                <col class="col-acciones">
            </colgroup>
            <thead>
                <tr>
                    <th class="sortable" data-sort-key="0" data-sort-type="text">Código <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="sortable" data-sort-key="1" data-sort-type="text">Nombre del Banco <i class="fas fa-caret-down sort-icon"></i></th>
                    <th class="text-center">Estado</th>
                    <th class="text-center">Acciones</th>
                </tr>
            </thead>
            <tbody id="bancos-tbody">
            <?php if (empty($bancos)): ?>
                <tr class="empty-row">
                    <td colspan="4">
                        <div class="empty-state">
                            <i class="fas fa-university"></i>
                            <p>No hay bancos registrados</p>
                            <span>Haga clic en "Nuevo Banco" para agregar el primero</span>
                        </div>
                    </td>
                </tr>
            <?php else: ?>
                <?php foreach ($bancos as $b):
                    $es_activo  = ($b['ind_estado'] === 't' || $b['ind_estado'] === true);
                    $badge_tipo = $es_activo
                        ? '<span class="badge badge-active">Activo</span>'
                        : '<span class="badge badge-inactive">Inactivo</span>';
                    $id_esc  = htmlspecialchars($b['id_banco']);
                    $nom_esc = htmlspecialchars($b['nom_banco']);
                    $filtro  = $es_activo ? 'activo' : 'inactivo';
                ?>
                <tr data-tipo="<?= $filtro ?>">
                    <td data-sort="<?= $id_esc ?>"><strong><?= $id_esc ?></strong></td>
                    <td data-sort="<?= $nom_esc ?>"><?= $nom_esc ?></td>
                    <td class="text-center"><?= $badge_tipo ?></td>
                    <td class="text-center">
                        <button class="btn-icon-sm toggle" title="<?= $es_activo ? 'Desactivar' : 'Activar' ?>"
                                onclick="toggleEstadoBanco('<?= $id_esc ?>', <?= $es_activo ? 'false' : 'true' ?>)">
                            <i class="fas fa-power-off"></i>
                        </button>
                        <button class="btn-icon-sm edit" onclick='openEditModal(<?= json_encode($b) ?>)'>
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn-icon-sm reject" onclick="eliminarBanco('<?= $id_esc ?>', '<?= htmlspecialchars($b['nom_banco'], ENT_QUOTES) ?>')">
                            <i class="fas fa-trash"></i>
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
                <span class="pagination-range" id="bancos-range">0 de 0</span>
                <button type="button" id="bancos-prev" class="pagination-btn" disabled aria-label="Página anterior">
                    <i class="fas fa-chevron-left"></i>
                </button>
                <button type="button" id="bancos-next" class="pagination-btn" disabled aria-label="Página siguiente">
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- MODAL: NUEVO BANCO -->
<div id="modal-new-banco" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header green">
            <div>
                <h2>Nuevo Banco</h2>
                <p>Registre un banco en el catálogo del sistema</p>
            </div>
            <button class="modal-close btn-close-new-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-banco-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <div class="form-field">
                    <label class="form-label">Código del Banco <span class="required">*</span></label>
                    <input type="text" id="new-id-banco" name="txt_id_banco" class="form-input" placeholder="Ej: 0001234" minlength="6" maxlength="10">
                    <span class="field-error" id="err-new-id"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Nombre del Banco <span class="required">*</span></label>
                    <input type="text" id="new-nom-banco" name="txt_nom_banco" class="form-input" placeholder="Ej: Bancolombia" minlength="4" maxlength="50">
                    <span class="field-error" id="err-new-nombre"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Estado</label>
                    <select id="new-estado" name="sel_estado" class="form-select">
                        <option value="true">Activo</option>
                        <option value="false">Inactivo</option>
                    </select>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar Banco</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR BANCO -->
<div id="modal-edit-banco" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header blue">
            <div>
                <h2>Editar Banco</h2>
                <p>Modifique el nombre o el estado del banco</p>
            </div>
            <button class="modal-close btn-close-edit-modal"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-banco-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id_banco" id="edit-id-banco-hid" value="">
                <div class="form-field">
                    <label class="form-label">Código del Banco</label>
                    <input type="text" id="edit-id-banco-display" class="form-input" disabled>
                </div>
                <div class="form-field">
                    <label class="form-label">Nombre del Banco <span class="required">*</span></label>
                    <input type="text" id="edit-nom-banco" name="txt_edit_nom_banco" class="form-input" minlength="4" maxlength="50">
                    <span class="field-error" id="err-edit-nombre"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Estado</label>
                    <select id="edit-estado" name="sel_edit_estado" class="form-select">
                        <option value="true">Activo</option>
                        <option value="false">Inactivo</option>
                    </select>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-edit-modal">Cancelar</button>
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Actualizar Banco</button>
        </div>
    </div>
</div>

<!-- MODAL: CONFIRMAR ELIMINACIÓN (estilo módulo Compras) -->
<div id="modal-confirm-eliminar" class="modal-overlay hidden">
    <div class="modal-box confirm-box">
        <div class="confirm-icon"><i class="fas fa-exclamation-triangle"></i></div>
        <h4 id="confirm-eliminar-title"></h4>
        <p id="confirm-eliminar-body"></p>
        <div class="confirm-buttons">
            <button type="button" class="btn-cancelar" id="confirm-eliminar-cancel-btn">Cancelar</button>
            <button type="button" class="btn-eliminar" id="confirm-eliminar-ok-btn">Sí, eliminar</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="hidden"><span id="toast-message"></span></div>



<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
