<?php
// ========== PERSONALIZAR PÁGINA ==========
$pageTitle        = 'ERP ADSO — Tesorería';
$activeModule     = 'tescxp';
$page_title       = "ADSOERP | Cuentas de la Empresa";
$page_description = "Gestión de cuentas bancarias propias para pagos a proveedores";
$page_icon        = "bi-bank";
$page_extra_css   = ['modules/tescxp/css/tcx_pantalla.css', 'modules/tescxp/css/tcx_modales.css', 'modules/tescxp/css/ctas_empresa.css'];
$page_extra_js    = ['modules/tescxp/js/ctas_empresa.js'];
$page_erp_ui      = ['modales', 'indicadores', 'filtros', 'paginador', 'lista_fija', 'movil', 'botones', 'orden'];   // GUIA_PANTALLAS_ERP §2
$show_welcome     = false;
// ==========================================

if (!defined('INCLUDE_MENU_PRINCIPAL')) {
    header("Location: menu_principal.php");
    exit();
}

require_once('prepare_tescxp.php');

// ============================================================
// NIT DE LA EMPRESA (fijo, viene de Parámetros Generales)
// ============================================================
$list_pmtros_grales->execute();
$pmtros_grales   = $list_pmtros_grales->fetch(PDO::FETCH_ASSOC);
$id_empresa_fijo = $pmtros_grales['id_empresa'] ?? '';


