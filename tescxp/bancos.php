<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp'; // Ajustar si "Bancos" vive bajo otro módulo del menú
$page_title       = "ADSOERP | Bancos";
$page_description = "Catálogo de bancos disponibles en el sistema";
$page_icon        = "bi-bank2";
$page_extra_css   = ['modules/tescxp/css/tcx_pantalla.css', 'modules/tescxp/css/tcx_modales.css', 'modules/tescxp/css/bancos.css'];
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

// Uso de cada banco: cuántas cuentas (de la empresa y de proveedores) lo usan.
// Columna "Cuentas" de la tabla maestra (GUIA_PANTALLAS_ERP §10, modelo: Cargos).
$uso_bancos = [];
$list_ctas_empresa->execute();
foreach ($list_ctas_empresa->fetchAll(PDO::FETCH_ASSOC) as $c) {
    $uso_bancos[$c['id_banco']] = ($uso_bancos[$c['id_banco']] ?? 0) + 1;
}
$list_bancoxprov->execute();
foreach ($list_bancoxprov->fetchAll(PDO::FETCH_ASSOC) as $c) {
    $uso_bancos[$c['id_banco']] = ($uso_bancos[$c['id_banco']] ?? 0) + 1;
}
foreach ($bancos as &$b_uso) {
    $b_uso['num_cuentas'] = (int)($uso_bancos[$b_uso['id_banco']] ?? 0);
}
unset($b_uso);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>
<div id="mod-bancos" class="app-view active tcx-pantalla" data-lista-fija>

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Bancos</h1>
            <p>Catálogo de bancos disponibles en el sistema</p>
        </div>
        <div class="module-header-acciones">
            <button type="button" id="btn-add-banco" class="btn btn-primary"><i class="fas fa-plus"></i> Nuevo banco</button>
        </div>
    </div>

    <!-- Indicadores: los calcula bancos.js sobre todos los bancos -->
    <div class="stats-grid">
        <div class="stat-card" style="--i:0">
            <div class="stat-icon blue"><i class="fas fa-university"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total bancos</div>
                <div class="stat-value" id="stat-total">0</div>
                <div class="stat-hint">En el catálogo</div>
            </div>
        </div>
        <div class="stat-card" style="--i:1">
            <div class="stat-icon green"><i class="fas fa-check-circle"></i></div>
            <div class="stat-info">
                <div class="stat-label">Activos</div>
                <div class="stat-value" id="stat-activos">0</div>
                <div class="stat-hint">Se pueden usar en cuentas</div>
            </div>
        </div>
        <div class="stat-card" style="--i:2">
            <div class="stat-icon rose"><i class="fas fa-ban"></i></div>
            <div class="stat-info">
                <div class="stat-label">Inactivos</div>
                <div class="stat-value" id="stat-inactivos">0</div>
                <div class="stat-hint">No aparecen en las listas</div>
            </div>
        </div>
        <div class="stat-card" style="--i:3">
            <div class="stat-icon amber"><i class="fas fa-link"></i></div>
            <div class="stat-info">
                <div class="stat-label">Con cuentas</div>
                <div class="stat-value" id="stat-uso">0</div>
                <div class="stat-hint" id="stat-uso-hint">De la empresa o de proveedores</div>
            </div>
        </div>
    </div>

    <!-- Filtros (componente "filtros": píldoras con conteo) -->
    <div class="filter-bar">
        <div class="filter-row">
            <div class="search-wrapper">
                <span class="search-icon"><i class="fas fa-search"></i></span>
                <input type="search" id="banco-search" class="search-input" maxlength="60" autocomplete="off" placeholder="Buscar por código o nombre...">
            </div>
            <div class="filter-toggle-group" role="group" aria-label="Estado" data-para="banco-filtro-estado">
                <button type="button" class="filter-toggle active" data-valor="all" aria-pressed="true">Todos <span class="count" id="ban-cnt-all"></span></button>
                <button type="button" class="filter-toggle" data-valor="activo" aria-pressed="false">Activos <span class="count" id="ban-cnt-activo"></span></button>
                <button type="button" class="filter-toggle" data-valor="inactivo" aria-pressed="false">Inactivos <span class="count" id="ban-cnt-inactivo"></span></button>
            </div>
            <input type="hidden" id="banco-filtro-estado" value="all">
            <button type="button" id="btn-clear-filters" class="btn-clear-filter" hidden><i class="fas fa-eraser"></i> Limpiar</button>
        </div>
        <div class="filter-info" id="bancos-count" aria-live="polite">0 resultados</div>
    </div>

    <!-- Lista: la pinta bancos.js; el paginador agrega su pie -->
    <div class="table-container" data-lista>
        <div data-lista-scroll>
            <table id="bancos-table" class="data-table" data-erp-movil data-erp-movil-titulo="2">
                <thead>
                    <tr>
                        <th>Código</th>
                        <th>Nombre del banco</th>
                        <th class="text-center">Cuentas</th>
                        <th>Estado</th>
                        <th class="col-acciones">Acciones</th>
                    </tr>
                </thead>
                <tbody id="bancos-tbody"></tbody>
            </table>
        </div>
    </div>
</div>

<!-- MODAL: NUEVO BANCO -->
<div id="modal-new-banco" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div>
                <h3>Nuevo banco</h3>
                <p>Registre un banco en el catálogo del sistema</p>
            </div>
            <button type="button" class="modal-close btn-close-new-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-banco-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <div class="form-field">
                    <label class="form-label">Código del banco <span class="required">*</span></label>
                    <input type="text" id="new-id-banco" name="txt_id_banco" class="form-input" placeholder="Ej: 0001234" minlength="6" maxlength="10">
                    <span class="field-error" id="err-new-id"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Nombre del banco <span class="required">*</span></label>
                    <input type="text" id="new-nom-banco" name="txt_nom_banco" class="form-input" placeholder="Ej: Bancolombia" minlength="4" maxlength="50">
                    <span class="field-error" id="err-new-nombre"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Estado</label>
                    <select id="new-estado" name="sel_estado" class="form-input">
                        <option value="true">Activo</option>
                        <option value="false">Inactivo</option>
                    </select>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-new-modal">Cancelar</button>
            <button type="button" id="new-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR BANCO -->
<div id="modal-edit-banco" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div>
                <h3>Editar banco</h3>
                <p>Modifique el nombre o el estado del banco</p>
            </div>
            <button type="button" class="modal-close btn-close-edit-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-banco-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id_banco" id="edit-id-banco-hid" value="">
                <div class="form-field">
                    <label class="form-label">Código del banco</label>
                    <input type="text" id="edit-id-banco-display" class="form-input" disabled>
                </div>
                <div class="form-field">
                    <label class="form-label">Nombre del banco <span class="required">*</span></label>
                    <input type="text" id="edit-nom-banco" name="txt_edit_nom_banco" class="form-input" minlength="4" maxlength="50">
                    <span class="field-error" id="err-edit-nombre"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Estado</label>
                    <select id="edit-estado" name="sel_edit_estado" class="form-input">
                        <option value="true">Activo</option>
                        <option value="false">Inactivo</option>
                    </select>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-edit-modal">Cancelar</button>
            <button type="button" id="edit-btn-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar</button>
        </div>
    </div>
</div>

<!-- MODAL: CONFIRMAR ELIMINACIÓN (después de los formularios: queda encima) -->
<div id="modal-confirm-eliminar" class="modal-overlay hidden">
    <div class="modal-box confirm-box">
        <div class="confirm-icon"><i class="fas fa-exclamation-triangle"></i></div>
        <h4 id="confirm-eliminar-title"></h4>
        <p id="confirm-eliminar-body"></p>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary" id="confirm-eliminar-cancel-btn">Cancelar</button>
            <button type="button" class="btn btn-danger" id="confirm-eliminar-ok-btn">Eliminar</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div id="toast" class="tcx-toast hidden" role="status" aria-live="polite"><span id="toast-message"></span></div>

<!-- DATOS PARA EL JS -->
<script>
const bancosData = <?= json_encode(array_values($bancos), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP) ?>;
</script>

<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