// ============================================================
// CARGAR SELECTS (siempre se cargan para la vista inicial)
// ============================================================
$list_bancos->execute();
$bancos = $list_bancos->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// MANEJO DE PETICIONES POST (SIEMPRE RESPONDEN CON JSON)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    erp_validar_csrf();   // SEC-08: token de la sesión + origen
    header('Content-Type: application/json');
    $respuesta = ['success' => false, 'message' => '', 'errors' => []];

    try {
        // ---------- NUEVO BANCO RÁPIDO (modal dentro de "Nueva Cuenta") ----------
        // Crea el banco sin recargar la página y devuelve sus datos para que
        // el JS lo agregue al select y lo deje seleccionado.
        if (isset($_POST['btn_nuevo_banco'])) {
            $id_banco  = trim($_POST['txt_banco_id']     ?? '');
            $nom_banco = trim($_POST['txt_banco_nombre'] ?? '');

            $errores = [];

            if (mb_strlen($id_banco) < 6 || mb_strlen($id_banco) > 10) {
                $errores['err-banco-id'] = 'El código debe tener entre 6 y 10 caracteres.';
            }
            if (mb_strlen($nom_banco) < 4 || mb_strlen($nom_banco) > 50) {
                $errores['err-banco-nombre'] = 'El nombre debe tener entre 4 y 50 caracteres.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            // Se crea siempre ACTIVO: un banco inactivo no serviría para la cuenta.
            $ins_banco->execute([
                ':wid_banco'   => $id_banco,
                ':wnom_banco'  => $nom_banco,
                ':wind_estado' => 'true',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Banco registrado correctamente.';
            $respuesta['banco']   = ['id_banco' => $id_banco, 'nom_banco' => $nom_banco];
            echo json_encode($respuesta);
            exit;
        }

        // ---------- NUEVA CUENTA ----------
        if (isset($_POST['btn_nuevo'])) {
            $cta_empresa    = trim($_POST['txt_cta_empresa']     ?? '');
            $id_banco       = trim($_POST['sel_id_banco']        ?? '');
            $ind_tipocuenta = ($_POST['sel_tipocuenta']          ?? 'false') === 'true';

            $errores = [];

            if (empty($id_empresa_fijo)) {
                $errores['err-new-id-empresa'] = 'No se encontró el NIT de la empresa en Parámetros Generales. Configure primero ese módulo.';
            }
            if (!preg_match('/^[0-9]{10,16}$/', $cta_empresa)) {
                $errores['err-new-cta'] = 'El número de cuenta debe tener entre 10 y 16 dígitos numéricos.';
            }
            if (empty($id_banco)) {
                $errores['err-new-banco'] = 'Seleccione un banco.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $ins_cta_empresa->execute([
                ':wid_empresa'     => $id_empresa_fijo,
                ':wcta_empresa'    => $cta_empresa,
                ':wid_banco'       => $id_banco,
                ':wind_tipocuenta' => $ind_tipocuenta ? 'true' : 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Cuenta bancaria registrada correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- EDITAR CUENTA ----------
        if (isset($_POST['btn_editar'])) {
            $id_empresa     = trim($_POST['hid_edit_id_empresa']  ?? '');
            $cta_empresa    = trim($_POST['hid_edit_cta_empresa'] ?? '');
            $id_banco       = trim($_POST['sel_edit_id_banco']    ?? '');
            $ind_tipocuenta = ($_POST['sel_edit_tipocuenta']      ?? 'false') === 'true';

            $errores = [];

            if (empty($id_empresa) || empty($cta_empresa)) {
                $errores['err-edit-banco'] = 'Cuenta no válida.';
            }
            if (empty($id_banco)) {
                $errores['err-edit-banco'] = 'Seleccione un banco.';
            }

            if (!empty($errores)) {
                $respuesta['errors'] = $errores;
                echo json_encode($respuesta);
                exit;
            }

            $upd_cta_empresa->execute([
                ':wid_empresa'     => $id_empresa,
                ':wcta_empresa'    => $cta_empresa,
                ':wid_banco'       => $id_banco,
                ':wind_tipocuenta' => $ind_tipocuenta ? 'true' : 'false',
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Cuenta bancaria actualizada correctamente.';
            echo json_encode($respuesta);
            exit;
        }

        // ---------- ELIMINAR CUENTA ----------
        if (isset($_POST['btn_eliminar'])) {
            $id_empresa  = trim($_POST['hid_del_id_empresa']  ?? '');
            $cta_empresa = trim($_POST['hid_del_cta_empresa'] ?? '');

            if (empty($id_empresa) || empty($cta_empresa)) {
                throw new Exception('Cuenta no válida.');
            }

            $del_cta_empresa->execute([
                ':wid_empresa'  => $id_empresa,
                ':wcta_empresa' => $cta_empresa,
            ]);

            $respuesta['success'] = true;
            $respuesta['message'] = 'Cuenta bancaria eliminada correctamente.';
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

        // Banco rápido con código repetido: se muestra debajo del campo Código
        if (isset($_POST['btn_nuevo_banco']) &&
            (stripos($mensaje, 'ya existe') !== false ||
             stripos($mensaje, 'duplicate key') !== false ||
             stripos($mensaje, 'llave duplicada') !== false)) {
            $respuesta['errors'] = ['err-banco-id' => 'Ya existe un banco registrado con ese código.'];
            echo json_encode($respuesta);
            exit;
        }

        $respuesta['message'] = $mensaje;
        echo json_encode($respuesta);
        exit;
    }
}

// ============================================================
// CARGAR TABLA (SOLO PARA LA VISTA INICIAL)
// ============================================================
$list_ctas_empresa->execute();
$ctas_empresa = $list_ctas_empresa->fetchAll(PDO::FETCH_ASSOC);

// ============================================================
// INICIO DEL HTML
// ============================================================
ob_start();
?>

<div id="mod-ctas-empresa" class="app-view active tcx-pantalla" data-lista-fija>

    <!-- ENCABEZADO -->
    <div class="module-header">
        <div class="module-header-text">
            <h1>Cuentas de la empresa</h1>
            <p>Cuentas bancarias propias utilizadas para el pago a proveedores</p>
        </div>
        <div class="module-header-acciones">
            <button type="button" id="btn-add-cuenta" class="btn btn-primary"><i class="fas fa-plus"></i> Nueva cuenta</button>
        </div>
    </div>

    <!-- Indicadores: los calcula ctas_empresa.js sobre todas las cuentas -->
    <div class="stats-grid">
        <div class="stat-card" style="--i:0">
            <div class="stat-icon blue"><i class="fas fa-university"></i></div>
            <div class="stat-info">
                <div class="stat-label">Total cuentas</div>
                <div class="stat-value" id="stat-total">0</div>
                <div class="stat-hint">Registradas</div>
            </div>
        </div>
        <div class="stat-card" style="--i:1">
            <div class="stat-icon green"><i class="fas fa-money-check-alt"></i></div>
            <div class="stat-info">
                <div class="stat-label">Corrientes</div>
                <div class="stat-value" id="stat-corrientes">0</div>
                <div class="stat-hint">Cuentas corrientes</div>
            </div>
        </div>
        <div class="stat-card" style="--i:2">
            <div class="stat-icon amber"><i class="fas fa-piggy-bank"></i></div>
            <div class="stat-info">
                <div class="stat-label">Ahorros</div>
                <div class="stat-value" id="stat-ahorros">0</div>
                <div class="stat-hint">Cuentas de ahorros</div>
            </div>
        </div>
        <div class="stat-card" style="--i:3">
            <div class="stat-icon rose"><i class="fas fa-landmark"></i></div>
            <div class="stat-info">
                <div class="stat-label">Bancos distintos</div>
                <div class="stat-value" id="stat-bancos">0</div>
                <div class="stat-hint">Donde la empresa tiene cuentas</div>
            </div>
        </div>
    </div>

    <!-- Filtros (componente "filtros": píldoras con conteo) -->
    <div class="filter-bar">
        <div class="filter-row">
            <div class="search-wrapper">
                <span class="search-icon"><i class="fas fa-search"></i></span>
                <input type="search" id="cuenta-search" class="search-input" maxlength="60" autocomplete="off" placeholder="Buscar por número de cuenta o banco...">
            </div>
            <select id="cuenta-banco-filter" class="filter-select" aria-label="Filtrar por banco">
                <option value="">Todos los bancos</option>
            </select>
            <div class="filter-toggle-group" role="group" aria-label="Tipo de cuenta" data-para="cuenta-filtro-tipo">
                <button type="button" class="filter-toggle active" data-valor="all" aria-pressed="true">Todas <span class="count" id="cta-cnt-all"></span></button>
                <button type="button" class="filter-toggle" data-valor="corriente" aria-pressed="false">Corrientes <span class="count" id="cta-cnt-corriente"></span></button>
                <button type="button" class="filter-toggle" data-valor="ahorros" aria-pressed="false">Ahorros <span class="count" id="cta-cnt-ahorros"></span></button>
            </div>
            <input type="hidden" id="cuenta-filtro-tipo" value="all">
            <button type="button" id="btn-clear-filters" class="btn-clear-filter" hidden><i class="fas fa-eraser"></i> Limpiar</button>
        </div>
        <div class="filter-info" id="cuentas-count" aria-live="polite">0 resultados</div>
    </div>

    <!-- Lista: la pinta ctas_empresa.js; el paginador agrega su pie -->
    <div class="table-container" data-lista>
        <div data-lista-scroll>
            <table id="cuentas-table" class="data-table" data-erp-movil data-erp-movil-titulo="3">
                <thead>
                    <tr>
                        <th>NIT empresa</th>
                        <th>Banco</th>
                        <th>Número de cuenta</th>
                        <th>Tipo</th>
                        <th class="col-acciones">Acciones</th>
                    </tr>
                </thead>
                <tbody id="cuentas-tbody"></tbody>
            </table>
        </div>
    </div>
</div>

<!-- MODAL: NUEVA CUENTA -->
<div id="modal-new-cuenta" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div>
                <h3>Nueva Cuenta Bancaria</h3>
                <p>Registre una cuenta de la empresa</p>
            </div>
            <button type="button" class="modal-close btn-close-new-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="new-cuenta-form" novalidate>
                <input type="hidden" name="btn_nuevo" value="1">
                <div class="form-field">
                    <label class="form-label">NIT de la Empresa</label>
                    <input type="text" id="new-id-empresa" class="form-input" value="<?= htmlspecialchars($id_empresa_fijo) ?>" disabled>
                    <span class="field-error" id="err-new-id-empresa"></span>
                    <p class="field-hint">Definido en Parámetros Generales. No se puede modificar desde aquí.</p>
                </div>
                <div class="form-field">
                    <div class="label-row">
                        <label class="form-label" for="new-id-banco">Banco <span class="required">*</span></label>
                        <button type="button" class="btn-link-inline" id="btn-open-banco-rapido">
                            <i class="fas fa-plus"></i> Nuevo banco
                        </button>
                    </div>
                    <select id="new-id-banco" name="sel_id_banco" class="form-input">
                        <option value=""><?= empty($bancos) ? 'No hay bancos registrados' : 'Seleccione...' ?></option>
                        <?php foreach ($bancos as $b): ?>
                            <option value="<?= htmlspecialchars($b['id_banco']) ?>"><?= htmlspecialchars($b['nom_banco']) ?></option>
                        <?php endforeach; ?>
                    </select>
                    <div id="new-banco-empty" class="empty-hint <?= empty($bancos) ? '' : 'hidden' ?>">
                        <i class="fas fa-info-circle"></i>
                        <span>Aún no hay bancos registrados.</span>
                        <button type="button" class="btn-link-inline" id="btn-empty-crear-banco">Crear banco aquí</button>
                    </div>
                    <span class="field-error" id="err-new-banco"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Número de Cuenta <span class="required">*</span></label>
                    <input type="text" id="new-cta-empresa" name="txt_cta_empresa" class="form-input" placeholder="Ej: 1234567890" minlength="10" maxlength="16">
                    <span class="field-error" id="err-new-cta"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Tipo de Cuenta</label>
                    <select id="new-tipocuenta" name="sel_tipocuenta" class="form-input">
                        <option value="false">Ahorros</option>
                        <option value="true">Corriente</option>
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

<!-- MODAL ANIDADO: CREAR BANCO SIN SALIR DE "NUEVA CUENTA" -->
<div id="modal-banco-rapido" class="modal-overlay modal-nested hidden">
    <div class="modal-box modal-box-sm">
        <div class="modal-header">
            <div>
                <h3>Nuevo Banco</h3>
                <p>Se agregará a la lista sin salir de la cuenta</p>
            </div>
            <button type="button" class="modal-close btn-close-banco-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="banco-rapido-form" novalidate>
                <input type="hidden" name="btn_nuevo_banco" value="1">
                <div class="form-field">
                    <label class="form-label" for="banco-rapido-id">Código del Banco <span class="required">*</span></label>
                    <input type="text" id="banco-rapido-id" name="txt_banco_id" class="form-input" placeholder="Ej: 0001234" minlength="6" maxlength="10">
                    <span class="field-error" id="err-banco-id"></span>
                </div>
                <div class="form-field">
                    <label class="form-label" for="banco-rapido-nombre">Nombre del Banco <span class="required">*</span></label>
                    <input type="text" id="banco-rapido-nombre" name="txt_banco_nombre" class="form-input" placeholder="Ej: Bancolombia" minlength="4" maxlength="50">
                    <span class="field-error" id="err-banco-nombre"></span>
                    <p class="field-hint">El banco se crea en estado Activo y queda seleccionado en la cuenta.</p>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary btn-cancel-banco-modal">Cancelar</button>
            <button type="button" id="banco-rapido-save" class="btn btn-primary"><i class="fas fa-save"></i> Guardar</button>
        </div>
    </div>
</div>

<!-- MODAL: EDITAR CUENTA -->
<div id="modal-edit-cuenta" class="modal-overlay hidden">
    <div class="modal-box">
        <div class="modal-header">
            <div>
                <h3>Editar Cuenta Bancaria</h3>
                <p>Modifique el banco o el tipo de cuenta</p>
            </div>
            <button type="button" class="modal-close btn-close-edit-modal" aria-label="Cerrar"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <form id="edit-cuenta-form" novalidate>
                <input type="hidden" name="btn_editar" value="1">
                <input type="hidden" name="hid_edit_id_empresa" id="edit-id-empresa-hid" value="">
                <input type="hidden" name="hid_edit_cta_empresa" id="edit-cta-empresa-hid" value="">
                <div class="form-field">
                    <label class="form-label">NIT de la Empresa</label>
                    <input type="text" id="edit-id-empresa-display" class="form-input" disabled>
                </div>
                <div class="form-field">
                    <label class="form-label">Número de Cuenta</label>
                    <input type="text" id="edit-cta-empresa-display" class="form-input" disabled>
                </div>
                <div class="form-field">
                    <label class="form-label">Banco <span class="required">*</span></label>
                    <select id="edit-id-banco" name="sel_edit_id_banco" class="form-input">
                        <option value="">Seleccione...</option>
                        <?php foreach ($bancos as $b): ?>
                            <option value="<?= htmlspecialchars($b['id_banco']) ?>"><?= htmlspecialchars($b['nom_banco']) ?></option>
                        <?php endforeach; ?>
                    </select>
                    <span class="field-error" id="err-edit-banco"></span>
                </div>
                <div class="form-field">
                    <label class="form-label">Tipo de Cuenta</label>
                    <select id="edit-tipocuenta" name="sel_edit_tipocuenta" class="form-input">
                        <option value="false">Ahorros</option>
                        <option value="true">Corriente</option>
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
const ctasData = <?= json_encode(array_values($ctas_empresa), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP) ?>;
</script>


<?php
$moduleContent = ob_get_clean();
echo $moduleContent;
?>
